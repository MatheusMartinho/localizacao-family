import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Atributos da Live Activity do Família: acompanha um membro (ou o próprio
/// usuário) na tela de bloqueio e na Dynamic Island.
struct FamilyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Nome de quem está sendo observado ("Maria" ou "Você").
        var memberName: String
        var memberEmoji: String
        var isMoving: Bool
        /// Quando o estado atual (movendo/parado) começou.
        var stateSince: Date
        var batteryPct: Int
        var placeHint: String?
        /// Alarme de pânico em aberto: a Live Activity vira vermelha e passa a
        /// gritar na tela de bloqueio, no lugar do status normal.
        var isEmergency: Bool = false
    }

    /// Nome da família (fixo durante a activity).
    var familyName: String
}
#endif
