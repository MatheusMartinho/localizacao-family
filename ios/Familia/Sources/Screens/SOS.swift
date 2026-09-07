import SwiftUI
import UIKit

/// Botão de pânico. Precisa ser **segurado** — um toque solto no bolso não
/// pode acordar a família inteira. O anel vai preenchendo enquanto segura.
struct SOSButton: View {
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var fired = false
    private let hold: Double = 1.2

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dangerRed.opacity(0.92))
                .frame(width: 52, height: 52)
                .shadow(color: .dangerRed.opacity(0.5), radius: progress * 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)

            Text("SOS")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
        .scaleEffect(1 + progress * 0.12)
        .accessibilityLabel("Alarme de emergência. Segure para disparar.")
        .onLongPressGesture(minimumDuration: hold) {
            guard !fired else { return }
            fired = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            action()
            withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { fired = false }
        } onPressingChanged: { pressing in
            if pressing {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation(.linear(duration: hold)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
    }
}

/// Tela cheia vermelha quando alguém dispara o alarme. Impossível de ignorar.
struct SOSOverlay: View {
    @Bindable var model: AppModel
    let alert: FamilyAlert

    @State private var pulse = false

    private var isMine: Bool { alert.senderID == model.store.selfMember?.id }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.dangerRed, Color(red: 0.45, green: 0.05, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 3)
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 132, height: 132)
                    Text(alert.senderEmoji).font(.system(size: 64))
                }
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

                VStack(spacing: 8) {
                    Text(isMine ? "Alarme enviado" : "\(alert.senderName) precisa de ajuda")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                    if let place = alert.placeHint {
                        Label(place, systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .opacity(0.9)
                    }
                    Text(isMine
                         ? "Sua família foi avisada e está vendo onde você está."
                         : "Disparado \(FamilyMember.relative(since: alert.createdAt))")
                        .font(.subheadline)
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 12) {
                    if !isMine {
                        Button {
                            model.showAlertOnMap(alert)
                        } label: {
                            Label("Ver no mapa", systemImage: "map.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(Color.dangerRed)
                    }

                    Button {
                        model.resolveActiveAlert()
                    } label: {
                        Text(isMine ? "Cancelar alarme" : "Estou indo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)

                    Button("Dispensar") { model.dismissActiveAlert() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
            }
        }
        .onAppear { pulse = true }
        .transition(.opacity)
    }
}
