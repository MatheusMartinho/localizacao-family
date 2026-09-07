import SwiftUI
import MapKit

/// Tela principal: mapa full-bleed com os pins da família e UI de vidro
/// flutuando por cima.
struct MapScreen: View {
    @Bindable var model: AppModel
    @State private var camera: MapCameraPosition = .automatic
    @State private var didInitialFrame = false

    private var store: any FamilyStore { model.store }

    /// Membros que já publicaram uma posição. Quem ainda não publicou fica em
    /// (0, 0) e jogaria a câmera no meio do Atlântico.
    private var locatedMembers: [FamilyMember] {
        store.sortedMembers.filter { $0.latitude != 0 || $0.longitude != 0 }
    }

    private var emergencyIDs: Set<String> { model.membersInEmergency }

    /// Grupo aberto pelo toque: os pins dele voltam a ser individuais.
    @State private var expandedGroupID: String?

    /// O `Map` reaproveita as anotações pela identidade do `ForEach`, então uma
    /// mudança de estado externa (o alarme) não redesenhava o pin. Colocar o
    /// estado relevante na identidade força a reconstrução.
    private struct PinItem: Identifiable {
        /// Uma pessoa, ou o grupo de quem está no mesmo lugar.
        let members: [FamilyMember]
        let isEmergency: Bool
        let coordinate: CLLocationCoordinate2D
        let id: String

        var isGroup: Bool { members.count > 1 }
    }

    private static func groupID(_ group: [FamilyMember]) -> String {
        group.map(\.id).sorted().joined(separator: "+")
    }

    private static func center(of group: [FamilyMember]) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
            longitude: group.map(\.longitude).reduce(0, +) / Double(group.count)
        )
    }

    private func soloPin(_ member: FamilyMember, _ emergency: Set<String>) -> PinItem {
        let isEmergency = emergency.contains(member.id)
        return PinItem(
            members: [member], isEmergency: isEmergency, coordinate: member.coordinate,
            id: "\(member.id)|\(isEmergency)|\(member.sharingPaused)|\(member.isInVehicle)"
        )
    }

    /// Com a família toda no mesmo lugar, sete pins viram uma pilha ilegível.
    /// Quem está junto vira um pin só, que abre ao toque.
    private var pinItems: [PinItem] {
        let emergency = emergencyIDs
        let groups = store.proximityGroups
        let grouped = Set(groups.flatMap { $0 }.map(\.id))
        var items: [PinItem] = []

        for group in groups {
            let id = Self.groupID(group)
            // Um alarme de pânico nunca fica escondido dentro de um grupo.
            let hasEmergency = group.contains { emergency.contains($0.id) }
            if group.count == 1 || hasEmergency || expandedGroupID == id {
                items += group.map { soloPin($0, emergency) }
            } else {
                items.append(PinItem(members: group, isEmergency: false,
                                     coordinate: Self.center(of: group),
                                     id: "grupo|\(id)"))
            }
        }
        // Pausados e posições velhas não entram em grupo, mas continuam no mapa.
        items += locatedMembers
            .filter { !grouped.contains($0.id) }
            .map { soloPin($0, emergency) }
        return items
    }

    var body: some View {
        Map(position: $camera) {
            // Lugares marcados: círculo suave com o nome no centro.
            ForEach(store.places) { place in
                MapCircle(center: place.coordinate, radius: place.radiusM)
                    .foregroundStyle(Color.accentDeep.opacity(0.10))
                    .stroke(Color.accentDeep.opacity(0.45), lineWidth: 1.5)
                Annotation(place.name, coordinate: place.coordinate) {
                    Text(place.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: .capsule)
                        // Abaixo do centro para não cobrir o pin de quem está
                        // justamente dentro do lugar.
                        .offset(y: 38)
                        .allowsHitTesting(false)
                }
                .annotationTitles(.hidden)
            }

            // Trilha do membro selecionado.
            if let selected = model.selectedMember,
               let trail = store.trails[selected.id], trail.count > 1 {
                MapPolyline(coordinates: trail.map(\.coordinate))
                    .stroke(
                        Color.accentDeep.opacity(0.9),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(pinItems) { item in
                Annotation(item.members.first?.name ?? "", coordinate: item.coordinate) {
                    if item.isGroup {
                        GroupPinView(members: item.members)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.4)) {
                                    expandedGroupID = Self.groupID(item.members)
                                }
                                focus(on: item.coordinate, span: 0.004)
                            }
                    } else if let member = item.members.first {
                        MemberPinView(member: member,
                                      isSelected: member.id == model.selectedMemberID,
                                      isEmergency: item.isEmergency)
                            .onTapGesture {
                                model.select(member)
                                focus(on: member)
                            }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        // Uma linha só no topo: pânico à esquerda, status no meio (encolhe
        // conforme o espaço) e ajustes à direita. Sobrepostos em `overlay`
        // separados eles acabavam um por cima do outro em telas menores.
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    sosButton
                    familyStrip
                        .layoutPriority(1)
                    settingsButton
                }
                statusPill
                farAwayBanner
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .overlay(alignment: .bottom) { actionBar }
        .sheet(isPresented: $model.showFamilySheet) {
            FamilySheet(model: model, camera: $camera)
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .ready { frameFamilyIfNeeded() }
        }
        // A primeira posição costuma chegar depois do mapa aparecer.
        .onChange(of: locatedMembers.count) { _, _ in frameFamilyIfNeeded() }
        .onAppear { frameFamilyIfNeeded() }
    }

    // MARK: - Barra da família

    /// Avatares de todo mundo numa fita rolável: cresce para famílias grandes
    /// sem virar um texto truncado, e o anel já diz quem está em movimento.
    private var familyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.sortedMembers) { member in
                    Button {
                        model.select(member)
                        focus(on: member)
                    } label: {
                        AvatarView(member: member, size: 36, ring: 2.5,
                                   ringOverride: emergencyIDs.contains(member.id) ? .dangerRed : nil)
                            .overlay(alignment: .bottomTrailing) {
                                // Só chama atenção quando é útil: bateria baixa
                                // ou a pessoa num carro.
                                if member.batteryPct < 20 {
                                    Circle()
                                        .fill(Color.dangerRed)
                                        .frame(width: 11, height: 11)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                } else if member.isInVehicle {
                                    VehicleBadge(member: member, compact: true)
                                }
                            }
                            .scaleEffect(model.selectedMemberID == member.id ? 1.12 : 1)
                            .opacity(model.selectedMemberID == nil
                                     || model.selectedMemberID == member.id ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.spring(duration: 0.35), value: model.selectedMemberID)
        }
        .scrollBounceBehavior(.basedOnSize)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Pílula de status

    @ViewBuilder
    private var statusPill: some View {
        if let watched = model.pillMember {
            HStack(spacing: 7) {
                PulsingDot(color: watched.sharingPaused
                           ? .stoppedGray : .movement(watched.isMoving),
                           pulsing: watched.isMoving && !watched.sharingPaused)
                Text(watched.isSelf ? "Você" : watched.name)
                    .fontWeight(.semibold)
                Text(watched.isInVehicle
                     ? "No carro · \(watched.speedText)"
                     : watched.shortStatusLine)
                    .foregroundStyle(.secondary)
                // Pausado, o lugar é o de antes da pausa — some da pílula.
                if let place = store.locationLabel(for: watched), !watched.sharingPaused {
                    Text("· \(place)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { focus(on: watched) }
        }
    }

    private func focus(on member: FamilyMember) {
        guard member.latitude != 0 || member.longitude != 0 else { return }
        focus(on: member.coordinate)
    }

    private func focus(on coordinate: CLLocationCoordinate2D, span: Double = 0.012) {
        withAnimation(.spring(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
        }
    }

    // MARK: - Aviso de alguém longe

    /// Aparece quando alguém está a mais de 1000 km: o mapa plano vira um
    /// oceano sem graça, o globo é o jeito fácil de navegar.
    @ViewBuilder
    private var farAwayBanner: some View {
        if let far = model.farAwayMember, let me = store.selfMember {
            Button {
                model.select(far)
                model.openGlobe()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe.americas.fill")
                        .foregroundStyle(Color.accentDeep)
                    Text(FamilyMember.format(meters: GlobeMath.distanceMeters(me, far)))
                        .fontWeight(.semibold)
                    Text("· \(far.name) no globo")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Botão de ajustes

    private var settingsButton: some View {
        Button {
            model.showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Botão de pânico

    /// Segurar por 1,2 s dispara o alerta — um toque acidental no bolso não
    /// acorda a família inteira de madrugada.
    private var sosButton: some View {
        SOSButton { model.triggerSOS() }
    }

    // MARK: - Barra de ações flutuante

    private var actionBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                barButton("location.fill", label: "Centralizar em você") {
                    if let me = store.selfMember {
                        model.select(nil)
                        withAnimation(.spring(duration: 0.8)) {
                            camera = .region(MKCoordinateRegion(
                                center: me.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                            ))
                        }
                    }
                }
                barButton("person.3.fill", label: "Família toda") {
                    model.select(nil)
                    expandedGroupID = nil
                    frameFamily(animated: true)
                }
                barButton("list.bullet", label: "Lista da família") {
                    model.showFamilySheet = true
                }
                barButton("globe.americas.fill", label: "Globo 3D") {
                    model.openGlobe()
                }
                .tint(model.farAwayMember != nil ? Color.accentDeep : nil)
            }
        }
        // Logo acima do sheet da família (detent mínimo de 74pt).
        .padding(.bottom, 86)
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
    }

    // MARK: - Enquadramento

    private func frameFamilyIfNeeded() {
        guard !didInitialFrame, !locatedMembers.isEmpty else { return }
        didInitialFrame = true
        frameFamily(animated: false)
    }

    private func frameFamily(animated: Bool) {
        let coords = locatedMembers.map(\.coordinate)
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.6),
            longitudeDelta: max(0.02, (lons.max()! - lons.min()!) * 1.6)
        )
        let region = MKCoordinateRegion(center: center, span: span)
        if animated {
            withAnimation(.spring(duration: 0.9)) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }
}

// MARK: - Pin de membro

/// Avatar pin: círculo com emoji, anel de status, pulso quando em movimento e
/// badge de bateria. Com alarme de pânico em aberto, vira vermelho e ganha
/// ondas maiores — tem que puxar o olho de longe.
struct MemberPinView: View {
    let member: FamilyMember
    var isSelected = false
    var isEmergency = false

    /// Pausado, o pin marca a **última** posição conhecida: fica apagado e sem
    /// pulso, para não passar por posição de agora.
    private var isPaused: Bool { member.sharingPaused && !isEmergency }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if isEmergency {
                    // Duas ondas defasadas dão a sensação de sirene.
                    PulseRing(color: .dangerRed, diameter: 54, lineWidth: 4, maxScale: 2.1)
                    PulseRing(color: .dangerRed, diameter: 54, lineWidth: 4, maxScale: 2.1, delay: 0.7)
                    Circle()
                        .fill(Color.dangerRed.opacity(0.22))
                        .frame(width: 66, height: 66)
                } else if member.isMoving && !isPaused {
                    PulseRing(color: .accentDeep)
                }

                AvatarView(member: member, size: 46,
                           ring: isEmergency ? 4 : 3,
                           ringOverride: isEmergency ? .dangerRed
                                         : isPaused ? .stoppedGray : nil)
                    .shadow(color: (isEmergency ? Color.dangerRed : .black).opacity(isEmergency ? 0.6 : 0.25),
                            radius: isEmergency ? 10 : 6, y: 3)
                    .saturation(isPaused ? 0 : 1)
                    .opacity(isPaused ? 0.55 : 1)
            }
            .frame(width: 54, height: 54)

            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.stoppedGray, in: .circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -4)
            } else if isEmergency {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.dangerRed, in: .circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 8, y: -6)
            } else {
                BatteryBadge(pct: member.batteryPct)
                    .offset(x: 6, y: -4)
            }
        }
        // A velocidade fica embaixo, fora do canto da bateria: no carro as duas
        // informações interessam juntas.
        .overlay(alignment: .bottom) {
            if member.isInVehicle {
                VehicleBadge(member: member)
                    .offset(y: 16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.bottom, member.isInVehicle ? 16 : 0)
        .animation(.spring(duration: 0.4), value: member.isInVehicle)
        .scaleEffect(isSelected ? 1.18 : 1)
        .animation(.spring(duration: 0.35), value: isSelected)
        .animation(.default, value: member.isMoving)
        .animation(.spring(duration: 0.4), value: isEmergency)
    }
}

/// Pin de quem está no mesmo lugar: avatares sobrepostos, como um grupo de
/// pessoas de fato fica. Toque abre em pins individuais.
struct GroupPinView: View {
    let members: [FamilyMember]

    /// Três cabem sem virar uma mancha; o resto vira contagem.
    private var shown: [FamilyMember] { Array(members.prefix(3)) }
    private var extras: Int { members.count - shown.count }

    var body: some View {
        HStack(spacing: -16) {
            ForEach(shown) { member in
                AvatarView(member: member, size: 40, ring: 3)
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            }
            if extras > 0 {
                Text("+\(extras)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(width: 40, height: 40)
                    .background(Color.accentLime, in: .circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Text("\(members.count) juntos")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .fixedSize()
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentLime, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .offset(y: 15)
        }
        .padding(.bottom, 14)
        // Os avatares se sobrepõem com espaçamento negativo e sobra buraco
        // transparente entre eles; sem isto metade dos toques não pega.
        .contentShape(.rect)
    }
}

/// "🚗 68 km/h" — a pessoa está num veículo. Não é aviso nem alarme: é o mesmo
/// tipo de informação que a bateria, aparecendo do lado de quem está no carro.
struct VehicleBadge: View {
    let member: FamilyMember
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "car.fill")
                .font(.system(size: compact ? 8 : 10, weight: .bold))
            if !compact {
                Text(member.speedText)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    // Sem isto o mapa aperta a anotação e quebra "69 km/h"
                    // em duas linhas.
                    .fixedSize()
            }
        }
        .foregroundStyle(Color.paper)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 3 : 2)
        .background(Color.ink.opacity(0.85), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
    }
}

/// Anel que pulsa continuamente para fora.
struct PulseRing: View {
    let color: Color
    var diameter: CGFloat = 46
    var lineWidth: CGFloat = 3
    var maxScale: CGFloat = 1.45
    /// Defasagem, para empilhar ondas sem que saiam juntas.
    var delay: Double = 0

    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animating ? maxScale : 1)
            .opacity(animating ? 0 : 0.9)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(delay),
                       value: animating)
            .onAppear { animating = true }
    }
}

/// Badge compacto de bateria sobre o pin.
struct BatteryBadge: View {
    let pct: Int

    var body: some View {
        Text("\(pct)")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(pct < 20 ? Color.white : Color.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(pct < 20 ? Color.dangerRed : Color.accentLime, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
    }
}

/// Ponto de status que pulsa quando em movimento.
struct PulsingDot: View {
    let color: Color
    var pulsing = true
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(pulsing ? (on ? 1 : 0.35) : 1)
            .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: on)
            .onAppear { on = true }
    }
}
