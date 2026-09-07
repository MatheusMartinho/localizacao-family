import Foundation
import Observation

/// Fonte de dados da família — implementada por `MockFamilyStore` (modo demo)
/// e `SupabaseFamilyStore` (backend real). Toda a UI fala apenas com este
/// protocolo.
@MainActor
protocol FamilyStore: AnyObject, Observable {
    /// `true` quando rodando com dados fake (Config com placeholders).
    var isDemo: Bool { get }
    var phase: StorePhase { get }
    var family: FamilyInfo? { get }
    /// Todos os membros, incluindo você (`isSelf == true`).
    var members: [FamilyMember] { get }
    /// Trilhas conhecidas por membro (id → pontos ordenados no tempo).
    var trails: [String: [TrailPoint]] { get }
    /// Alertas da família, mais recentes primeiro.
    var alerts: [FamilyAlert] { get }
    /// Lugares marcados pela família (casa, trabalho…).
    var places: [FamilyPlace] { get }
    /// Viagens recentes da família, mais novas primeiro.
    var trips: [FamilyTrip] { get }
    /// Pausa o envio da própria localização.
    var sharingPaused: Bool { get set }
    /// Última mensagem de erro amigável, se houver.
    var errorMessage: String? { get set }

    /// Inicia sessão/subscriptions. Chamar uma vez ao entrar no app.
    func start() async

    /// Recarrega família e posições (ex.: ao voltar para o primeiro plano).
    func refresh() async

    // Autenticação (no modo demo são no-ops).
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, displayName: String, emoji: String) async throws
    func signOut() async

    // Família.
    func createFamily(named name: String) async throws
    func joinFamily(code: String) async throws
    func leaveFamily() async throws
    func updateProfile(name: String, emoji: String) async throws

    /// Publica a própria posição (chamado pelo LocationEngine).
    func publishOwnLocation(_ snapshot: OwnLocationSnapshot) async

    /// Carrega/atualiza a trilha de um membro específico.
    func loadTrail(for memberID: String) async

    /// Dispara um alerta para a família (pânico ou toque).
    /// `targetID` endereça o toque a alguém específico.
    func sendAlert(kind: FamilyAlert.Kind, targetID: String?) async throws

    /// Avisa a família que está indo para um lugar.
    func startTrip(destinationName: String, emoji: String, latitude: Double,
                   longitude: Double, radiusM: Double) async throws
    /// Encerra a viagem: chegou, ou cancelou.
    func finishTrip(id: String, arrived: Bool) async throws
    /// Marca um alerta como atendido/cancelado.
    func resolveAlert(id: String) async

    /// Foto de perfil (JPEG pequeno). `nil` remove a foto.
    func updatePhoto(_ jpeg: Data?) async throws

    /// Cria um lugar para a família toda.
    func addPlace(name: String, emoji: String, latitude: Double, longitude: Double,
                  radiusM: Double) async throws
    func deletePlace(id: String) async throws
}

/// Quem está perto de quem. Duas pessoas dentro deste raio estão, para efeito
/// de mapa, no mesmo lugar — e dois pins empilhados viram um só.
enum FamilyProximity {
    static let radiusM: Double = 120
}

extension FamilyStore {
    /// O próprio usuário, se conhecido.
    var selfMember: FamilyMember? { members.first(where: \.isSelf) }

    /// Alerta em aberto mais recente, se houver.
    var activeAlert: FamilyAlert? { alerts.first { $0.isActive } }

    /// Viagens em andamento.
    var activeTrips: [FamilyTrip] { trips.filter(\.isActive) }

    /// Sua viagem em andamento, se houver.
    var myActiveTrip: FamilyTrip? {
        guard let me = selfMember else { return nil }
        return activeTrips.first { $0.travelerID == me.id }
    }

    /// Há quanto tempo a posição desta pessoa não é atualizada. Acima de
    /// ~20 min o ponto no mapa não é confiável.
    func isLocationStale(_ member: FamilyMember, after: TimeInterval = 20 * 60) -> Bool {
        member.updatedAt != .distantPast && Date.now.timeIntervalSince(member.updatedAt) > after
    }

    /// Reconstrói o dia da pessoa a partir da trilha gravada, agrupando
    /// pontos consecutivos no mesmo lugar. Precisa que `loadTrail` já tenha
    /// sido chamado para esse membro.
    func daySegments(for member: FamilyMember) -> [DaySegment] {
        let points = (trails[member.id] ?? [])
            .filter { Calendar.current.isDateInToday($0.recordedAt) }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard !points.isEmpty else { return [] }

        var segments: [DaySegment] = []
        var currentPlace = places.first { $0.contains(latitude: points[0].latitude,
                                                      longitude: points[0].longitude) }
        var start = points[0].recordedAt
        var last = points[0].recordedAt

        for point in points.dropFirst() {
            let place = places.first { $0.contains(latitude: point.latitude,
                                                   longitude: point.longitude) }
            if place?.id != currentPlace?.id {
                segments.append(DaySegment(id: "\(start.timeIntervalSince1970)",
                                           place: currentPlace, start: start, end: last))
                currentPlace = place
                start = point.recordedAt
            }
            last = point.recordedAt
        }
        segments.append(DaySegment(id: "\(start.timeIntervalSince1970)",
                                   place: currentPlace, start: start, end: last))
        // Trechos de menos de 2 min costumam ser oscilação do GPS na borda.
        return segments.filter { $0.end.timeIntervalSince($0.start) >= 120 }
    }

    /// Em qual lugar marcado a pessoa está, se estiver em algum.
    func place(for member: FamilyMember) -> FamilyPlace? {
        places.first { $0.contains(latitude: member.latitude, longitude: member.longitude) }
    }

    /// O que mostrar como localização: o nome do lugar marcado ganha do
    /// endereço aproximado — "🏠 Casa" diz mais que "Rua Augusta".
    func locationLabel(for member: FamilyMember) -> String? {
        place(for: member)?.label ?? member.placeHint
    }

    /// Membros agrupados por proximidade. Grupos de um só continuam na lista:
    /// quem desenha decide o que fazer com cada tamanho.
    ///
    /// Encadeamento simples (A perto de B, B perto de C ⇒ os três juntos): numa
    /// família são poucas pessoas, e o resultado é o que o olho espera ver.
    var proximityGroups: [[FamilyMember]] {
        // Pausados e posições velhas ficam de fora: dizer "está com a Ana" a
        // partir de um ponto de uma hora atrás seria inventar.
        let located = members.filter {
            ($0.latitude != 0 || $0.longitude != 0) && !$0.sharingPaused && !isLocationStale($0)
        }
        var remaining = located
        var groups: [[FamilyMember]] = []

        while let seed = remaining.first {
            remaining.removeFirst()
            var group = [seed]
            var changed = true
            while changed {
                changed = false
                for (index, candidate) in remaining.enumerated().reversed()
                where group.contains(where: { $0.meters(to: candidate) <= FamilyProximity.radiusM }) {
                    group.append(candidate)
                    remaining.remove(at: index)
                    changed = true
                }
            }
            // Você primeiro; depois por nome, para o grupo não dançar a cada
            // atualização de posição.
            groups.append(group.sorted { a, b in
                if a.isSelf != b.isSelf { return a.isSelf }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            })
        }
        // Grupos maiores primeiro: o que interessa ver é onde a família juntou.
        return groups.sorted { $0.count > $1.count }
    }

    /// Com quem esta pessoa está, sem contar ela mesma.
    func companions(of member: FamilyMember) -> [FamilyMember] {
        guard let group = proximityGroups.first(where: { g in g.contains { $0.id == member.id } })
        else { return [] }
        return group.filter { $0.id != member.id }
    }

    /// Membros ordenados: você primeiro, depois por nome.
    var sortedMembers: [FamilyMember] {
        members.sorted { a, b in
            if a.isSelf != b.isSelf { return a.isSelf }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func member(id: String?) -> FamilyMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }
}
