import Foundation
import UserNotifications
import UIKit

/// Notificações locais dos alertas da família.
///
/// Não usa push (APNs): o app já roda em segundo plano por causa do
/// `UIBackgroundModes: location`, então a assinatura realtime continua viva e
/// o alerta chega mesmo com o app fora da tela. Se o app for encerrado à força
/// pelo usuário, aí só push resolveria — veja o README.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    /// Chamado quando o usuário toca na notificação.
    var onOpenAlert: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    /// Pede permissão. Chamado no onboarding e ao ligar o alarme nos ajustes.
    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    var isAuthorized: Bool {
        get async { await center.notificationSettings().authorizationStatus == .authorized }
    }

    /// Publica a notificação de um alerta recebido.
    func post(_ alert: FamilyAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = alert.kind == .sos ? .defaultCritical : .default
        // Time Sensitive atravessa o Modo Foco quando o app tem o
        // entitlement correspondente; sem ele o sistema trata como normal.
        content.interruptionLevel = alert.kind == .sos ? .timeSensitive : .active
        content.userInfo = ["alertID": alert.id]
        content.threadIdentifier = alert.kind.rawValue

        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        center.add(request)

        if alert.kind == .sos {
            // Vibra além do som: alerta de emergência tem que ser sentido.
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    /// Avisa que alguém chegou ou saiu de um lugar marcado.
    func postPlaceEvent(member: FamilyMember, place: FamilyPlace, arrived: Bool) {
        let content = UNMutableNotificationContent()
        content.title = arrived
            ? "\(member.emoji) \(member.name) chegou"
            : "\(member.emoji) \(member.name) saiu"
        content.body = arrived
            ? "Chegou em \(place.label)."
            : "Saiu de \(place.label)."
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "place-\(place.id)"

        // Identificador por membro+lugar+sentido: se a pessoa ficar oscilando
        // na borda do raio, a notificação é substituída em vez de empilhada.
        let id = "place-\(member.id)-\(place.id)-\(arrived ? "in" : "out")"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Bateria acabando: a razão mais comum de alguém "sumir" do mapa.
    func postLowBattery(member: FamilyMember) {
        let content = UNMutableNotificationContent()
        content.title = "🔋 Bateria de \(member.name) acabando"
        content.body = "Restam \(member.batteryPct)%. Em breve o celular pode desligar e a localização parar."
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "battery"
        center.add(UNNotificationRequest(identifier: "battery-\(member.id)",
                                         content: content, trigger: nil))
    }

    /// Eventos de uma viagem acompanhada. Não existe aviso de atraso: a
    /// previsão de chegada foi removida do app inteiro justamente porque
    /// "fulano não chegou no horário" gera susto a partir de um palpite.
    enum TripEvent {
        case arrived
        case stalled(minutes: Int)
    }

    /// Nenhum destes é emergência. Alarmar a família por trânsito ensina a
    /// ignorar o aviso — e aí ele não serve quando importa.
    func postTripEvent(_ event: TripEvent, trip: FamilyTrip) {
        let content = UNMutableNotificationContent()
        switch event {
        case .arrived:
            content.title = "\(trip.travelerEmoji) \(trip.travelerName) chegou"
            content.body = "Chegou em \(trip.destinationLabel)."
            content.interruptionLevel = .active
        case .stalled(let minutes):
            content.title = "\(trip.travelerEmoji) \(trip.travelerName) parou há \(minutes) min"
            content.body = "A caminho de \(trip.destinationLabel). Pode ser trânsito ou uma parada."
            content.interruptionLevel = .active
        }
        content.sound = .default
        content.threadIdentifier = "trip-\(trip.id)"

        let suffix: String
        switch event {
        case .arrived: suffix = "arrived"
        case .stalled: suffix = "stalled"
        }
        center.add(UNNotificationRequest(identifier: "trip-\(trip.id)-\(suffix)",
                                         content: content, trigger: nil))
    }

    /// Alguém pausou (ou retomou) o compartilhamento. O texto é deliberadamente
    /// seco: pausar é um direito de quem compartilha, não uma infração.
    func postSharingPause(member: FamilyMember, paused: Bool) {
        let content = UNMutableNotificationContent()
        content.title = paused
            ? "\(member.emoji) \(member.name) pausou o compartilhamento"
            : "\(member.emoji) \(member.name) voltou a compartilhar"
        content.body = paused
            ? "A localização fica indisponível até \(member.name) retomar."
            : "A localização está aparecendo de novo no mapa."
        content.sound = .default
        // `.active`, e não `.passive`: passivo entrega calado na central, e um
        // aviso que ninguém vê não avisa nada. Urgente também não é — quem
        // pausa não está em perigo.
        content.interruptionLevel = .active
        content.threadIdentifier = "pause-\(member.id)"
        // Um identificador por sentido, removendo o oposto: quem pausa e retoma
        // várias vezes não empilha avisos, e cada mudança de fato aparece —
        // reusar o mesmo id nos dois sentidos substituía o aviso em silêncio.
        let id = "pause-\(member.id)-\(paused ? "on" : "off")"
        center.removeDeliveredNotifications(
            withIdentifiers: ["pause-\(member.id)-\(paused ? "off" : "on")"])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Alguém quer saber onde você está.
    func postPingReceived(from member: FamilyMember) {
        let content = UNMutableNotificationContent()
        content.title = "\(member.emoji) \(member.name) quer saber onde você está"
        content.body = "Sua posição foi atualizada agora."
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "ping"
        center.add(UNNotificationRequest(identifier: "ping-\(member.id)-\(Int(Date.now.timeIntervalSince1970))",
                                         content: content, trigger: nil))
    }

    /// Remove a notificação de um alerta já resolvido.
    func clear(alertID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [alertID])
        center.removePendingNotificationRequests(withIdentifiers: [alertID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Mostra a notificação mesmo com o app aberto — o overlay de SOS aparece
    /// junto, mas o banner reforça quando o usuário está em outra tela do app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["alertID"] as? String
        guard let id else { return }
        await MainActor.run { self.onOpenAlert?(id) }
    }
}
