import Foundation

/// Retrato da família gravado pelo app para o widget ler. O widget roda em
/// outro processo e não tem sessão do Supabase, então o app deixa este arquivo
/// pronto no App Group compartilhado.
struct FamilySnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var emoji: String
        var isMoving: Bool
        var stateSince: Date
        var batteryPct: Int
        /// Lugar marcado ou endereço aproximado.
        var place: String?
        var isEmergency: Bool
        /// Opcionais para um retrato gravado por uma versão anterior do app
        /// continuar decodificando.
        var isPaused: Bool?
        /// Preenchido só quando a pessoa está num veículo.
        var vehicleKmh: Int?

        var isInVehicle: Bool { vehicleKmh != nil && isPaused != true }

        var statusLine: String {
            if isPaused == true { return "Compartilhamento pausado" }
            if let vehicleKmh { return "No carro · \(vehicleKmh) km/h" }
            let status = isMoving ? "Em movimento" : "Parou"
            let seconds = max(0, Date.now.timeIntervalSince(stateSince))
            let minutes = Int(seconds / 60)
            if minutes < 1 { return "\(status) agora" }
            if minutes < 60 { return "\(status) há \(minutes) min" }
            return "\(status) há \(minutes / 60) h"
        }
    }

    var familyName: String
    var members: [Entry]
    var updatedAt: Date

    static let appGroup = "group.com.matheus.familia"
    private static let fileName = "family-snapshot.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> FamilySnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FamilySnapshot.self, from: data)
    }

    /// Exemplo para a pré-visualização do widget na galeria.
    static var placeholder: FamilySnapshot {
        FamilySnapshot(
            familyName: "Família",
            members: [
                Entry(id: "1", name: "Mãe", emoji: "👩", isMoving: true,
                      stateSince: .now.addingTimeInterval(-720), batteryPct: 76,
                      place: "Av. Paulista", isEmergency: false, isPaused: false,
                      vehicleKmh: 62),
                Entry(id: "2", name: "Ana", emoji: "👧", isMoving: false,
                      stateSince: .now.addingTimeInterval(-3600), batteryPct: 54,
                      place: "🏫 Escola", isEmergency: false, isPaused: false),
            ],
            updatedAt: .now
        )
    }
}
