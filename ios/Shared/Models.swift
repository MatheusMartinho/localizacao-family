import Foundation
import CoreLocation

/// Um membro da família com a última localização conhecida.
struct FamilyMember: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var emoji: String
    var colorHex: String
    var latitude: Double
    var longitude: Double
    var speedMps: Double
    var isMoving: Bool
    var stateSince: Date
    var batteryPct: Int
    var placeHint: String?
    var updatedAt: Date
    var isSelf: Bool
    /// Foto de perfil em JPEG, quando a pessoa escolheu uma da galeria.
    var photo: Data? = nil
    /// A pessoa pausou o próprio compartilhamento. A família vê a pausa —
    /// sumir sem explicação seria pior do que dizer que foi de propósito.
    var sharingPaused: Bool = false
    var pausedAt: Date? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Velocidade em km/h, que é como as pessoas leem.
    var speedKmh: Double { max(0, speedMps * 3.6) }

    /// A partir de 25 km/h ninguém está a pé nem correndo — é carro, ônibus ou
    /// moto. Não é um alerta, é só o que aparece do lado da pessoa no mapa.
    static let vehicleSpeedKmh = 25.0

    var isInVehicle: Bool {
        isMoving && !sharingPaused && speedKmh >= Self.vehicleSpeedKmh
    }

    /// "68 km/h" — arredondado, porque a precisão do GPS não justifica decimal.
    var speedText: String { "\(Int(speedKmh.rounded())) km/h" }

    /// Distância em metros até outra pessoa.
    func meters(to other: FamilyMember) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// "Em movimento" / "Parou".
    ///
    /// Verbo em vez de adjetivo de propósito: "Parado há 12 min" fica errado
    /// para metade da família ("Ana está parado"), e o app não sabe — nem tem
    /// por que saber — o gênero de ninguém.
    var statusLabel: String { isMoving ? "Em movimento" : "Parou" }

    /// "Em movimento há 12 min".
    var statusLine: String {
        sharingPaused ? pausedLine : "\(statusLabel) \(Self.relative(since: stateSince))"
    }

    /// Versão curta para caber na pílula do mapa: "Parou há 2 h".
    var shortStatusLine: String {
        sharingPaused ? pausedLine : "\(statusLabel) \(Self.coarse(since: stateSince))"
    }

    /// "Pausado há 20 min" — o tempo conta desde a pausa, não desde a última
    /// vez que a pessoa se mexeu.
    var pausedLine: String {
        guard let pausedAt else { return "Compartilhamento pausado" }
        return "Pausado \(Self.coarse(since: pausedAt))"
    }

    /// Como `relative`, mas sem o minuto quebrado ("há 2 h", não "há 2 h 15 min").
    static func coarse(since date: Date) -> String {
        let seconds = max(0, Date.now.timeIntervalSince(date))
        if seconds < 60 { return "agora" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "há \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "há \(hours) h" }
        return "há \(hours / 24) d"
    }

    /// "há 12 min", "há 2 h", "agora".
    static func relative(since date: Date) -> String {
        let seconds = max(0, Date.now.timeIntervalSince(date))
        if seconds < 60 { return "agora" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "há \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "há \(hours) h" : "há \(hours) h \(rest) min"
        }
        return "há \(hours / 24) d"
    }

    /// Distância até outro membro, formatada ("350 m", "2,4 km").
    func distance(to other: FamilyMember) -> String {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return Self.format(meters: a.distance(from: b))
    }

    static func format(meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        let km = meters / 1000
        return String(format: km < 10 ? "%.1f km" : "%.0f km", km)
            .replacingOccurrences(of: ".", with: ",")
    }
}

/// Lugar marcado pela família ("Casa", "Trabalho", "Casa da vó").
struct FamilyPlace: Identifiable, Equatable {
    var id: String
    var name: String
    var emoji: String
    var latitude: Double
    var longitude: Double
    /// Raio em metros: dentro dele, a pessoa "está" no lugar.
    var radiusM: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "🏠 Casa" — como o lugar aparece no lugar do endereço.
    var label: String { "\(emoji) \(name)" }

    func contains(latitude lat: Double, longitude lon: Double) -> Bool {
        guard lat != 0 || lon != 0 else { return false }
        let here = CLLocation(latitude: lat, longitude: lon)
        return here.distance(from: CLLocation(latitude: latitude, longitude: longitude)) <= radiusM
    }
}

/// Um trecho do dia: um tempo parado num lugar, ou em trânsito.
struct DaySegment: Identifiable {
    let id: String
    /// `nil` = fora de qualquer lugar marcado (em trânsito).
    let place: FamilyPlace?
    let start: Date
    let end: Date

    var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
    var label: String { place?.label ?? "Em trânsito" }
}

/// Viagem em andamento: alguém avisou para onde está indo.
struct FamilyTrip: Identifiable, Equatable {
    var id: String
    var travelerID: String
    var travelerName: String
    var travelerEmoji: String
    var destinationName: String
    var destinationEmoji: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var destinationRadiusM: Double
    var startedAt: Date
    var arrivedAt: Date?
    var cancelledAt: Date?

    var isActive: Bool { arrivedAt == nil && cancelledAt == nil }
    var destinationLabel: String { "\(destinationEmoji) \(destinationName)" }

    var destination: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }

    func hasArrived(latitude: Double, longitude: Double) -> Bool {
        guard latitude != 0 || longitude != 0 else { return false }
        return CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: destinationLatitude,
                                       longitude: destinationLongitude)) <= destinationRadiusM
    }

}

/// Alerta disparado por alguém da família.
struct FamilyAlert: Identifiable, Equatable {
    enum Kind: String { case sos, ping, checkin }

    var id: String
    var kind: Kind
    var senderID: String
    var senderName: String
    var senderEmoji: String
    var latitude: Double?
    var longitude: Double?
    var placeHint: String?
    var createdAt: Date
    var resolvedAt: Date?
    /// Para quem o toque foi endereçado (`nil` = família toda).
    var targetID: String?

    var isActive: Bool { resolvedAt == nil }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var title: String {
        switch kind {
        case .sos: "🚨 \(senderName) precisa de ajuda"
        case .ping: "\(senderEmoji) \(senderName) quer falar com você"
        case .checkin: "✅ \(senderName) avisou que está bem"
        }
    }

    var body: String {
        let onde = placeHint.map { " em \($0)" } ?? ""
        switch kind {
        case .sos: return "Alarme de emergência disparado\(onde). Toque para ver no mapa."
        case .ping: return "Mandou um toque para você\(onde)."
        case .checkin: return "Chegou bem\(onde)."
        }
    }
}

/// Família (grupo) a que o usuário pertence.
struct FamilyInfo: Equatable {
    var id: String
    var name: String
    var inviteCode: String
}

/// Ponto de trilha (histórico de rota) de um membro.
struct TrailPoint: Equatable {
    var latitude: Double
    var longitude: Double
    var recordedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Snapshot da própria localização produzido pelo LocationEngine.
struct OwnLocationSnapshot: Equatable {
    var latitude: Double
    var longitude: Double
    var accuracyM: Double?
    var speedMps: Double
    var heading: Double?
    var batteryPct: Int
    var isMoving: Bool
    var stateSince: Date
    var placeHint: String?
}

/// Erros do app com mensagem pronta para mostrar ao usuário.
enum FamiliaError: LocalizedError {
    /// Cadastro feito, mas o projeto exige confirmação de e-mail antes de entrar.
    case emailConfirmationPending

    var errorDescription: String? {
        switch self {
        case .emailConfirmationPending:
            "Conta criada! Confirme o e-mail que acabamos de enviar e depois toque em \"Já tenho conta\" para entrar."
        }
    }
}

/// Fase da sessão do store.
enum StorePhase: Equatable {
    /// Carregando sessão/dados.
    case loading
    /// Precisa autenticar (modo Supabase).
    case signedOut
    /// Autenticado mas sem família — criar ou entrar com código.
    case noFamily
    /// Tudo pronto: mapa ao vivo.
    case ready
}
