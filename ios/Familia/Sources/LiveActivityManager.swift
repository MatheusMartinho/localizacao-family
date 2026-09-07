import Foundation
import ActivityKit

/// Inicia e atualiza a Live Activity (tela de bloqueio + Dynamic Island) com
/// o status do membro observado. Funciona também no modo demo.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<FamilyActivityAttributes>?

    /// Alarme de pânico na tela de bloqueio. Tem prioridade sobre o status
    /// normal e é iniciado mesmo que ninguém esteja marcado para acompanhar.
    func showEmergency(alert: FamilyAlert, familyName: String) {
        push(FamilyActivityAttributes.ContentState(
            memberName: alert.senderName,
            memberEmoji: alert.senderEmoji,
            isMoving: false,
            stateSince: alert.createdAt,
            batteryPct: 0,
            placeHint: alert.placeHint,
            isEmergency: true
        ), familyName: familyName)
    }

    func startOrUpdate(member: FamilyMember, familyName: String) {
        push(FamilyActivityAttributes.ContentState(
            memberName: member.name,
            memberEmoji: member.emoji,
            isMoving: member.isMoving,
            stateSince: member.stateSince,
            batteryPct: member.batteryPct,
            placeHint: member.placeHint
        ), familyName: familyName)
    }

    private func push(_ state: FamilyActivityAttributes.ContentState, familyName: String) {
        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(15 * 60))

        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Reaproveita uma activity que sobreviveu a um relaunch do app.
        if let existing = Activity<FamilyActivityAttributes>.activities.first {
            activity = existing
            Task { await existing.update(content) }
            return
        }
        activity = try? Activity.request(
            attributes: FamilyActivityAttributes(familyName: familyName),
            content: content
        )
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
