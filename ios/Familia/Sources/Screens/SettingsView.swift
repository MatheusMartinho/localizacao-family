import SwiftUI
import PhotosUI

/// Ajustes: perfil, família (código, membros, sair) e privacidade.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🙂"
    @State private var loaded = false
    @State private var confirmLeave = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var savingPhoto = false
    @State private var confirmDelete = false
    @State private var deletingAccount = false

    private var store: any FamilyStore { model.store }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                placesSection
                familySection
                privacySection
                accountSection
                if store.isDemo { demoSection }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Ops", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") {
                        let novo = name.trimmingCharacters(in: .whitespaces)
                        // Nome vazio quebra a checagem do banco: mantém o atual.
                        let final = novo.isEmpty ? (store.selfMember?.name ?? "Eu") : novo
                        Task { try? await store.updateProfile(name: final, emoji: emoji) }
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(.thickMaterial)
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .onAppear { loadProfileIfNeeded() }
        // O perfil pode chegar depois da tela abrir; sem isto o campo do nome
        // ficava vazio e "Concluir" salvava um nome em branco.
        .onChange(of: store.selfMember) { _, _ in loadProfileIfNeeded() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            savingPhoto = true
            Task {
                defer { savingPhoto = false; pickedPhoto = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = Self.squareThumbnail(from: data) else { return }
                do { try await store.updatePhoto(jpeg) }
                catch { store.errorMessage = "Não foi possível salvar a foto: \(error.localizedDescription)" }
            }
        }
    }

    private func loadProfileIfNeeded() {
        guard !loaded, let me = store.selfMember else { return }
        loaded = true
        name = me.name
        emoji = me.emoji
    }

    // MARK: Perfil

    /// Lido aqui, no corpo da view (que é `@MainActor`), e não dentro do label
    /// do `PhotosPicker` — aquele closure não é isolado, e ler `selfMember`
    /// dali é erro sob a concorrência estrita do Swift 6.
    private var profilePhoto: UIImage? {
        store.selfMember?.photo.flatMap(UIImage.init(data:))
    }

    private var profileSection: some View {
        let photo = profilePhoto
        return Section("Seu perfil") {
            HStack(spacing: 14) {
                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                Text(emoji).font(.system(size: 32))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.accentOlive.opacity(0.3))
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(.circle)

                        Image(systemName: savingPhoto ? "arrow.triangle.2.circlepath" : "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.paper)
                            .padding(5)
                            .background(Color.accentDeep, in: .circle)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .disabled(savingPhoto)

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Seu nome", text: $name)
                        .font(.headline)
                    Text(photo == nil
                         ? "Toque na foto para escolher da galeria"
                         : "Toque para trocar a foto")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if photo != nil {
                Button("Remover foto", role: .destructive) {
                    Task { try? await store.updatePhoto(nil) }
                }
                .font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["🙂", "👩", "👨", "👧", "👦", "👵", "👴", "🧑", "🐶", "😎", "🦊"], id: \.self) { option in
                        Button {
                            emoji = option
                        } label: {
                            Text(option)
                                .font(.system(size: 26))
                                .frame(width: 42, height: 42)
                                .background(
                                    emoji == option ? Color.accentOlive.opacity(0.45) : Color.clear,
                                    in: .circle
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Lugares

    private var placesSection: some View {
        Section {
            NavigationLink {
                PlacesView(model: model)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lugares da família")
                        Text(store.places.isEmpty
                             ? "Marque casa, trabalho, casa da vó…"
                             : store.places.map(\.label).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "house.fill")
                        .foregroundStyle(Color.accentAdaptive)
                }
            }
        }
    }

    // MARK: Família

    private var familySection: some View {
        Section("Família") {
            if let family = store.family {
                LabeledContent("Nome") { Text(family.name) }
                HStack {
                    Text("Código de convite")
                    Spacer()
                    Text(family.inviteCode)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        // O código passou de 6 para 10 caracteres (migração
                        // 0007): menos espaçamento, e encolhe em vez de cortar
                        // nas telas estreitas.
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.accentAdaptive)
                    ShareLink(item: "Entre na nossa família no app Família! Código: \(family.inviteCode)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ForEach(store.sortedMembers) { member in
                    HStack {
                        Text(member.emoji)
                        Text(member.isSelf ? "\(member.name) (você)" : member.name)
                        Spacer()
                        Text("\(member.batteryPct)%")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.battery(member.batteryPct))
                    }
                }
                Button("Sair da família", role: .destructive) {
                    confirmLeave = true
                }
                .confirmationDialog("Sair da família?", isPresented: $confirmLeave) {
                    Button("Sair", role: .destructive) {
                        // Sem `try?`: se falhar, o usuário precisa saber que
                        // continua compartilhando a localização.
                        Task {
                            do {
                                try await store.leaveFamily()
                                dismiss()
                            } catch {
                                store.errorMessage = "Não foi possível sair da família: \(error.localizedDescription)"
                            }
                        }
                    }
                } message: {
                    Text("Sua família não verá mais a sua localização.")
                }
            } else {
                Text("Sem família ainda").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Privacidade

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.sharingPaused },
                set: { store.sharingPaused = $0 }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pausar compartilhamento")
                        // Dito na hora da escolha, não escondido num rodapé: a
                        // pessoa precisa saber que a família será avisada
                        // *antes* de pausar, senão a pausa vira uma armadilha.
                        Text("Sua posição para de ser enviada — e sua família é avisada da pausa.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(Color.stoppedGray)
                }
            }
            .tint(.accentAdaptive)

            Menu {
                Button("Silenciar por 1 hora") { model.snoozeAlerts(hours: 1) }
                Button("Silenciar por 8 horas") { model.snoozeAlerts(hours: 8) }
                Button("Silenciar até amanhã de manhã") { model.snoozeAlertsUntilMorning() }
                if model.alertsSnoozed {
                    Divider()
                    Button("Voltar a receber", role: .destructive) { model.cancelSnooze() }
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silenciar avisos")
                            .foregroundStyle(.primary)
                        Text(model.snoozeSummary)
                            .font(.caption)
                            .foregroundStyle(model.alertsSnoozed ? Color.accentAdaptive : .secondary)
                    }
                } icon: {
                    Image(systemName: model.alertsSnoozed ? "bell.slash.fill" : "bell.fill")
                        .foregroundStyle(model.alertsSnoozed ? Color.accentAdaptive : Color.stoppedGray)
                }
            }

            Toggle(isOn: Binding(
                get: { model.liveActivityEnabled },
                set: { model.liveActivityEnabled = $0; model.refreshLiveActivity() }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tela de bloqueio")
                        Text(lockScreenSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.iphone")
                        .foregroundStyle(Color.accentAdaptive)
                }
            }
            .tint(.accentAdaptive)

            NavigationLink {
                PlaceAlertsView(model: model)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chegadas e saídas")
                        Text(model.placeAlertsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "figure.walk.arrival")
                        .foregroundStyle(Color.accentAdaptive)
                }
            }

            Toggle(isOn: Binding(
                get: { model.pauseAlertsEnabled },
                set: { on in
                    model.pauseAlertsEnabled = on
                    if on { Task { await model.alertCenter.requestPermission() } }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pausas da família")
                        Text("Avisar quando alguém pausa ou retoma o compartilhamento.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(Color.accentAdaptive)
                }
            }
            .tint(.accentAdaptive)

            if let pinned = model.store.member(id: model.pinnedMemberID) {
                HStack {
                    AvatarView(member: pinned, size: 30, ring: 2)
                    Text(pinned.isSelf ? "Você" : pinned.name)
                    Spacer()
                    Button("Parar") { model.pinnedMemberID = nil }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dangerRed)
                }
            }
        } header: {
            Text("Privacidade")
        } footer: {
            Text("Ninguém aparece na tela de bloqueio até você marcar a pessoa no perfil dela. Silenciar avisos cala tudo menos o alarme de pânico.")
        }
    }

    private var lockScreenSummary: String {
        guard model.liveActivityEnabled else { return "Desligado." }
        if let pinned = model.store.member(id: model.pinnedMemberID) {
            return "Acompanhando \(pinned.isSelf ? "você" : pinned.name)."
        }
        return "Ninguém marcado — abra o perfil de alguém para escolher."
    }

    /// Reduz a foto a um quadrado de 320px em JPEG — a imagem viaja dentro da
    /// linha do perfil, então precisa ser pequena.
    private static func squareThumbnail(from data: Data, side: CGFloat = 320) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let crop = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - crop) / 2, y: (image.size.height - crop) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { _ in
                image.draw(in: CGRect(x: -origin.x * side / crop, y: -origin.y * side / crop,
                                      width: image.size.width * side / crop,
                                      height: image.size.height * side / crop))
            }
            .jpegData(compressionQuality: 0.75)
    }

    // MARK: Conta

    /// Exclusão de conta, exigida pela App Store (diretriz 5.1.1(v)) e devida
    /// de qualquer forma num app que guarda onde as pessoas estiveram.
    ///
    /// Fica numa seção própria, e não escondida dentro de "Família": sair da
    /// família e apagar a conta são coisas muito diferentes, e a primeira
    /// estava logo acima. O texto do alerta lista o que some, porque não tem
    /// volta.
    private var accountSection: some View {
        Section {
            Button("Apagar minha conta", role: .destructive) { confirmDelete = true }
                .disabled(deletingAccount)
        } header: {
            Text("Conta")
        } footer: {
            Text("Apagar a conta remove você do app e do servidor. Sair da família, acima, mantém sua conta.")
        }
        .alert("Apagar sua conta?", isPresented: $confirmDelete) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) { deleteAccount() }
        } message: {
            Text("Some para sempre: seu perfil, sua localização atual, o histórico de onde você esteve, seus avisos e sua participação nas famílias. Não dá para desfazer.")
        }
    }

    private func deleteAccount() {
        deletingAccount = true
        Task {
            defer { deletingAccount = false }
            do {
                try await store.deleteAccount()
                dismiss()
            } catch {
                store.errorMessage = "Não foi possível apagar a conta: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Demo

    private var demoSection: some View {
        Section {
            Label {
                Text("Modo demonstração ativo. Preencha `Config.swift` com a URL e a anon key do seu projeto Supabase para conectar sua família de verdade.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentAdaptive)
            }
        } footer: {
            Text("Migração do banco em backend/supabase/migrations/0001_init.sql.")
        }
    }
}
