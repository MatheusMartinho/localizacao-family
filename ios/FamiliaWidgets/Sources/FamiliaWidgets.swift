import WidgetKit
import SwiftUI
import ActivityKit

@main
struct FamiliaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FamilyLiveActivity()
        FamilyWidget()
    }
}

/// Live Activity do Família: tela de bloqueio + Dynamic Island com o status
/// do membro observado ("Em movimento há 12 min", lugar aproximado, bateria).
struct FamilyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FamilyActivityAttributes.self) { context in
            // Tela de bloqueio.
            LockScreenActivityView(context: context)
                .activityBackgroundTint(context.state.isEmergency
                                        ? Color.dangerRed.opacity(0.96)
                                        : Color.ink.opacity(0.85))
                .activitySystemActionForegroundColor(context.state.isEmergency
                                                     ? Color.white : Color.accentLime)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        AvatarBubble(emoji: context.state.memberEmoji,
                                     isMoving: context.state.isMoving,
                                     size: 40)
                        Text(context.state.memberName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        StatusDot(isMoving: context.state.isMoving)
                        Text(timerInterval: context.state.stateSince...Date.now.addingTimeInterval(60 * 60 * 24),
                             countsDown: false)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .frame(width: 56)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label {
                            Text(context.state.placeHint ?? (context.state.isMoving ? "A caminho" : "Sem se mover"))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color.accentLime)
                        }
                        .font(.footnote)
                        Spacer()
                        Label("\(context.state.batteryPct)%", systemImage: "battery.75percent")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.battery(context.state.batteryPct))
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if context.state.isEmergency {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dangerRed)
                } else {
                    StatusDot(isMoving: context.state.isMoving)
                }
            } compactTrailing: {
                Text(timerInterval: context.state.stateSince...Date.now.addingTimeInterval(60 * 60 * 24),
                     countsDown: false)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .frame(width: 40)
                    .foregroundStyle(context.state.isMoving ? Color.accentLime : Color.stoppedGray)
            } minimal: {
                if context.state.isEmergency {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dangerRed)
                } else {
                    StatusDot(isMoving: context.state.isMoving)
                }
            }
            .keylineTint(context.state.isEmergency ? Color.dangerRed : Color.accentLime)
        }
    }
}

// MARK: - Tela de bloqueio

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<FamilyActivityAttributes>

    var body: some View {
        if context.state.isEmergency { emergency } else { normal }
    }

    /// Alarme de pânico: vermelho, direto, sem status de bateria ou movimento.
    private var emergency: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.white.opacity(0.2))
                Text(context.state.memberEmoji).font(.system(size: 30))
                Circle().strokeBorder(.white, lineWidth: 3)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("🚨 \(context.state.memberName) precisa de ajuda")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let place = context.state.placeHint {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("há")
                    Text(timerInterval: context.state.stateSince...Date.now.addingTimeInterval(60 * 60 * 24),
                         countsDown: false)
                        .monospacedDigit()
                        // Estreito demais o sistema corta para "3:--".
                        .frame(width: 92, alignment: .leading)
                }
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var normal: some View {
        HStack(spacing: 14) {
            AvatarBubble(emoji: context.state.memberEmoji,
                         isMoving: context.state.isMoving,
                         size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.memberName)
                    .font(.headline)
                    .foregroundStyle(Color.paper)
                HStack(spacing: 6) {
                    StatusDot(isMoving: context.state.isMoving)
                    Text(context.state.isMoving ? "Em movimento" : "Parou")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(context.state.isMoving ? Color.accentLime : Color.stoppedGray)
                    Text("·")
                        .foregroundStyle(Color.paper.opacity(0.5))
                    Text(timerInterval: context.state.stateSince...Date.now.addingTimeInterval(60 * 60 * 24),
                         countsDown: false)
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.paper)
                        .frame(maxWidth: 74, alignment: .leading)
                }
                if let place = context.state.placeHint {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Color.paper.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "battery.75percent")
                    .foregroundStyle(Color.battery(context.state.batteryPct))
                Text("\(context.state.batteryPct)%")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.battery(context.state.batteryPct))
            }
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            // Barra accent na base do cartão.
            Capsule()
                .fill(Color.accentLime)
                .frame(height: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .opacity(context.state.isMoving ? 1 : 0.35)
        }
    }
}

// MARK: - Componentes

private struct AvatarBubble: View {
    let emoji: String
    let isMoving: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.paper.opacity(0.15))
            Text(emoji)
                .font(.system(size: size * 0.55))
            Circle()
                .strokeBorder(isMoving ? Color.accentLime : Color.stoppedGray, lineWidth: 3)
        }
        .frame(width: size, height: size)
    }
}

private struct StatusDot: View {
    let isMoving: Bool

    var body: some View {
        Circle()
            .fill(isMoving ? Color.accentLime : Color.stoppedGray)
            .frame(width: 9, height: 9)
    }
}
