import SwiftUI
import Observation
import MapKit
import CoreLocation
import WidgetKit

@main
struct FamiliaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // Verde que acompanha o modo do sistema: oliva no claro, limão
                // no escuro. As telas que são escuras *sempre* — onboarding,
                // globo, Live Activity — continuam pedindo `.accentLime`.
                .tint(.accentAdaptive)
        }
    }
}

/// Coordenador do app: escolhe o store (demo ou Supabase), controla o
/// onboarding, a seleção no mapa, o LocationEngine e a Live Activity.
@MainActor
@Observable
final class AppModel {
    let store: any FamilyStore
    let locationEngine = LocationEngine()
    let liveActivity = LiveActivityManager()
    let alertCenter = AlertCenter()

    /// Quem o usuário escolheu acompanhar na tela de bloqueio / Dynamic Island.
    /// `nil` = ninguém, e aí não existe Live Activity nenhuma.
    var pinnedMemberID: String? {
        didSet {
            UserDefaults.standard.set(pinnedMemberID, forKey: "pinnedMemberID")
            refreshLiveActivity()
        }
    }
    /// Avisar quando alguém da família chega ou sai de um lugar marcado.
    var placeAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(placeAlertsEnabled, forKey: "placeAlertsEnabled") }
    }
    /// O que avisar sobre cada pessoa (id → `PlaceAlertMode`). Fica só neste
    /// aparelho: é escolha de quem recebe, não de quem é observado.
    private var placeAlertModesRaw: [String: String] {
        didSet { UserDefaults.standard.set(placeAlertModesRaw, forKey: "placeAlertModes") }
    }
    /// Avisar quando alguém da família pausa (ou retoma) o compartilhamento.
    var pauseAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(pauseAlertsEnabled, forKey: "pauseAlertsEnabled") }
    }
    /// Avisos comuns silenciados até este instante. O alarme de pânico ignora
    /// a soneca — silenciar tudo menos a emergência é justamente o objetivo.
    var alertsSnoozedUntil: Date? {
        didSet { UserDefaults.standard.set(alertsSnoozedUntil, forKey: "alertsSnoozedUntil") }
    }

    /// Chave do ajuste por lugar. Sem `placeID`, é o padrão da pessoa.
    private func alertKey(_ memberID: String, _ placeID: String?) -> String {
        placeID.map { "\(memberID)|\($0)" } ?? memberID
    }

    /// Padrão da pessoa, usado quando o lugar não tem regra própria.
    func defaultPlaceAlertMode(for memberID: String) -> PlaceAlertMode {
        placeAlertModesRaw[memberID].flatMap(PlaceAlertMode.init(rawValue:)) ?? .both
    }

    /// Regra específica de um lugar, ou `nil` quando ele herda o padrão.
    func placeAlertOverride(for memberID: String, placeID: String) -> PlaceAlertMode? {
        placeAlertModesRaw[alertKey(memberID, placeID)].flatMap(PlaceAlertMode.init(rawValue:))
    }

    /// O que vale de fato para esta pessoa neste lugar.
    func placeAlertMode(for memberID: String, placeID: String) -> PlaceAlertMode {
        placeAlertOverride(for: memberID, placeID: placeID)
            ?? defaultPlaceAlertMode(for: memberID)
    }

    func setDefaultPlaceAlertMode(_ mode: PlaceAlertMode, for memberID: String) {
        placeAlertModesRaw[memberID] = mode.rawValue
    }

    /// `nil` faz o lugar voltar a herdar o padrão da pessoa.
    func setPlaceAlertOverride(_ mode: PlaceAlertMode?, for memberID: String, placeID: String) {
        placeAlertModesRaw[alertKey(memberID, placeID)] = mode?.rawValue
    }

    /// Quantos lugares fogem do padrão desta pessoa.
    func placeAlertOverrideCount(for memberID: String) -> Int {
        store.places.count { placeAlertOverride(for: memberID, placeID: $0.id) != nil }
    }

    /// A pessoa gera algum aviso, em qualquer lugar?
    func hasAnyPlaceAlert(for memberID: String) -> Bool {
        if store.places.isEmpty { return defaultPlaceAlertMode(for: memberID).isOn }
        return store.places.contains { placeAlertMode(for: memberID, placeID: $0.id).isOn }
    }

    /// Resumo para a linha dos ajustes ("Ana e Pai" / "ninguém").
    var placeAlertsSummary: String {
        guard placeAlertsEnabled else { return "Desligado" }
        let names = store.sortedMembers
            .filter { !$0.isSelf && hasAnyPlaceAlert(for: $0.id) }
            .map(\.name)
        if names.isEmpty { return "Ninguém selecionado" }
        if names.count <= 2 { return names.joined(separator: " e ") }
        return "\(names.prefix(2).joined(separator: ", ")) e mais \(names.count - 2)"
    }

    // MARK: - Soneca dos avisos

    /// Avisos comuns estão silenciados agora?
    var alertsSnoozed: Bool {
        guard let alertsSnoozedUntil else { return false }
        return alertsSnoozedUntil > .now
    }

    /// Um aviso comum pode tocar? O SOS nunca passa por aqui.
    private var canNotify: Bool { !alertsSnoozed }

    /// "Silenciado até 14:30" / "Silenciado até amanhã, 08:00".
    var snoozeSummary: String {
        guard let until = alertsSnoozedUntil, alertsSnoozed else { return "Tocando normalmente" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        let amanha = !Calendar.current.isDateInToday(until)
        return "Silenciado até \(amanha ? "amanhã, " : "")\(f.string(from: until))"
    }

    func snoozeAlerts(hours: Int) {
        alertsSnoozedUntil = Date.now.addingTimeInterval(Double(hours) * 3600)
    }

    /// Silencia até as 8h do dia seguinte — a versão "boa noite" da soneca.
    func snoozeAlertsUntilMorning() {
        let calendar = Calendar.current
        let amanha = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        alertsSnoozedUntil = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: amanha)
    }

    func cancelSnooze() { alertsSnoozedUntil = nil }

    // MARK: - Pausa do compartilhamento

    /// Estado de pausa na última verificação, por pessoa.
    private var lastPausedByMember: [String: Bool] = [:]
    /// Como nas chegadas, a primeira leitura só registra: abrir o app não pode
    /// anunciar uma pausa que já estava valendo antes.
    private var pauseTrackingPrimed = false

    func checkPauseTransitions() {
        guard store.phase == .ready else { return }
        var current: [String: Bool] = [:]
        for member in store.members { current[member.id] = member.sharingPaused }
        defer {
            lastPausedByMember = current
            pauseTrackingPrimed = true
        }
        guard pauseTrackingPrimed, pauseAlertsEnabled, canNotify else { return }

        for (memberID, paused) in current {
            guard let previous = lastPausedByMember[memberID], previous != paused,
                  let member = store.member(id: memberID), !member.isSelf else { continue }
            alertCenter.postSharingPause(member: member, paused: paused)
        }
    }

    /// Último lugar conhecido de cada pessoa (`""` = fora de qualquer lugar).
    private var lastPlaceByMember: [String: String] = [:]
    /// A primeira leitura só registra o estado — sem isso, abrir o app avisaria
    /// "chegou" para todo mundo que já estava em casa.
    private var placeTrackingPrimed = false

    /// Alerta sendo exibido em tela cheia. Um sheet aberto ficaria por cima de
    /// qualquer overlay, então ele sai de cena enquanto o alarme está na tela.
    var presentedAlert: FamilyAlert? {
        didSet {
            if presentedAlert != nil {
                showFamilySheet = false
                showSettings = false
            } else if !showGlobe {
                showFamilySheet = true
            }
        }
    }
    /// IDs já notificados, para não repetir o alarme a cada atualização.
    private var announcedAlertIDs: Set<String> = []

    var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }
    var selectedMemberID: String?
    /// Código de convite recém-criado que ainda precisa ser mostrado. Segura o
    /// app no onboarding mesmo com a fase já em `.ready`, senão a família é
    /// criada e o usuário nunca vê o código para convidar alguém.
    var pendingInviteCode: String?
    /// Ligada antes de chamar `createFamily`, porque a fase vira `.ready`
    /// dentro da chamada — sem isso a raiz troca para o mapa no meio do
    /// caminho e o onboarding é recriado do zero.
    var isCreatingFamily = false
    var showFamilySheet = true
    var showSettings = false
    var showGlobe = false

    /// A partir desta distância o mapa plano perde sentido e o globo entra.
    static let farAwayThreshold: Double = 1_000_000

    /// Só para testes: mantém o alarme sem a tela cheia, para inspecionar o
    /// mapa por baixo (`SIMCTL_CHILD_FAMILIA_NO_SOS_OVERLAY=1`).
    static var suppressAlertOverlay: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["FAMILIA_NO_SOS_OVERLAY"] == "1"
        #else
        false
        #endif
    }

    /// Membro mais distante de você, se estiver "do outro lado do mundo".
    var farAwayMember: FamilyMember? {
        guard let me = store.selfMember else { return nil }
        let farthest = store.members.filter { !$0.isSelf && ($0.latitude != 0 || $0.longitude != 0) }
            .max { GlobeMath.distanceMeters(me, $0) < GlobeMath.distanceMeters(me, $1) }
        guard let farthest, GlobeMath.distanceMeters(me, farthest) > Self.farAwayThreshold else { return nil }
        return farthest
    }
    /// Live Activity habilitada pelo usuário (Settings).
    var liveActivityEnabled: Bool {
        didSet { UserDefaults.standard.set(liveActivityEnabled, forKey: "liveActivityEnabled") }
    }

    private var started = false
    private var activityTask: Task<Void, Never>?

    init() {
        // `FAMILIA_FORCE_DEMO=1` roda a família fake mesmo com o Supabase
        // configurado — é como se testa layout com uma família grande sem
        // inventar contas de verdade no banco de alguém.
        #if DEBUG
        let forceDemo = ProcessInfo.processInfo.environment["FAMILIA_FORCE_DEMO"] == "1"
        #else
        let forceDemo = false
        #endif
        store = (Config.isConfigured && !forceDemo) ? SupabaseFamilyStore() : MockFamilyStore()
        onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        liveActivityEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
        pinnedMemberID = UserDefaults.standard.string(forKey: "pinnedMemberID")
        placeAlertsEnabled = UserDefaults.standard.object(forKey: "placeAlertsEnabled") as? Bool ?? true
        placeAlertModesRaw = UserDefaults.standard.dictionary(forKey: "placeAlertModes") as? [String: String] ?? [:]
        pauseAlertsEnabled = UserDefaults.standard.object(forKey: "pauseAlertsEnabled") as? Bool ?? true
        alertsSnoozedUntil = UserDefaults.standard.object(forKey: "alertsSnoozedUntil") as? Date
        lowBatteryAnnounced = Set(UserDefaults.standard.stringArray(forKey: "lowBatteryAnnounced") ?? [])
        announcedTripEvents = Set(UserDefaults.standard.stringArray(forKey: "announcedTripEvents") ?? [])
    }

    /// O globo é um overlay na raiz (não um modal), então o sheet da família
    /// precisa sair de cena enquanto ele está aberto — sheets ficam acima de
    /// qualquer overlay.
    func openGlobe() {
        showGlobe = true
        showFamilySheet = false
    }

    func closeGlobe() {
        showGlobe = false
        showFamilySheet = true
    }

    /// Membro selecionado no mapa, se houver.
    var selectedMember: FamilyMember? { store.member(id: selectedMemberID) }

    /// Quem a Live Activity observa: **só** quem foi marcado explicitamente.
    var watchedMember: FamilyMember? { store.member(id: pinnedMemberID) }

    func isPinned(_ member: FamilyMember) -> Bool { member.id == pinnedMemberID }

    /// Quem está com alarme de pânico em aberto — o mapa marca essas pessoas
    /// em vermelho.
    var membersInEmergency: Set<String> {
        Set(store.alerts.filter { $0.isActive && $0.kind == .sos }.map(\.senderID))
    }

    /// Alarme de pânico em aberto, se houver.
    ///
    /// Existe porque "Dispensar" na tela cheia só fechava a tela: o alarme
    /// continuava ativo no banco, o pin vermelho e a tela de bloqueio junto, e
    /// não sobrava nenhum caminho para cancelar. Ficava vermelho para sempre.
    var activeSOS: FamilyAlert? {
        store.alerts.first { $0.isActive && $0.kind == .sos }
    }

    /// O alarme em aberto é meu?
    var activeSOSIsMine: Bool {
        activeSOS.map { $0.senderID == store.selfMember?.id } ?? false
    }

    /// Encerra o alarme em aberto, tenha ele sido aberto por quem for.
    func cancelActiveSOS() {
        guard let alert = activeSOS else { return }
        alertCenter.clear(alertID: alert.id)
        presentedAlert = nil
        Task { await store.resolveAlert(id: alert.id) }
    }

    /// Reabre a tela cheia de um alarme que foi dispensado.
    func reopenActiveSOS() {
        guard let alert = activeSOS else { return }
        presentedAlert = alert
    }

    /// Marca/desmarca alguém para aparecer na tela de bloqueio.
    func togglePin(_ member: FamilyMember) {
        let willPin = !isPinned(member)
        pinnedMemberID = willPin ? member.id : nil
        if willPin { Task { await alertCenter.requestPermission() } }
    }

    /// Quem a pílula de status do mapa mostra — independente da tela de
    /// bloqueio, que é opt-in.
    var pillMember: FamilyMember? { selectedMember ?? store.selfMember }

    // MARK: - Chegadas e saídas

    /// Compara o lugar atual de cada pessoa com o da última verificação e
    /// avisa nas transições. Roda no aparelho de cada um, sem servidor: como o
    /// app fica vivo em segundo plano pela localização, a assinatura realtime
    /// continua entregando as posições.
    func checkPlaceTransitions() {
        guard store.phase == .ready, !store.places.isEmpty else { return }

        var current: [String: String] = [:]
        for member in store.members where member.latitude != 0 || member.longitude != 0 {
            current[member.id] = store.place(for: member)?.id ?? ""
        }
        defer {
            lastPlaceByMember = current
            placeTrackingPrimed = true
        }
        guard placeTrackingPrimed, placeAlertsEnabled, canNotify else { return }

        for (memberID, placeID) in current {
            guard let previous = lastPlaceByMember[memberID], previous != placeID,
                  let member = store.member(id: memberID), !member.isSelf else { continue }
            // A regra é a do lugar em questão: o de chegada, ou o de saída.
            if !placeID.isEmpty, let place = store.places.first(where: { $0.id == placeID }),
               placeAlertMode(for: memberID, placeID: placeID).allows(arrived: true) {
                alertCenter.postPlaceEvent(member: member, place: place, arrived: true)
            } else if placeID.isEmpty, !previous.isEmpty,
                      let place = store.places.first(where: { $0.id == previous }),
                      placeAlertMode(for: memberID, placeID: previous).allows(arrived: false) {
                alertCenter.postPlaceEvent(member: member, place: place, arrived: false)
            }
        }
    }

    // MARK: - Bateria e viagens

    /// Quem já foi avisado por bateria baixa (limpa quando recarrega, para o
    /// aviso poder acontecer de novo na próxima descarga).
    ///
    /// Persistido: só na memória, fechar e abrir o app fazia a notificação de
    /// bateria baixa tocar de novo para a mesma descarga.
    private var lowBatteryAnnounced: Set<String> {
        didSet { UserDefaults.standard.set(Array(lowBatteryAnnounced), forKey: "lowBatteryAnnounced") }
    }
    private static let lowBatteryThreshold = 15
    private static let batteryRecoveredThreshold = 25

    /// Quais eventos de viagem já foram tratados (`tripID|evento`). Também
    /// persistido: sem isso, reabrir o app reanunciava "fulano parou há 2 h"
    /// de uma viagem que continua em andamento.
    private var announcedTripEvents: Set<String> {
        didSet { UserDefaults.standard.set(Array(announcedTripEvents), forKey: "announcedTripEvents") }
    }
    /// 12 min pegava fila de semáforo e engarrafamento comum; 25 já é uma
    /// parada de verdade, e ainda assim o aviso não trata como emergência.
    private static let stallMinutes = 25

    /// Assinatura do último retrato gravado. O WidgetKit tem orçamento diário
    /// de recargas: chamar `reloadTimelines` a cada posição recebida (dezenas
    /// por minuto numa família grande) esgota o orçamento e o widget congela.
    private var lastSnapshotSignature: String?

    /// Grava o retrato da família para o widget da tela de início.
    func updateWidgetSnapshot() {
        guard store.phase == .ready else { return }
        let emergencias = membersInEmergency
        let snapshot = FamilySnapshot(
            familyName: store.family?.name ?? "Família",
            members: store.sortedMembers.map { member in
                FamilySnapshot.Entry(
                    id: member.id, name: member.isSelf ? "Você" : member.name,
                    emoji: member.emoji, isMoving: member.isMoving,
                    stateSince: member.stateSince, batteryPct: member.batteryPct,
                    place: store.locationLabel(for: member),
                    isEmergency: emergencias.contains(member.id),
                    isPaused: member.sharingPaused,
                    vehicleKmh: member.isInVehicle ? Int(member.speedKmh.rounded()) : nil
                )
            },
            updatedAt: .now
        )
        // `updatedAt` fica de fora da assinatura de propósito: ele muda sempre,
        // e o widget não o mostra.
        let signature = snapshot.members.map {
            "\($0.id)|\($0.name)|\($0.emoji)|\($0.isMoving)|\($0.batteryPct)|\($0.place ?? "")|\($0.isEmergency)|\($0.isPaused == true)|\($0.vehicleKmh ?? -1)"
        }.joined(separator: ";") + "|\(snapshot.familyName)"
        guard signature != lastSnapshotSignature else { return }
        lastSnapshotSignature = signature

        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "FamilyWidget")
    }

    func checkBatteryAndTrips() {
        guard store.phase == .ready else { return }

        // Agora que a lista é persistida, ela cresceria para sempre. O store só
        // carrega as viagens das últimas 12 h; o que saiu dessa janela não volta.
        if !store.trips.isEmpty {
            let conhecidas = Set(store.trips.map(\.id))
            let vivas = announcedTripEvents.filter { evento in
                conhecidas.contains(evento.split(separator: "|").first.map(String.init) ?? "")
            }
            if vivas.count != announcedTripEvents.count { announcedTripEvents = vivas }
        }

        // Bateria acabando de alguém da família.
        for member in store.members where !member.isSelf {
            if member.batteryPct > 0, member.batteryPct <= Self.lowBatteryThreshold {
                if !lowBatteryAnnounced.contains(member.id), placeAlertsEnabled, canNotify {
                    lowBatteryAnnounced.insert(member.id)
                    alertCenter.postLowBattery(member: member)
                }
            } else if member.batteryPct >= Self.batteryRecoveredThreshold {
                lowBatteryAnnounced.remove(member.id)
            }
        }

        // Minha viagem: eu sou quem tem a melhor posição, então é o meu
        // aparelho que marca a chegada. A trava é necessária porque esta função
        // roda a cada atualização de posição da família e `myActiveTrip` só
        // deixa de existir quando o `update` volta do servidor — sem ela, uma
        // rajada de atualizações disparava vários `finishTrip` para a mesma
        // chegada, cada um provocando um refresh que disparava o próximo.
        if let trip = store.myActiveTrip, let me = store.selfMember,
           trip.hasArrived(latitude: me.latitude, longitude: me.longitude),
           !announcedTripEvents.contains("\(trip.id)|arriving") {
            announcedTripEvents.insert("\(trip.id)|arriving")
            Task { try? await store.finishTrip(id: trip.id, arrived: true) }
        }

        // Viagens dos outros: chegada, parada longa e atraso.
        for trip in store.activeTrips where trip.travelerID != store.selfMember?.id {
            guard let traveler = store.member(id: trip.travelerID) else { continue }

            if !traveler.isMoving {
                let parado = Int(Date.now.timeIntervalSince(traveler.stateSince) / 60)
                if parado >= Self.stallMinutes {
                    announceTrip(.stalled(minutes: parado), trip: trip, key: "stalled")
                }
            }
        }

        // Chegadas: avisa quem estava acompanhando.
        for trip in store.trips where trip.arrivedAt != nil
            && trip.travelerID != store.selfMember?.id {
            announceTrip(.arrived, trip: trip, key: "arrived")
        }
    }

    private func announceTrip(_ event: AlertCenter.TripEvent, trip: FamilyTrip, key: String) {
        let id = "\(trip.id)|\(key)"
        guard placeAlertsEnabled, canNotify, !announcedTripEvents.contains(id) else { return }
        announcedTripEvents.insert(id)
        alertCenter.postTripEvent(event, trip: trip)
    }

    /// Começa a viagem. Sem previsão de chegada: ver "chega ~17:13" e o relógio
    /// passar disso assusta a família por causa de um palpite de rota.
    func startTrip(to place: FamilyPlace) {
        Task {
            await alertCenter.requestPermission()
            do {
                try await store.startTrip(destinationName: place.name, emoji: place.emoji,
                                          latitude: place.latitude, longitude: place.longitude,
                                          radiusM: place.radiusM)
            } catch {
                store.errorMessage = "Não foi possível iniciar: \(error.localizedDescription)"
            }
        }
    }

    func finishMyTrip(arrived: Bool) {
        guard let trip = store.myActiveTrip else { return }
        Task { try? await store.finishTrip(id: trip.id, arrived: arrived) }
    }

    // MARK: - Rota

    /// Rota traçada até alguém, desenhada no próprio mapa.
    ///
    /// Antes o botão jogava a pessoa no Apple Maps, e sair do app é sair do
    /// app: você perde a família de vista para ganhar uma linha. Aqui a linha
    /// aparece por cima do mesmo mapa, com os pins de todo mundo ainda ali. O
    /// Mapas continua a um toque de distância, para quem quer navegação
    /// guiada de verdade — que é coisa que este app não faz nem deveria.
    var route: MKRoute?
    var routeMemberID: String?
    var routeLoading = false

    var routeMember: FamilyMember? { store.member(id: routeMemberID) }

    func drawRoute(to member: FamilyMember) {
        guard let me = store.selfMember, me.latitude != 0 || me.longitude != 0 else {
            store.errorMessage = "Ainda não sabemos onde você está para traçar a rota."
            return
        }
        routeMemberID = member.id
        routeLoading = true
        showFamilySheet = false
        select(member)

        Task {
            defer { routeLoading = false }
            let request = MKDirections.Request()
            request.source = MKMapItem(location: CLLocation(latitude: me.latitude,
                                                            longitude: me.longitude), address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: member.latitude,
                                                                 longitude: member.longitude), address: nil)
            request.transportType = .automobile
            guard let resposta = try? await MKDirections(request: request).calculate(),
                  let primeira = resposta.routes.first else {
                routeMemberID = nil
                store.errorMessage = "Não foi possível traçar uma rota até \(member.name)."
                return
            }
            route = primeira
        }
    }

    func clearRoute() {
        route = nil
        routeMemberID = nil
    }

    /// Abre a rota no Apple Maps, para navegação guiada.
    func openRouteInMaps() {
        guard let member = routeMember else { return }
        let item = MKMapItem(location: CLLocation(latitude: member.latitude,
                                                  longitude: member.longitude), address: nil)
        item.name = member.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Alarme de pânico

    func triggerSOS() {
        Task {
            // A permissão é pedida aqui, no momento em que faz sentido — e não
            // com um pop-up seco na primeira abertura do app.
            await alertCenter.requestPermission()
            do { try await store.sendAlert(kind: .sos, targetID: nil) }
            catch { store.errorMessage = "Não foi possível enviar o alarme: \(error.localizedDescription)" }
        }
    }

    /// "Cheguei bem" — o contrário do SOS, e o aviso que a família de fato
    /// pede no dia a dia. Se havia uma viagem em andamento, chegar bem também
    /// é o fim dela: um botão só, fazendo a coisa certa.
    func sendCheckIn() {
        Task {
            await alertCenter.requestPermission()
            if let trip = store.myActiveTrip {
                try? await store.finishTrip(id: trip.id, arrived: true)
            }
            do { try await store.sendAlert(kind: .checkin, targetID: nil) }
            catch { store.errorMessage = "Não foi possível avisar: \(error.localizedDescription)" }
        }
    }

    /// "Cadê você?" — pede a posição atualizada de alguém.
    func ping(_ member: FamilyMember) {
        Task {
            await alertCenter.requestPermission()
            do { try await store.sendAlert(kind: .ping, targetID: member.id) }
            catch { store.errorMessage = "Não foi possível enviar: \(error.localizedDescription)" }
        }
    }

    /// Chamado quando a lista de alertas muda: notifica os novos e abre o
    /// alerta em tela cheia.
    func handleAlertsChanged() {
        for alert in store.alerts where alert.isActive && !announcedAlertIDs.contains(alert.id) {
            announcedAlertIDs.insert(alert.id)
            let isMine = alert.senderID == store.selfMember?.id

            // "Cadê você?" endereçado a mim: publica a posição na hora e
            // responde com uma notificação, sem tela cheia.
            if alert.kind == .ping {
                if !isMine, alert.targetID == store.selfMember?.id {
                    // A posição é atualizada mesmo com os avisos silenciados —
                    // a soneca cala o alerta, não o app.
                    locationEngine.requestImmediateUpdate()
                    if let sender = store.member(id: alert.senderID), canNotify {
                        alertCenter.postPingReceived(from: sender)
                    }
                    Task { await store.resolveAlert(id: alert.id) }
                }
                continue
            }

            // Check-in: avisa a família e some da lista. Quem envia é quem
            // encerra, para os aparelhos não disputarem o mesmo update.
            if alert.kind == .checkin {
                if isMine {
                    Task { await store.resolveAlert(id: alert.id) }
                } else if canNotify {
                    alertCenter.post(alert)
                }
                continue
            }

            if !isMine { alertCenter.post(alert) }
            if alert.kind == .sos {
                // Vai para a tela de bloqueio mesmo sem ninguém marcado: um
                // pânico não depende de configuração para ser visto.
                liveActivity.showEmergency(alert: alert, familyName: store.family?.name ?? "Família")
            }
            if presentedAlert == nil && !Self.suppressAlertOverlay { presentedAlert = alert }
        }
        // Alerta resolvido por outra pessoa some da tela e da central.
        if let presented = presentedAlert,
           store.alerts.first(where: { $0.id == presented.id })?.isActive == false {
            alertCenter.clear(alertID: presented.id)
            presentedAlert = nil
        }
        // Sem SOS em aberto, a tela de bloqueio volta ao status normal.
        if !store.alerts.contains(where: { $0.isActive && $0.kind == .sos }) {
            refreshLiveActivity()
        }
    }

    func resolveActiveAlert() {
        guard let alert = presentedAlert else { return }
        alertCenter.clear(alertID: alert.id)
        presentedAlert = nil
        Task { await store.resolveAlert(id: alert.id) }
    }

    func dismissActiveAlert() {
        if let alert = presentedAlert { alertCenter.clear(alertID: alert.id) }
        presentedAlert = nil
    }

    /// Fecha o alerta e centraliza o mapa em quem disparou.
    func showAlertOnMap(_ alert: FamilyAlert) {
        presentedAlert = nil
        showGlobe = false
        showFamilySheet = true
        if let member = store.member(id: alert.senderID) { select(member) }
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { await store.start() }

        #if DEBUG
        // Gatilhos de teste (`SIMCTL_CHILD_FAMILIA_...=1`). Ficam aqui, e não
        // no `init`, porque só valem depois que a view existe.
        let env = ProcessInfo.processInfo.environment
        if env["FAMILIA_OPEN_GLOBE"] == "1" { openGlobe() }
        if env["FAMILIA_OPEN_SETTINGS"] == "1" { showSettings = true }
        if env["FAMILIA_TEST_SOS"] == "1" {
            presentedAlert = FamilyAlert(
                id: "preview", kind: .sos, senderID: "preview",
                senderName: "Ana", senderEmoji: "👧",
                latitude: 38.7223, longitude: -9.1393,
                placeHint: "Lisboa, Portugal", createdAt: .now
            )
        }
        #endif

        alertCenter.configure()
        alertCenter.onOpenAlert = { [weak self] id in
            guard let self, let alert = self.store.alerts.first(where: { $0.id == id }) else { return }
            self.presentedAlert = alert
        }

        locationEngine.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            Task { await self.store.publishOwnLocation(snapshot) }
            self.refreshLiveActivity()
        }
        if !store.isDemo {
            locationEngine.startIfAuthorized()
        }

        // Mantém a Live Activity fresca enquanto o app roda.
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshLiveActivity()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func select(_ member: FamilyMember?) {
        selectedMemberID = member?.id
        if let member {
            Task { await store.loadTrail(for: member.id) }
        }
        refreshLiveActivity()
    }

    func refreshLiveActivity() {
        // Um alarme em aberto tem prioridade absoluta e não pode ser encerrado
        // pelo ciclo normal: sem esta checagem o refresh periódico matava a
        // Live Activity de emergência segundos depois de criá-la, porque
        // ninguém estava marcado para acompanhamento.
        if let sos = store.alerts.first(where: { $0.isActive && $0.kind == .sos }) {
            liveActivity.showEmergency(alert: sos, familyName: store.family?.name ?? "Família")
            return
        }
        // Sem alguém marcado, nada aparece na tela de bloqueio — é opt-in.
        guard liveActivityEnabled, store.phase == .ready, let watched = watchedMember else {
            liveActivity.end()
            return
        }
        liveActivity.startOrUpdate(member: watched, familyName: store.family?.name ?? "Família")
    }

    /// Entra no modo demo a partir do onboarding.
    func enterDemo() {
        onboardingDone = true
        Task { await store.start() }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.onboardingDone || needsSetup
                || model.isCreatingFamily || model.pendingInviteCode != nil {
                OnboardingView(model: model)
            } else {
                MapScreen(model: model)
            }
        }
        .animation(.spring(duration: 0.5), value: model.onboardingDone)
        .overlay {
            if model.showGlobe {
                GlobeScreen(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.spring(duration: 0.6, bounce: 0.1), value: model.showGlobe)
        // O alarme fica acima de tudo, inclusive do globo.
        .overlay {
            if let alert = model.presentedAlert {
                SOSOverlay(model: model, alert: alert)
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.presentedAlert)
        .onChange(of: model.store.alerts) { _, _ in model.handleAlertsChanged() }
        .onChange(of: model.store.members) { _, _ in
            model.checkPlaceTransitions()
            model.checkPauseTransitions()
            model.checkBatteryAndTrips()
            model.updateWidgetSnapshot()
        }
        .onChange(of: model.store.trips) { _, _ in model.checkBatteryAndTrips() }
        // A primeira verificação só registra o estado, e sem isto ela caía
        // justamente na primeira mudança de verdade — a chegada ou a pausa
        // logo após abrir o app passava batida. Registrar assim que a família
        // termina de carregar deixa o próximo evento ser o primeiro avisado.
        .onChange(of: model.store.phase) { _, phase in
            guard phase == .ready else { return }
            model.checkPlaceTransitions()
            model.checkPauseTransitions()
            model.updateWidgetSnapshot()
        }
        .onAppear { model.startIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.store.refresh() }
            // Puxa do servidor **e** empurra o próprio estado: em segundo plano
            // o app fica suspenso, então a bateria e o horário da última
            // posição podem estar congelados desde a última vez que ele esteve
            // aberto. Abrir o app tem que valer como atualizar.
            model.locationEngine.refreshNow()
        }
    }

    /// No modo Supabase, força o fluxo de setup enquanto não há sessão/família.
    private var needsSetup: Bool {
        guard !model.store.isDemo else { return false }
        switch model.store.phase {
        case .signedOut, .noFamily: return true
        case .loading, .ready: return false
        }
    }
}
