import Foundation
import Observation
import Supabase

/// Store real: autenticação, RPCs `create_family`/`join_family`, upsert em
/// `locations` e realtime via postgres_changes.
@MainActor
@Observable
final class SupabaseFamilyStore: FamilyStore {
    let isDemo = false
    private(set) var phase: StorePhase = .loading
    private(set) var family: FamilyInfo? = nil
    private(set) var members: [FamilyMember] = []
    private(set) var trails: [String: [TrailPoint]] = [:]
    private(set) var alerts: [FamilyAlert] = []
    private(set) var places: [FamilyPlace] = []
    private(set) var trips: [FamilyTrip] = []
    /// Pausa o envio da própria posição — e publica isso, para a família ver
    /// "pausado" em vez de um pin envelhecendo sem explicação.
    var sharingPaused = false {
        didSet {
            guard oldValue != sharingPaused, !applyingRemotePause else { return }
            Task { await publishPauseState() }
        }
    }
    var errorMessage: String?

    private let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var profileCache: [UUID: ProfileRow] = [:]
    private var myID: UUID?
    private var lastHistoryInsert = Date.distantPast
    /// Evita que a pausa lida do banco seja reenviada como se fosse escolha
    /// nova do usuário.
    private var applyingRemotePause = false

    init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Linhas do banco

    private struct ProfileRow: Codable {
        let id: UUID
        let display_name: String
        let avatar_emoji: String
        let avatar_color: String
        /// Data URI do JPEG; ausente nos projetos sem a migração 0003.
        var avatar_photo: String?
    }

    private struct AlertRow: Codable {
        let id: UUID
        let family_id: UUID
        let sender_id: UUID
        let kind: String
        let latitude: Double?
        let longitude: Double?
        let place_hint: String?
        let created_at: Date
        let resolved_at: Date?
        let target_id: UUID?
    }

    private struct TripRow: Codable {
        let id: UUID
        let traveler_id: UUID
        let destination_name: String
        let destination_emoji: String
        let destination_latitude: Double
        let destination_longitude: Double
        let destination_radius_m: Int
        let started_at: Date
        let arrived_at: Date?
        let cancelled_at: Date?
    }

    private struct NewTripRow: Codable {
        let family_id: UUID
        let traveler_id: UUID
        let destination_name: String
        let destination_emoji: String
        let destination_latitude: Double
        let destination_longitude: Double
        let destination_radius_m: Int
    }

    private struct PlaceRow: Codable {
        let id: UUID
        let name: String
        let emoji: String
        let latitude: Double
        let longitude: Double
        let radius_m: Int
    }

    private struct NewPlaceRow: Codable {
        let family_id: UUID
        let created_by: UUID
        let name: String
        let emoji: String
        let latitude: Double
        let longitude: Double
        let radius_m: Int
    }

    private struct NewAlertRow: Codable {
        let family_id: UUID
        let sender_id: UUID
        let kind: String
        let latitude: Double?
        let longitude: Double?
        let place_hint: String?
        let target_id: UUID?
    }

    private struct FamilyRow: Codable {
        let id: UUID
        let name: String
        let invite_code: String
    }

    private struct MemberRow: Codable {
        let family_id: UUID
        let profile_id: UUID
    }

    private struct LocationRow: Codable {
        let profile_id: UUID
        let latitude: Double
        let longitude: Double
        let accuracy_m: Double?
        let speed_mps: Double?
        let heading: Double?
        let battery_pct: Int?
        let is_moving: Bool
        let state_since: Date
        let place_hint: String?
        let updated_at: Date
        /// Ausentes nos projetos sem a migração 0006.
        var sharing_paused: Bool?
        var paused_at: Date?
    }

    /// O upsert de posição não menciona as colunas da migração 0006: assim o
    /// app continua funcionando em projetos que ainda não a aplicaram, e a
    /// pausa é escrita à parte, por `publishPauseState`.
    private struct LocationUpsertRow: Codable {
        let profile_id: UUID
        let latitude: Double
        let longitude: Double
        let accuracy_m: Double?
        let speed_mps: Double?
        let heading: Double?
        let battery_pct: Int?
        let is_moving: Bool
        let state_since: Date
        let place_hint: String?
        let updated_at: Date
    }

    private struct HistoryRow: Codable {
        let profile_id: UUID
        let latitude: Double
        let longitude: Double
        let recorded_at: Date
    }

    // MARK: - Sessão

    func start() async {
        phase = .loading
        do {
            let session = try await client.auth.session
            myID = session.user.id
            try await loadEverything()
            await subscribeRealtime()
        } catch {
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        myID = session.user.id
        try await loadEverything()
        await subscribeRealtime()
    }

    func signUp(email: String, password: String, displayName: String, emoji: String) async throws {
        // O perfil é criado no banco pelo trigger `on_auth_user_created`
        // (migração 0002) a partir destes metadados — não pelo cliente, que
        // ainda não tem sessão quando a confirmação de e-mail está ligada.
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "display_name": .string(displayName),
                "avatar_emoji": .string(emoji),
                "avatar_color": .string("#D4FF3F"),
            ]
        )
        guard let session = response.session else {
            throw FamiliaError.emailConfirmationPending
        }
        myID = session.user.id
        // O trigger já criou o perfil; este upsert cobre projetos sem a
        // migração 0002 aplicada e garante o nome/emoji escolhidos aqui.
        let profile = ProfileRow(id: session.user.id, display_name: displayName,
                                 avatar_emoji: emoji, avatar_color: "#D4FF3F")
        try await client.from("profiles").upsert(profile).execute()
        try await loadEverything()
        await subscribeRealtime()
    }

    func signOut() async {
        realtimeTask?.cancel()
        if let channel = realtimeChannel {
            await client.removeChannel(channel)
        }
        realtimeChannel = nil
        try? await client.auth.signOut()
        myID = nil
        family = nil
        members = []
        trails = [:]
        phase = .signedOut
    }

    // MARK: - Família

    func createFamily(named name: String) async throws {
        let fam: FamilyRow = try await client
            .rpc("create_family", params: ["family_name": name])
            .execute().value
        family = FamilyInfo(id: fam.id.uuidString, name: fam.name, inviteCode: fam.invite_code)
        try await loadEverything()
        await subscribeRealtime()
    }

    func joinFamily(code: String) async throws {
        let fam: FamilyRow = try await client
            .rpc("join_family", params: ["code": code])
            .execute().value
        family = FamilyInfo(id: fam.id.uuidString, name: fam.name, inviteCode: fam.invite_code)
        try await loadEverything()
        await subscribeRealtime()
    }

    func leaveFamily() async throws {
        guard let myID, let family else { return }
        try await client.from("family_members")
            .delete()
            .eq("family_id", value: family.id)
            .eq("profile_id", value: myID.uuidString)
            .execute()
        self.family = nil
        members = []
        phase = .noFamily
    }

    /// Apagar um usuário do Auth exige a chave `service_role`, que ignora o RLS
    /// e por isso jamais pode estar dentro do app. Quem apaga é a Edge Function
    /// `delete-account`, que descobre de quem é a conta pelo próprio JWT — não
    /// existe parâmetro dizendo "qual usuário", então não dá para pedir a
    /// exclusão de outra pessoa.
    func deleteAccount() async throws {
        guard myID != nil else { return }
        try await client.functions.invoke("delete-account")
        // A sessão local não vale mais nada: limpa tudo e volta para o início.
        await signOut()
    }

    func updateProfile(name: String, emoji: String) async throws {
        guard let myID else { return }
        try await client.from("profiles")
            .update(["display_name": name, "avatar_emoji": emoji])
            .eq("id", value: myID.uuidString)
            .execute()
        try await loadEverything()
    }

    // MARK: - Carregamento

    private func loadEverything() async throws {
        guard let myID else {
            phase = .signedOut
            return
        }

        // Garante que existe um perfil (contas antigas podem não ter).
        let profiles: [ProfileRow] = try await client.from("profiles")
            .select().eq("id", value: myID.uuidString).execute().value
        if profiles.isEmpty {
            let profile = ProfileRow(id: myID, display_name: "Eu",
                                     avatar_emoji: "🙂", avatar_color: "#D4FF3F")
            _ = try? await client.from("profiles").insert(profile).execute()
        }

        // Família do usuário (RLS já limita às famílias em que ele está).
        let families: [FamilyRow] = try await client.from("families")
            .select().limit(1).execute().value
        guard let fam = families.first else {
            family = nil
            phase = .noFamily
            return
        }
        family = FamilyInfo(id: fam.id.uuidString, name: fam.name, inviteCode: fam.invite_code)

        let memberRows: [MemberRow] = try await client.from("family_members")
            .select().eq("family_id", value: fam.id.uuidString).execute().value
        let ids = memberRows.map { $0.profile_id.uuidString }

        let profileRows: [ProfileRow] = try await client.from("profiles")
            .select().in("id", values: ids).execute().value
        profileCache = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id, $0) })

        try await refreshLocations()
        // As migrações 0003/0004 podem não ter sido aplicadas: sem elas as
        // tabelas não existem e o app segue funcionando sem alarme e lugares.
        try? await refreshAlerts()
        try? await refreshPlaces()
        try? await refreshTrips()
        phase = .ready
    }

    private func refreshLocations() async throws {
        guard let myID else { return }
        let ids = profileCache.keys.map(\.uuidString)
        guard !ids.isEmpty else { return }
        let rows: [LocationRow] = try await client.from("locations")
            .select().in("profile_id", values: ids).execute().value
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.profile_id, $0) })

        members = profileCache.values.map { profile in
            let loc = byID[profile.id]
            return FamilyMember(
                id: profile.id.uuidString,
                name: profile.display_name,
                emoji: profile.avatar_emoji,
                colorHex: profile.avatar_color,
                latitude: loc?.latitude ?? 0,
                longitude: loc?.longitude ?? 0,
                speedMps: loc?.speed_mps ?? 0,
                isMoving: loc?.is_moving ?? false,
                stateSince: loc?.state_since ?? .now,
                batteryPct: loc?.battery_pct ?? 0,
                placeHint: loc?.place_hint,
                updatedAt: loc?.updated_at ?? .distantPast,
                isSelf: profile.id == myID,
                photo: Self.decodePhoto(profile.avatar_photo),
                sharingPaused: loc?.sharing_paused ?? false,
                pausedAt: loc?.paused_at
            )
        }.filter { $0.latitude != 0 || $0.longitude != 0 || $0.isSelf }

        // A pausa vive no banco: reinstalar o app ou trocar de aparelho não
        // pode fazer a posição voltar a ser enviada sem a pessoa pedir.
        if let mine = byID[myID], (mine.sharing_paused ?? false) != sharingPaused {
            applyingRemotePause = true
            sharingPaused = mine.sharing_paused ?? false
            applyingRemotePause = false
        }

        // Alimenta as trilhas em memória com cada atualização recebida.
        let now = Date.now
        for member in members {
            var trail = trails[member.id] ?? []
            if let last = trail.last {
                if last.latitude != member.latitude || last.longitude != member.longitude {
                    trail.append(TrailPoint(latitude: member.latitude,
                                            longitude: member.longitude, recordedAt: now))
                }
            } else {
                trail.append(TrailPoint(latitude: member.latitude,
                                        longitude: member.longitude, recordedAt: now))
            }
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
            trails[member.id] = trail
        }
    }

    // MARK: - Realtime

    private func subscribeRealtime() async {
        realtimeTask?.cancel()
        if let channel = realtimeChannel {
            await client.removeChannel(channel)
            realtimeChannel = nil
        }
        guard phase == .ready else { return }

        let channel = client.channel("familia-realtime")
        let locationChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "locations")
        let alertChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "alerts")
        let placeChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "places")
        let tripChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "trips")
        realtimeChannel = channel
        do {
            // `subscribe()` (depreciado) engolia a falha: o app ficava sem
            // tempo real e sem dizer nada, e o mapa só mudava ao reabrir.
            try await channel.subscribeWithError()
        } catch {
            errorMessage = "Sem atualização em tempo real: \(error.localizedDescription). Puxe para atualizar."
            return
        }

        realtimeTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await action in locationChanges {
                        guard let self, !Task.isCancelled else { return }
                        await self.handleLocationChange(action)
                    }
                }
                group.addTask { [weak self] in
                    for await _ in alertChanges {
                        guard let self, !Task.isCancelled else { return }
                        try? await self.refreshAlerts()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in placeChanges {
                        guard let self, !Task.isCancelled else { return }
                        try? await self.refreshPlaces()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in tripChanges {
                        guard let self, !Task.isCancelled else { return }
                        try? await self.refreshTrips()
                    }
                }
            }
        }
    }

    private func handleLocationChange(_ action: AnyAction) async {
        let record: [String: AnyJSON]
        switch action {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        case .delete(let a): record = a.oldRecord
        }
        var changedID: UUID?
        if case .string(let s)? = record["profile_id"] { changedID = UUID(uuidString: s) }

        // Perfil fora do cache = alguém entrou na família depois do app abrir;
        // só recarregar posições deixaria a pessoa invisível até reiniciar.
        if let changedID, profileCache[changedID] == nil {
            try? await loadEverything()
        } else {
            try? await refreshLocations()
        }
    }

    func refresh() async {
        guard myID != nil else { return }
        try? await loadEverything()
    }

    // MARK: - Publicação da própria localização

    func publishOwnLocation(_ snapshot: OwnLocationSnapshot) async {
        guard let myID, phase == .ready, !sharingPaused else { return }
        let row = LocationUpsertRow(
            profile_id: myID,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            accuracy_m: snapshot.accuracyM,
            speed_mps: snapshot.speedMps,
            heading: snapshot.heading,
            battery_pct: snapshot.batteryPct,
            is_moving: snapshot.isMoving,
            state_since: snapshot.stateSince,
            place_hint: snapshot.placeHint,
            updated_at: .now
        )
        do {
            try await client.from("locations").upsert(row).execute()
            // Histórico a cada 30 s no máximo.
            if Date.now.timeIntervalSince(lastHistoryInsert) > 30 {
                lastHistoryInsert = .now
                let hist = HistoryRow(profile_id: myID, latitude: snapshot.latitude,
                                      longitude: snapshot.longitude, recorded_at: .now)
                _ = try? await client.from("location_history").insert(hist).execute()
            }
        } catch {
            errorMessage = "Falha ao enviar localização: \(error.localizedDescription)"
        }
    }

    /// Publica a pausa como um `update` (nunca um insert): quem nunca enviou
    /// posição não tem o que pausar, e um insert precisaria inventar
    /// coordenadas.
    private func publishPauseState() async {
        guard let myID else { return }
        let paused = sharingPaused
        var values: [String: AnyJSON] = ["sharing_paused": .bool(paused)]
        values["paused_at"] = paused
            ? .string(ISO8601DateFormatter().string(from: .now))
            : .null
        do {
            try await client.from("locations")
                .update(values)
                .eq("profile_id", value: myID.uuidString)
                .execute()
            try? await refreshLocations()
        } catch {
            // Sem a migração 0006 a coluna não existe: a pausa continua valendo
            // neste aparelho, só não fica visível para a família.
            errorMessage = paused
                ? "Sua posição parou de ser enviada, mas não deu para avisar a família da pausa."
                : "Sua posição voltou a ser enviada, mas não deu para avisar a família."
        }
    }

    // MARK: - Alertas

    func sendAlert(kind: FamilyAlert.Kind, targetID: String?) async throws {
        guard let myID, let family, let famID = UUID(uuidString: family.id) else { return }
        let me = selfMember
        let row = NewAlertRow(
            family_id: famID, sender_id: myID, kind: kind.rawValue,
            latitude: me?.latitude, longitude: me?.longitude, place_hint: me?.placeHint,
            target_id: targetID.flatMap(UUID.init(uuidString:))
        )
        try await client.from("alerts").insert(row).execute()
        try? await refreshAlerts()
    }

    func resolveAlert(id: String) async {
        guard let myID, let uuid = UUID(uuidString: id) else { return }
        do {
            try await client.from("alerts")
                .update(["resolved_at": AnyJSON.string(ISO8601DateFormatter().string(from: .now)),
                         "resolved_by": .string(myID.uuidString)])
                .eq("id", value: uuid.uuidString)
                .execute()
            try? await refreshAlerts()
        } catch {
            errorMessage = "Não foi possível encerrar o alerta: \(error.localizedDescription)"
        }
    }

    /// Alertas das últimas 12 h — o suficiente para não perder um SOS recente
    /// sem carregar histórico antigo toda vez.
    private func refreshAlerts() async throws {
        guard let family else { return }
        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-12 * 3600))
        let rows: [AlertRow] = try await client.from("alerts")
            .select()
            .eq("family_id", value: family.id)
            .gte("created_at", value: since)
            .order("created_at", ascending: false)
            .limit(20)
            .execute().value

        alerts = rows.map { row in
            let sender = profileCache[row.sender_id]
            return FamilyAlert(
                id: row.id.uuidString,
                kind: FamilyAlert.Kind(rawValue: row.kind) ?? .ping,
                senderID: row.sender_id.uuidString,
                senderName: sender?.display_name ?? "Família",
                senderEmoji: sender?.avatar_emoji ?? "🙂",
                latitude: row.latitude, longitude: row.longitude,
                placeHint: row.place_hint,
                createdAt: row.created_at, resolvedAt: row.resolved_at,
                targetID: row.target_id?.uuidString
            )
        }
    }

    // MARK: - Lugares

    func addPlace(name: String, emoji: String, latitude: Double, longitude: Double,
                  radiusM: Double) async throws {
        guard let myID, let family, let famID = UUID(uuidString: family.id) else { return }
        let row = NewPlaceRow(family_id: famID, created_by: myID, name: name, emoji: emoji,
                              latitude: latitude, longitude: longitude,
                              radius_m: Int(radiusM.rounded()))
        try await client.from("places").insert(row).execute()
        try? await refreshPlaces()
    }

    func deletePlace(id: String) async throws {
        guard let uuid = UUID(uuidString: id) else { return }
        try await client.from("places").delete().eq("id", value: uuid.uuidString).execute()
        try? await refreshPlaces()
    }

    private func refreshPlaces() async throws {
        guard let family else { return }
        let rows: [PlaceRow] = try await client.from("places")
            .select()
            .eq("family_id", value: family.id)
            .order("created_at", ascending: true)
            .execute().value
        places = rows.map {
            FamilyPlace(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji,
                        latitude: $0.latitude, longitude: $0.longitude,
                        radiusM: Double($0.radius_m))
        }
    }

    // MARK: - Viagens

    func startTrip(destinationName: String, emoji: String, latitude: Double,
                   longitude: Double, radiusM: Double) async throws {
        guard let myID, let family, let famID = UUID(uuidString: family.id) else { return }
        let row = NewTripRow(family_id: famID, traveler_id: myID,
                             destination_name: destinationName, destination_emoji: emoji,
                             destination_latitude: latitude, destination_longitude: longitude,
                             destination_radius_m: Int(radiusM.rounded()))
        try await client.from("trips").insert(row).execute()
        try? await refreshTrips()
    }

    func finishTrip(id: String, arrived: Bool) async throws {
        guard let uuid = UUID(uuidString: id) else { return }
        let stamp = ISO8601DateFormatter().string(from: .now)
        try await client.from("trips")
            .update([arrived ? "arrived_at" : "cancelled_at": AnyJSON.string(stamp)])
            .eq("id", value: uuid.uuidString)
            .execute()
        try? await refreshTrips()
    }

    /// Viagens das últimas 12 h: o suficiente para as ativas e um histórico curto.
    private func refreshTrips() async throws {
        guard let family else { return }
        let since = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-12 * 3600))
        let rows: [TripRow] = try await client.from("trips")
            .select()
            .eq("family_id", value: family.id)
            .gte("started_at", value: since)
            .order("started_at", ascending: false)
            .limit(30)
            .execute().value
        trips = rows.map { row in
            let traveler = profileCache[row.traveler_id]
            return FamilyTrip(
                id: row.id.uuidString,
                travelerID: row.traveler_id.uuidString,
                travelerName: traveler?.display_name ?? "Família",
                travelerEmoji: traveler?.avatar_emoji ?? "🙂",
                destinationName: row.destination_name,
                destinationEmoji: row.destination_emoji,
                destinationLatitude: row.destination_latitude,
                destinationLongitude: row.destination_longitude,
                destinationRadiusM: Double(row.destination_radius_m),
                startedAt: row.started_at,
                arrivedAt: row.arrived_at, cancelledAt: row.cancelled_at
            )
        }
    }

    // MARK: - Foto de perfil

    func updatePhoto(_ jpeg: Data?) async throws {
        guard let myID else { return }
        let value = jpeg.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        try await client.from("profiles")
            .update(["avatar_photo": value.map { AnyJSON.string($0) } ?? AnyJSON.null])
            .eq("id", value: myID.uuidString)
            .execute()
        try await loadEverything()
    }

    /// Converte o data URI guardado no banco de volta para JPEG.
    private static func decodePhoto(_ dataURI: String?) -> Data? {
        guard let dataURI, let comma = dataURI.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...]))
    }

    func loadTrail(for memberID: String) async {
        guard let uuid = UUID(uuidString: memberID) else { return }
        do {
            let rows: [HistoryRow] = try await client.from("location_history")
                .select()
                .eq("profile_id", value: uuid.uuidString)
                .order("recorded_at", ascending: false)
                .limit(240)
                .execute().value
            trails[memberID] = rows.reversed().map {
                TrailPoint(latitude: $0.latitude, longitude: $0.longitude, recordedAt: $0.recorded_at)
            }
        } catch {
            // Mantém a trilha em memória caso o fetch falhe.
        }
    }
}
