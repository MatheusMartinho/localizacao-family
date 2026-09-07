import SwiftUI
import MapKit

/// Bottom sheet de vidro com a lista da família. Tocar num membro seleciona
/// no mapa e abre o detalhe.
struct FamilySheet: View {
    @Bindable var model: AppModel
    @Binding var camera: MapCameraPosition
    @State private var detailMember: FamilyMember?
    /// Altura atual do sheet. Controlada para poder abrir sozinho quando
    /// aparece algo que precisa de atenção (uma viagem em andamento).
    @State private var detent: PresentationDetent = .height(74)

    private var store: any FamilyStore { model.store }

    /// Agrupar é O(n²). Como propriedade computada isto rodava **uma vez por
    /// linha** da lista; o `let` no `body` abaixo é o que de fato calcula uma
    /// vez só por atualização.
    private var companionsByMember: [String: [FamilyMember]] {
        var map: [String: [FamilyMember]] = [:]
        for group in store.proximityGroups where group.count > 1 {
            for member in group {
                map[member.id] = group.filter { $0.id != member.id }
            }
        }
        return map
    }

    var body: some View {
        let companions = companionsByMember
        return NavigationStack {
            List {
                TripSection(model: model)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                if store.isDemo {
                    demoBanner
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                ForEach(store.sortedMembers) { member in
                    Button {
                        model.select(member)
                        withAnimation(.spring(duration: 0.8)) {
                            camera = .region(MKCoordinateRegion(
                                center: member.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                            ))
                        }
                        detailMember = member
                    } label: {
                        MemberRow(member: member, me: store.selfMember,
                                  isEmergency: model.membersInEmergency.contains(member.id),
                                  placeLabel: store.locationLabel(for: member),
                                  isStale: store.isLocationStale(member),
                                  companions: companions[member.id] ?? [])
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle(store.family?.name ?? "Família")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $detailMember) { member in
                MemberDetailView(model: model, memberID: member.id)
            }
        }
        // Apresentado aqui (e não no MapScreen) porque o sheet da família fica
        // sempre visível — um segundo sheet só abre a partir do já apresentado.
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        // O vidro do sheet acompanha o que está atrás dele: sobre o mapa da
        // cidade fica claro, sobre o oceano fica quase preto — e aí o verde
        // escuro do app some. Material espesso segue o modo claro/escuro do
        // sistema, não a cor do mapa, então o contraste é sempre o mesmo.
        .presentationBackground(.thickMaterial)
        .presentationDetents([.height(74), .fraction(0.45), .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        .presentationCornerRadius(28)
        .interactiveDismissDisabled()
        .onChange(of: store.activeTrips.count) { antes, agora in
            // Uma viagem nova merece ser vista sem o usuário ter que arrastar.
            if agora > antes { detent = .fraction(0.45) }
        }
        .onAppear {
            if !store.activeTrips.isEmpty { detent = .fraction(0.45) }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentDeep)
            Text("Modo demonstração — família fake passeando por São Paulo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// Linha da lista: avatar, nome, lugar, distância, status + tempo, bateria.
struct MemberRow: View {
    let member: FamilyMember
    let me: FamilyMember?
    var isEmergency = false
    /// Nome do lugar marcado, quando a pessoa está em um.
    var placeLabel: String?
    /// Posição antiga demais para ser confiável.
    var isStale = false
    /// Quem está no mesmo lugar que esta pessoa agora.
    var companions: [FamilyMember] = []

    /// "com 👩 Mãe" / "com 👩 Mãe e 👧 Ana" / "com mais 3".
    private var companionsText: String? {
        guard !companions.isEmpty else { return nil }
        if companions.count > 2 { return "com mais \(companions.count) da família" }
        return "com " + companions.map { "\($0.emoji) \($0.isSelf ? "você" : $0.name)" }
            .joined(separator: " e ")
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(member: member, size: 50,
                       ringOverride: isEmergency ? .dangerRed
                                     : member.sharingPaused ? .stoppedGray : nil)
                .saturation(member.sharingPaused && !isEmergency ? 0 : 1)
                .opacity(member.sharingPaused && !isEmergency ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.isSelf ? "\(member.name) (você)" : member.name)
                        .font(.headline)
                    if let me, !member.isSelf {
                        Text(member.distance(to: me))
                            .font(.caption.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentDeep, in: .capsule)
                    }
                }
                // Pausado, o lugar guardado é o de antes da pausa — mostrá-lo
                // aqui pareceria a posição de agora.
                if let place = placeLabel, !member.sharingPaused {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let companionsText {
                    Label(companionsText, systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentDeep)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    PulsingDot(color: isEmergency ? .dangerRed
                               : member.sharingPaused ? .stoppedGray
                               : .movement(member.isMoving),
                               pulsing: isEmergency || (member.isMoving && !member.sharingPaused))
                    // A pausa vem antes de "visto há tanto tempo": ela explica
                    // justamente por que a posição parou de chegar.
                    Text(isEmergency ? "🚨 Pediu ajuda"
                         : member.sharingPaused ? member.pausedLine
                         : isStale ? "Visto \(FamilyMember.relative(since: member.updatedAt))"
                         : member.isInVehicle ? "No carro · \(member.speedText)"
                         : member.statusLine)
                        .font(.footnote)
                        .fontWeight(isEmergency ? .bold : .regular)
                        .foregroundStyle(isEmergency ? Color.dangerRed
                                         : (isStale || member.sharingPaused) ? Color.stoppedGray
                                         : Color.movement(member.isMoving))
                }
            }

            Spacer()

            if member.isInVehicle {
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentDeep)
            }

            VStack(spacing: 2) {
                Image(systemName: batterySymbol)
                    .foregroundStyle(Color.battery(member.batteryPct))
                Text("\(member.batteryPct)%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.battery(member.batteryPct))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .contentShape(.rect)
    }

    private var batterySymbol: String {
        switch member.batteryPct {
        case ..<15: "battery.25percent"
        case ..<45: "battery.50percent"
        case ..<80: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
