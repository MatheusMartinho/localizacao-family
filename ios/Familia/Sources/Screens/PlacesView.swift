import SwiftUI
import MapKit

/// Lugares da família: casa, trabalho, casa da vó. Quando alguém está dentro
/// do círculo, o app mostra "🏠 Casa" no lugar do endereço.
struct PlacesView: View {
    @Bindable var model: AppModel
    @State private var showingNew = false

    private var store: any FamilyStore { model.store }

    var body: some View {
        List {
            Section {
                if store.places.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhum lugar ainda", systemImage: "mappin.slash")
                    } description: {
                        Text("Marque a casa, o trabalho ou a casa da vó. A família toda passa a ver o nome do lugar em vez do endereço.")
                    }
                } else {
                    ForEach(store.places) { place in
                        HStack(spacing: 14) {
                            Text(place.emoji)
                                .font(.system(size: 26))
                                .frame(width: 46, height: 46)
                                .background(Color.accentOlive.opacity(0.25), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.headline)
                                Text("Raio de \(Int(place.radiusM)) m")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Quem está lá agora.
                            let quem = store.members.filter {
                                place.contains(latitude: $0.latitude, longitude: $0.longitude)
                            }
                            if !quem.isEmpty {
                                HStack(spacing: -8) {
                                    ForEach(quem.prefix(3)) { member in
                                        AvatarView(member: member, size: 28, ring: 2)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexes in
                        let ids = indexes.map { store.places[$0].id }
                        Task { for id in ids { try? await store.deletePlace(id: id) } }
                    }
                }
            } footer: {
                Text("Os lugares valem para a família inteira — quem cria, cria para todos.")
            }
        }
        .navigationTitle("Lugares")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("Novo lugar", systemImage: "plus")
                }
                .disabled(store.selfMember == nil)
            }
        }
        .sheet(isPresented: $showingNew) {
            NewPlaceView(model: model)
        }
    }
}

/// Criação de lugar a partir de onde você está agora.
private struct NewPlaceView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🏠"
    @State private var radius: Double = 150
    @State private var camera: MapCameraPosition = .automatic
    @State private var saving = false
    @State private var error: String?

    private var store: any FamilyStore { model.store }
    /// O lugar nasce onde você está — é o caso comum e evita ter que arrastar
    /// um alfinete no mapa.
    private var here: CLLocationCoordinate2D? { store.selfMember?.coordinate }

    private let suggestions: [(String, String)] = [
        ("🏠", "Casa"), ("💼", "Trabalho"), ("👵", "Casa da vó"),
        ("🏫", "Escola"), ("🏋️", "Academia"), ("⛪", "Igreja"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: 54, height: 54)
                            .background(Color.accentOlive.opacity(0.25), in: .circle)
                        TextField("Nome do lugar", text: $name)
                            .font(.headline)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.1) { item in
                                Button {
                                    emoji = item.0
                                    if name.isEmpty { name = item.1 }
                                } label: {
                                    Text("\(item.0) \(item.1)")
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.accentOlive.opacity(0.18), in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Área") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Raio: \(Int(radius)) metros")
                            .font(.subheadline.weight(.semibold))
                        Slider(value: $radius, in: 50...1000, step: 10)
                            .tint(.accentAdaptive)
                        Text("Um raio pequeno demais faz a pessoa \"sair\" do lugar sozinha, porque o GPS oscila alguns metros.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let here {
                        Map(position: $camera, interactionModes: []) {
                            MapCircle(center: here, radius: radius)
                                .foregroundStyle(Color.accentAdaptive.opacity(0.15))
                                .stroke(Color.accentAdaptive, lineWidth: 2)
                            Marker(name.isEmpty ? "Aqui" : name, coordinate: here)
                                .tint(Color.accentAdaptive)
                        }
                        .frame(height: 190)
                        .clipShape(.rect(cornerRadius: 16))
                        .onAppear { frame(on: here) }
                        .onChange(of: radius) { _, _ in frame(on: here) }
                    } else {
                        Label("Esperando sua localização…", systemImage: "location.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Color.dangerRed)
                }
            }
            .navigationTitle("Novo lugar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || here == nil || saving)
                }
            }
        }
    }

    private func frame(on center: CLLocationCoordinate2D) {
        // Enquadra com folga para o círculo caber inteiro.
        let span = max(0.004, radius / 40_000)
        camera = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        ))
    }

    private func save() {
        guard let here else { return }
        saving = true
        error = nil
        Task {
            do {
                try await store.addPlace(name: name.trimmingCharacters(in: .whitespaces),
                                         emoji: emoji,
                                         latitude: here.latitude, longitude: here.longitude,
                                         radiusM: radius)
                dismiss()
            } catch {
                self.error = "Não foi possível salvar: \(error.localizedDescription)"
            }
            saving = false
        }
    }
}
