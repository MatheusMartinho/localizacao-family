import SwiftUI
import MapKit

/// Detalhe do membro: cartão grande com status, bateria, lugar aproximado e
/// ações (traçar rota no Apple Maps, notificar).
struct MemberDetailView: View {
    @Bindable var model: AppModel
    let memberID: String
    @State private var showNotified = false

    private var store: any FamilyStore { model.store }
    private var member: FamilyMember? { store.member(id: memberID) }

    var body: some View {
        Group {
            if let member {
                content(for: member)
            } else {
                ContentUnavailableView("Membro não encontrado",
                                       systemImage: "person.slash")
            }
        }
        .navigationTitle(member?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for member: FamilyMember) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // Cabeçalho: avatar grande com anel e pulso.
                ZStack {
                    if member.isMoving && !member.sharingPaused {
                        PulseRing(color: .accentAdaptive).scaleEffect(1.8)
                    }
                    AvatarView(member: member, size: 92, ring: 4,
                               ringOverride: member.sharingPaused ? .stoppedGray : nil)
                        .saturation(member.sharingPaused ? 0 : 1)
                        .opacity(member.sharingPaused ? 0.6 : 1)
                }
                .frame(height: 110)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(member.isSelf ? "\(member.name) (você)" : member.name)
                        .font(.title2.bold())
                    HStack(spacing: 7) {
                        PulsingDot(color: member.sharingPaused
                                   ? .stoppedGray : .movement(member.isMoving),
                                   pulsing: member.isMoving && !member.sharingPaused)
                        Text(member.statusLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(member.sharingPaused
                                             ? Color.stoppedGray
                                             : Color.movement(member.isMoving))
                    }
                }

                let juntos = store.companions(of: member)
                if !juntos.isEmpty { togetherCard(juntos, member: member) }

                if member.sharingPaused { pausedCard(for: member) }

                // Grade de fatos.
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        factCard(title: "Bateria",
                                 value: "\(member.batteryPct)%",
                                 symbol: "battery.100percent",
                                 tint: Color.battery(member.batteryPct))
                        // No carro a velocidade é o dado do momento; parado, a
                        // distância até você diz mais.
                        if member.isInVehicle {
                            factCard(title: "No carro",
                                     value: member.speedText,
                                     symbol: "car.fill",
                                     tint: .accentAdaptive)
                        } else if let me = store.selfMember, !member.isSelf {
                            factCard(title: "Distância",
                                     value: member.distance(to: me),
                                     symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                     tint: .accentAdaptive)
                        } else {
                            factCard(title: "Velocidade",
                                     value: member.speedText,
                                     symbol: "gauge.with.needle",
                                     tint: .accentAdaptive)
                        }
                    }
                }

                // Lugar + atualização.
                VStack(alignment: .leading, spacing: 10) {
                    if let place = store.locationLabel(for: member) {
                        Label(place, systemImage: store.place(for: member) != nil
                              ? "house.fill" : "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                    }
                    Label {
                        Text("Coordenadas \(String(format: "%.4f", member.latitude)), \(String(format: "%.4f", member.longitude))")
                    } icon: {
                        Image(systemName: "location.viewfinder")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    let velha = store.isLocationStale(member)
                    Label {
                        Text(velha
                             ? "Posição de \(FamilyMember.relative(since: member.updatedAt)) — pode não ser onde está agora"
                             : "Atualizado \(FamilyMember.relative(since: member.updatedAt))")
                    } icon: {
                        Image(systemName: velha ? "clock.badge.exclamationmark" : "clock.arrow.circlepath")
                    }
                    .font(.footnote)
                    .foregroundStyle(velha ? Color.dangerRed : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

                NavigationLink {
                    DayTimelineView(model: model, member: member)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.accentAdaptive)
                            .frame(width: 44, height: 44)
                            .background(Color.accentOlive.opacity(0.2), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Onde esteve hoje")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Linha do tempo pelos lugares da família")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)

                lockScreenCard(for: member)

                // Ações.
                if !member.isSelf {
                    VStack(spacing: 12) {
                        Button {
                            model.drawRoute(to: member)
                        } label: {
                            Label("Traçar rota", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.accentLime)
                        .foregroundStyle(Color.ink)

                        Button {
                            model.ping(member)
                            showNotified = true
                        } label: {
                            Label("Cadê você?", systemImage: "hand.wave.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)

                        if let me = store.selfMember,
                           GlobeMath.distanceMeters(me, member) > AppModel.farAwayThreshold {
                            Button {
                                model.select(member)
                                model.openGlobe()
                            } label: {
                                Label("Ver no globo 3D", systemImage: "globe.americas.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .alert("Pedido enviado", isPresented: $showNotified) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(member.name) recebe um aviso e o celular dela atualiza a posição na hora.")
        }
    }

    /// Quem está no mesmo lugar. É a informação que a família procura sem
    /// pedir — "ela está sozinha?" — e ninguém precisa cruzar dois pontinhos
    /// no mapa para chegar nela.
    private func togetherCard(_ companions: [FamilyMember], member: FamilyMember) -> some View {
        let nomes = companions.map { $0.isSelf ? "você" : $0.name }
        let lista = nomes.count == 1
            ? nomes[0]
            : nomes.dropLast().joined(separator: ", ") + " e " + nomes[nomes.count - 1]
        return HStack(spacing: 14) {
            // Lado a lado, não empilhados: aqui não é um pin de mapa, onde a
            // sobreposição economiza espaço e se lê como grupo. Num cartão de
            // texto ela só faz um avatar comer o anel do outro.
            HStack(spacing: 6) {
                ForEach(companions.prefix(3)) { companion in
                    AvatarView(member: companion, size: 32, ring: 2.5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.isSelf ? "Você está com \(lista)" : "\(member.name) está com \(lista)")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text("A menos de \(Int(FamilyProximity.radiusM)) m de distância.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular.tint(.accentAdaptive.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    /// Pausa: aqui a última posição conhecida é dita como tal, com o horário —
    /// é a informação útil sem fingir que é a de agora.
    private func pausedCard(for member: FamilyMember) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.stoppedGray)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.isSelf
                     ? "Você pausou o compartilhamento"
                     : "\(member.name) pausou o compartilhamento")
                    .font(.subheadline.weight(.semibold))
                Text(member.isSelf
                     ? "Sua família sabe que você pausou e não vê onde você está."
                     : "A localização volta quando \(member.name) retomar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let place = store.locationLabel(for: member) {
                    Text("Última vez em \(place), \(FamilyMember.relative(since: member.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// Opt-in explícito: só quem é marcado aqui aparece na tela de bloqueio e
    /// na Dynamic Island. Sem ninguém marcado, não existe Live Activity.
    private func lockScreenCard(for member: FamilyMember) -> some View {
        let pinned = model.isPinned(member)
        return Button {
            withAnimation(.spring(duration: 0.4)) { model.togglePin(member) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(pinned ? Color.accentDeep : Color.stoppedGray.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: pinned ? "lock.iphone" : "lock.slash")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(pinned ? Color.paper : Color.stoppedGray)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Acompanhar na tela de bloqueio")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(pinned
                         ? "\(member.name) aparece na tela de bloqueio e na Dynamic Island."
                         : "Ninguém aparece por padrão. Marque para acompanhar \(member.name).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: pinned ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(pinned ? Color.accentAdaptive : Color.stoppedGray.opacity(0.5))
                    .symbolEffect(.bounce, value: pinned)
            }
            .padding(16)
            .glassEffect(pinned ? .regular.tint(.accentAdaptive.opacity(0.16)) : .regular,
                         in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func factCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

}
