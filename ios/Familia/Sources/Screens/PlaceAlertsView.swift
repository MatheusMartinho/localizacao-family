import SwiftUI

/// O que avisar sobre uma pessoa. É preferência de quem recebe, guardada só no
/// aparelho — ninguém da família descobre quem você acompanha.
enum PlaceAlertMode: String, CaseIterable, Identifiable {
    case both, arrivals, departures, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: "Chegadas e saídas"
        case .arrivals: "Só quando chegar"
        case .departures: "Só quando sair"
        case .off: "Não avisar"
        }
    }

    var symbol: String {
        switch self {
        case .both: "arrow.left.arrow.right"
        case .arrivals: "figure.walk.arrival"
        case .departures: "figure.walk.departure"
        case .off: "bell.slash"
        }
    }

    var isOn: Bool { self != .off }

    func allows(arrived: Bool) -> Bool {
        switch self {
        case .both: true
        case .arrivals: arrived
        case .departures: !arrived
        case .off: false
        }
    }
}

/// Quem gera aviso. Cada pessoa abre a própria tela, onde dá para ajustar
/// lugar por lugar.
struct PlaceAlertsView: View {
    @Bindable var model: AppModel

    private var store: any FamilyStore { model.store }
    /// Você não é avisado sobre si mesmo, então nem aparece na lista.
    private var others: [FamilyMember] { store.sortedMembers.filter { !$0.isSelf } }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { model.placeAlertsEnabled },
                    set: { on in
                        model.placeAlertsEnabled = on
                        if on { Task { await model.alertCenter.requestPermission() } }
                    }
                )) {
                    Label("Receber avisos", systemImage: "bell.fill")
                }
                .tint(.accentDeep)
            } footer: {
                Text("Desligar aqui silencia os avisos de chegada e saída — e também os de bateria acabando e de viagem — sem perder suas escolhas abaixo.")
            }

            Section("Quem") {
                if others.isEmpty {
                    Text("Ninguém na família ainda.").foregroundStyle(.secondary)
                } else if store.places.isEmpty {
                    Label("Marque um lugar primeiro em Lugares da família.",
                          systemImage: "mappin.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others) { member in
                        NavigationLink {
                            MemberPlaceAlertsView(model: model, member: member)
                        } label: {
                            row(for: member)
                        }
                    }
                }
            }
            // Só a lista de pessoas: desabilitar a tela inteira travaria também
            // o botão acima, e aí não haveria como voltar a ligar os avisos.
            .disabled(!model.placeAlertsEnabled)
        }
        .navigationTitle("Chegadas e saídas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for member: FamilyMember) -> some View {
        let overrides = model.placeAlertOverrideCount(for: member.id)
        let mode = model.defaultPlaceAlertMode(for: member.id)
        let resumo = overrides == 0
            ? mode.label
            : "\(mode.label) · \(overrides) exceção\(overrides > 1 ? "ões" : "")"
        return HStack(spacing: 14) {
            AvatarView(member: member, size: 42, ring: 2.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.headline)
                Text(resumo)
                    .font(.caption)
                    .foregroundStyle(model.hasAnyPlaceAlert(for: member.id)
                                     ? Color.accentDeep : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Ajuste fino: um padrão para a pessoa e, se quiser, uma regra diferente para
/// cada lugar ("avise quando ela chegar na escola, mas não em casa").
struct MemberPlaceAlertsView: View {
    @Bindable var model: AppModel
    let member: FamilyMember

    private var store: any FamilyStore { model.store }

    var body: some View {
        List {
            Section {
                picker(selection: Binding(
                    get: { model.defaultPlaceAlertMode(for: member.id) },
                    set: { model.setDefaultPlaceAlertMode($0, for: member.id) }
                ))
            } header: {
                Text("Padrão")
            } footer: {
                Text("Vale para qualquer lugar que não tenha regra própria abaixo.")
            }

            Section("Por lugar") {
                ForEach(store.places) { place in
                    let override = model.placeAlertOverride(for: member.id, placeID: place.id)
                    HStack(spacing: 12) {
                        Text(place.emoji).font(.title3)
                        Text(place.name)
                        Spacer()
                        Menu {
                            Button {
                                model.setPlaceAlertOverride(nil, for: member.id, placeID: place.id)
                            } label: {
                                Label("Igual ao padrão", systemImage: "equal")
                            }
                            Divider()
                            ForEach(PlaceAlertMode.allCases) { option in
                                Button {
                                    model.setPlaceAlertOverride(option, for: member.id,
                                                                placeID: place.id)
                                } label: {
                                    Label(option.label, systemImage: option.symbol)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(override?.label ?? "Igual ao padrão")
                                    .font(.subheadline)
                                    .foregroundStyle(override == nil ? .secondary : Color.accentDeep)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func picker(selection: Binding<PlaceAlertMode>) -> some View {
        Picker("Avisar", selection: selection) {
            ForEach(PlaceAlertMode.allCases) { option in
                Label(option.label, systemImage: option.symbol).tag(option)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
