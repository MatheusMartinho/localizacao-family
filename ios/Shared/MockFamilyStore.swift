import Foundation
import CoreLocation
import Observation

/// Store de demonstração: uma família fake se movendo suavemente por
/// São Paulo, sem nenhum backend. Usado quando `Config.isConfigured == false`.
@MainActor
@Observable
final class MockFamilyStore: FamilyStore {
    let isDemo = true
    private(set) var phase: StorePhase = .loading
    private(set) var family: FamilyInfo? = FamilyInfo(id: "demo", name: "Família Martinho", inviteCode: "DEMO42")
    private(set) var members: [FamilyMember] = []
    private(set) var trails: [String: [TrailPoint]] = [:]
    private(set) var alerts: [FamilyAlert] = []
    private(set) var trips: [FamilyTrip] = []
    /// Lugares de exemplo em volta das rotas da família fake.
    private(set) var places: [FamilyPlace] = [
        FamilyPlace(id: "demo-casa", name: "Casa", emoji: "🏠",
                    latitude: -23.5896, longitude: -46.6345, radiusM: 200),
        FamilyPlace(id: "demo-trabalho", name: "Trabalho", emoji: "💼",
                    latitude: -23.5461, longitude: -46.6386, radiusM: 250),
    ]
    var sharingPaused = false
    var errorMessage: String?

    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    private var sims: [MemberSim] = []
    private var tickCount = 0

    /// Simulação de um membro: anda por uma rota de waypoints, alterna
    /// fases de movimento/parada e drena bateria.
    private struct MemberSim {
        var member: FamilyMember
        /// Rota em loop pela cidade.
        var route: [CLLocationCoordinate2D]
        /// Índice do segmento atual e progresso 0...1 dentro dele.
        var segment: Int
        var progress: Double
        /// Velocidade típica em m/s quando em movimento.
        var cruiseSpeed: Double
        /// Segundos restantes na fase atual (movendo ou parado).
        var phaseRemaining: TimeInterval
        /// Duração das fases (movendo, parado).
        var movingDuration: ClosedRange<TimeInterval>
        var stoppedDuration: ClosedRange<TimeInterval>
        /// Lugares aproximados exibidos quando parado/movendo.
        var placeHints: [String]
    }

    func start() async {
        guard sims.isEmpty else { return }
        buildFamily()
        phase = .ready
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick(dt: 1.0) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    // MARK: - Família fake

    private func buildFamily() {
        let now = Date.now

        // Centro de São Paulo e arredores.
        func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Mãe: dirigindo entre Pinheiros e o Ibirapuera.
        let mae = FamilyMember(
            id: "demo-mae", name: "Mãe", emoji: "👩", colorHex: "#D4FF3F",
            latitude: -23.5675, longitude: -46.6926, speedMps: 8.5,
            isMoving: true, stateSince: now.addingTimeInterval(-12 * 60),
            batteryPct: 76, placeHint: "Av. Brig. Faria Lima", updatedAt: now, isSelf: false)
        let maeRoute = [
            c(-23.5675, -46.6926), c(-23.5714, -46.6852), c(-23.5766, -46.6800),
            c(-23.5824, -46.6742), c(-23.5874, -46.6672), c(-23.5890, -46.6580),
            c(-23.5874, -46.6672), c(-23.5824, -46.6742), c(-23.5766, -46.6800),
            c(-23.5714, -46.6852),
        ]

        // Ana (irmã): caminhando na Av. Paulista.
        let ana = FamilyMember(
            id: "demo-ana", name: "Ana", emoji: "👧", colorHex: "#D4FF3F",
            latitude: -23.5614, longitude: -46.6560, speedMps: 1.6,
            isMoving: true, stateSince: now.addingTimeInterval(-4 * 60),
            batteryPct: 17, placeHint: "Av. Paulista", updatedAt: now, isSelf: false)
        let anaRoute = [
            c(-23.5614, -46.6560), c(-23.5629, -46.6544), c(-23.5648, -46.6528),
            c(-23.5672, -46.6506), c(-23.5648, -46.6528), c(-23.5629, -46.6544),
        ]

        // Vovó: em casa, Vila Mariana.
        let vovo = FamilyMember(
            id: "demo-vovo", name: "Vovó", emoji: "👵", colorHex: "#8E93A6",
            latitude: -23.5896, longitude: -46.6345, speedMps: 0,
            isMoving: false, stateSince: now.addingTimeInterval(-58 * 60),
            batteryPct: 92, placeHint: "Casa · Vila Mariana", updatedAt: now, isSelf: false)
        let vovoRoute = [
            c(-23.5896, -46.6345), c(-23.5902, -46.6332), c(-23.5896, -46.6345),
        ]

        // Duda e Bia: na casa da vó, junto com ela — o trio existe para o mapa
        // ter um grupo de verdade para agrupar num pin só.
        let duda = FamilyMember(
            id: "demo-duda", name: "Duda", emoji: "👦", colorHex: "#D4FF3F",
            latitude: -23.5893, longitude: -46.6341, speedMps: 0,
            isMoving: false, stateSince: now.addingTimeInterval(-46 * 60),
            batteryPct: 63, placeHint: "Casa · Vila Mariana", updatedAt: now, isSelf: false)
        let dudaRoute = [
            c(-23.5893, -46.6341), c(-23.5899, -46.6337), c(-23.5893, -46.6341),
        ]

        let bia = FamilyMember(
            id: "demo-bia", name: "Bia", emoji: "👧🏽", colorHex: "#8E93A6",
            latitude: -23.5899, longitude: -46.6349, speedMps: 0,
            isMoving: false, stateSince: now.addingTimeInterval(-51 * 60),
            batteryPct: 34, placeHint: "Casa · Vila Mariana", updatedAt: now, isSelf: false)
        let biaRoute = [
            c(-23.5899, -46.6349), c(-23.5891, -46.6352), c(-23.5899, -46.6349),
        ]

        // Tio Léo: na Marginal, em velocidade de carro — o crachá "🚗 km/h".
        let leo = FamilyMember(
            id: "demo-leo", name: "Tio Léo", emoji: "🧔", colorHex: "#D4FF3F",
            latitude: -23.5320, longitude: -46.6900, speedMps: 19.5,
            isMoving: true, stateSince: now.addingTimeInterval(-23 * 60),
            batteryPct: 88, placeHint: "Marginal Pinheiros", updatedAt: now, isSelf: false)
        let leoRoute = [
            c(-23.5320, -46.6900), c(-23.5410, -46.6980), c(-23.5510, -46.7020),
            c(-23.5620, -46.7030), c(-23.5510, -46.7020), c(-23.5410, -46.6980),
        ]

        // Você: perto da República.
        let voce = FamilyMember(
            id: "demo-voce", name: "Matheus", emoji: "🧑", colorHex: "#D4FF3F",
            latitude: -23.5560, longitude: -46.6620, speedMps: 0,
            isMoving: false, stateSince: now.addingTimeInterval(-7 * 60),
            batteryPct: 64, placeHint: "Consolação", updatedAt: now, isSelf: true)
        let voceRoute = [
            c(-23.5560, -46.6620), c(-23.5574, -46.6602), c(-23.5590, -46.6584),
            c(-23.5574, -46.6602),
        ]

        sims = [
            MemberSim(member: mae, route: maeRoute, segment: 0, progress: 0,
                      cruiseSpeed: 9, phaseRemaining: 90,
                      movingDuration: 80...160, stoppedDuration: 25...60,
                      placeHints: ["Av. Brig. Faria Lima", "Pinheiros", "Av. Rebouças", "Ibirapuera"]),
            MemberSim(member: ana, route: anaRoute, segment: 0, progress: 0,
                      cruiseSpeed: 1.7, phaseRemaining: 70,
                      movingDuration: 60...120, stoppedDuration: 40...90,
                      placeHints: ["Av. Paulista", "MASP", "Parque Trianon"]),
            MemberSim(member: vovo, route: vovoRoute, segment: 0, progress: 0,
                      cruiseSpeed: 0.9, phaseRemaining: 200,
                      movingDuration: 20...45, stoppedDuration: 180...360,
                      placeHints: ["Casa · Vila Mariana"]),
            MemberSim(member: voce, route: voceRoute, segment: 0, progress: 0,
                      cruiseSpeed: 1.4, phaseRemaining: 60,
                      movingDuration: 45...100, stoppedDuration: 60...140,
                      placeHints: ["Consolação", "Rua Augusta", "Higienópolis"]),
            MemberSim(member: duda, route: dudaRoute, segment: 0, progress: 0,
                      cruiseSpeed: 0.8, phaseRemaining: 190,
                      movingDuration: 20...40, stoppedDuration: 160...320,
                      placeHints: ["Casa · Vila Mariana"]),
            MemberSim(member: bia, route: biaRoute, segment: 0, progress: 0,
                      cruiseSpeed: 0.8, phaseRemaining: 210,
                      movingDuration: 20...40, stoppedDuration: 160...320,
                      placeHints: ["Casa · Vila Mariana"]),
            MemberSim(member: leo, route: leoRoute, segment: 0, progress: 0,
                      // ~70 km/h: velocidade de carro, para o crachá aparecer.
                      cruiseSpeed: 19.5, phaseRemaining: 260,
                      movingDuration: 240...480, stoppedDuration: 30...70,
                      placeHints: ["Marginal Pinheiros", "Av. dos Bandeirantes", "Morumbi"]),
        ]
        members = sims.map(\.member)
        for sim in sims {
            trails[sim.member.id] = [TrailPoint(latitude: sim.member.latitude,
                                                longitude: sim.member.longitude,
                                                recordedAt: now)]
        }
    }

    // MARK: - Simulação

    private func tick(dt: TimeInterval) {
        tickCount += 1
        let now = Date.now

        for i in sims.indices {
            var sim = sims[i]
            var m = sim.member

            // No demo a pausa vale para "você", para a tela mostrar o mesmo
            // que mostraria com o backend real: pin congelado na última
            // posição, sem atualizar.
            if m.isSelf, m.sharingPaused != sharingPaused {
                m.sharingPaused = sharingPaused
                m.pausedAt = sharingPaused ? now : nil
                sim.member = m
                sims[i] = sim
            }
            if m.sharingPaused { continue }

            // Alterna fases movendo/parado.
            sim.phaseRemaining -= dt
            if sim.phaseRemaining <= 0 {
                m.isMoving.toggle()
                m.stateSince = now
                sim.phaseRemaining = m.isMoving
                    ? .random(in: sim.movingDuration)
                    : .random(in: sim.stoppedDuration)
                m.placeHint = sim.placeHints.randomElement()
            }

            if m.isMoving {
                // Anda pela rota com velocidade levemente variável.
                let speed = sim.cruiseSpeed * .random(in: 0.85...1.15)
                m.speedMps = speed
                var remaining = speed * dt
                while remaining > 0 {
                    let a = sim.route[sim.segment]
                    let b = sim.route[(sim.segment + 1) % sim.route.count]
                    let segLen = CLLocation(latitude: a.latitude, longitude: a.longitude)
                        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                    let left = (1 - sim.progress) * segLen
                    if remaining < left {
                        sim.progress += remaining / max(segLen, 1)
                        remaining = 0
                    } else {
                        remaining -= left
                        sim.segment = (sim.segment + 1) % sim.route.count
                        sim.progress = 0
                    }
                }
                let a = sim.route[sim.segment]
                let b = sim.route[(sim.segment + 1) % sim.route.count]
                m.latitude = a.latitude + (b.latitude - a.latitude) * sim.progress
                m.longitude = a.longitude + (b.longitude - a.longitude) * sim.progress
            } else {
                m.speedMps = 0
            }

            // Bateria varia devagar (drena mais em movimento).
            if tickCount % 45 == 0 {
                let drain = m.isMoving ? Int.random(in: 0...2) : Int.random(in: 0...1)
                m.batteryPct = max(3, m.batteryPct - drain)
                if m.batteryPct <= 3, Bool.random() { m.batteryPct = 100 } // "carregou"
            }

            m.updatedAt = now
            sim.member = m
            sims[i] = sim

            // Trilha: guarda um ponto a cada 5 s de movimento.
            if m.isMoving, tickCount % 5 == 0 {
                var trail = trails[m.id] ?? []
                trail.append(TrailPoint(latitude: m.latitude, longitude: m.longitude, recordedAt: now))
                if trail.count > 240 { trail.removeFirst(trail.count - 240) }
                trails[m.id] = trail
            }
        }
        members = sims.map(\.member)
    }

    // MARK: - FamilyStore (no-ops no demo)

    func refresh() async {}

    func sendAlert(kind: FamilyAlert.Kind, targetID: String?) async throws {
        guard let me = selfMember else { return }
        alerts.insert(FamilyAlert(id: UUID().uuidString, kind: kind,
                                  senderID: me.id, senderName: me.name, senderEmoji: me.emoji,
                                  latitude: me.latitude, longitude: me.longitude,
                                  placeHint: me.placeHint, createdAt: .now,
                                  targetID: targetID), at: 0)
    }

    func startTrip(destinationName: String, emoji: String, latitude: Double,
                   longitude: Double, radiusM: Double) async throws {
        guard let me = selfMember else { return }
        trips.insert(FamilyTrip(id: UUID().uuidString, travelerID: me.id,
                                travelerName: me.name, travelerEmoji: me.emoji,
                                destinationName: destinationName, destinationEmoji: emoji,
                                destinationLatitude: latitude, destinationLongitude: longitude,
                                destinationRadiusM: radiusM, startedAt: .now), at: 0)
    }

    func finishTrip(id: String, arrived: Bool) async throws {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        if arrived { trips[i].arrivedAt = .now } else { trips[i].cancelledAt = .now }
    }

    func resolveAlert(id: String) async {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].resolvedAt = .now
    }

    func addPlace(name: String, emoji: String, latitude: Double, longitude: Double,
                  radiusM: Double) async throws {
        places.append(FamilyPlace(id: UUID().uuidString, name: name, emoji: emoji,
                                  latitude: latitude, longitude: longitude, radiusM: radiusM))
    }

    func deletePlace(id: String) async throws {
        places.removeAll { $0.id == id }
    }

    func updatePhoto(_ jpeg: Data?) async throws {
        guard let i = sims.firstIndex(where: { $0.member.isSelf }) else { return }
        sims[i].member.photo = jpeg
        members = sims.map(\.member)
    }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, displayName: String, emoji: String) async throws {}
    func signOut() async {}
    func createFamily(named name: String) async throws {
        family = FamilyInfo(id: "demo", name: name, inviteCode: Self.randomCode())
    }
    func joinFamily(code: String) async throws {}
    func leaveFamily() async throws {}

    /// No demo não existe conta para apagar, mas a tela precisa se comportar
    /// igual: some tudo e volta para o começo.
    func deleteAccount() async throws {
        timer?.invalidate()
        sims = []
        members = []
        trails = [:]
        alerts = []
        trips = []
        phase = .signedOut
    }

    func updateProfile(name: String, emoji: String) async throws {
        guard let i = sims.firstIndex(where: { $0.member.isSelf }) else { return }
        sims[i].member.name = name
        sims[i].member.emoji = emoji
        members = sims.map(\.member)
    }

    func publishOwnLocation(_ snapshot: OwnLocationSnapshot) async {
        // No demo a própria posição também é simulada; ignora o engine.
    }

    func loadTrail(for memberID: String) async {
        // Trilhas já são mantidas em memória pelo tick.
    }

    static func randomCode() -> String {
        String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ".randomElement()! })
    }
}
