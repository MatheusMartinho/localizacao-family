import SwiftUI
import RealityKit

/// Globo 3D em tela cheia para quando alguém da família está longe demais
/// para o mapa fazer sentido. UI de vidro flutuando sobre a cena.
struct GlobeScreen: View {
    @Bindable var model: AppModel
    @State private var scene = GlobeScene()
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var flewToInitial = false

    private var store: any FamilyStore { model.store }
    private var focused: FamilyMember? { model.selectedMember ?? farthest }
    private var farthest: FamilyMember? {
        guard let me = store.selfMember else { return nil }
        return store.members.filter { !$0.isSelf }
            .max { GlobeMath.distanceMeters(me, $0) < GlobeMath.distanceMeters(me, $1) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Foto de céu (`sky.jpg` em Familia/Resources), quando houver.
            if let url = GlobeScene.skyPhotoURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.25).ignoresSafeArea())
            }

            RealityView { content in
                await scene.build(into: &content)
                scene.update(members: store.members, selectedID: focused?.id)
                flyToFocusedOnce()
            } update: { _ in
                scene.update(members: store.members, selectedID: focused?.id)
                // A família pode chegar depois do globo abrir (ex.: logo no
                // launch), então o voo inicial também é tentado aqui.
                flyToFocusedOnce()
            }
            .ignoresSafeArea()
            .gesture(drag)
            .simultaneousGesture(magnify)
            // Voa de novo quando muda quem está em foco — inclusive quando a
            // família chega depois do globo abrir.
            .onChange(of: focused?.id) { _, _ in
                guard let focused, focused.latitude != 0 || focused.longitude != 0 else { return }
                scene.flyTo(lat: focused.latitude, lon: focused.longitude)
            }

            VStack {
                topBar
                Spacer()
                memberChips
            }
        }
        .preferredColorScheme(.dark)
        .tint(.accentLime)
        .statusBarHidden()
    }

    private func flyToFocusedOnce() {
        guard !flewToInitial, let focused, focused.latitude != 0 || focused.longitude != 0 else { return }
        flewToInitial = true
        scene.flyTo(lat: focused.latitude, lon: focused.longitude)
    }

    // MARK: - UI de vidro

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.closeGlobe() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)

            Spacer()

            if let focused, let me = store.selfMember {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(focused.emoji)
                        Text(focused.name).fontWeight(.bold)
                        PulsingDot(color: focused.isMoving ? .accentLime : .stoppedGray,
                                   pulsing: focused.isMoving)
                    }
                    .font(.subheadline)
                    Text(FamilyMember.format(meters: GlobeMath.distanceMeters(me, focused)) + " de você")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(Color.accentLime)
                        .monospacedDigit()
                    if let place = focused.placeHint {
                        Text(place).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var memberChips: some View {
        VStack(spacing: 12) {
            Text("Arraste para girar · belisque para aproximar")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(store.sortedMembers) { member in
                            Button {
                                model.select(member)
                                scene.flyTo(lat: member.latitude, lon: member.longitude)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(member.emoji)
                                    Text(member.isSelf ? "Você" : member.name)
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                            .tint(member.id == focused?.id ? .accentLime : nil)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            Button {
                model.closeGlobe()
            } label: {
                Label("Ver no mapa", systemImage: "map.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentLime)
            .foregroundStyle(Color.ink)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Gestos

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = Float(value.translation.width - lastDrag.width)
                let dy = Float(value.translation.height - lastDrag.height)
                lastDrag = value.translation
                scene.dragChanged(dx: dx, dy: dy)
            }
            .onEnded { _ in
                lastDrag = .zero
                scene.dragEnded()
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let factor = Float(value.magnification / lastMagnification)
                lastMagnification = value.magnification
                scene.zoom(by: factor)
            }
            .onEnded { _ in lastMagnification = 1 }
    }
}
