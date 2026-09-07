import SwiftUI

/// Onboarding em 3 passos: boas-vindas, permissão de localização e
/// criação/entrada na família (ou família demo).
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var step = 0

    var body: some View {
        ZStack {
            background
            VStack {
                switch step {
                case 0: WelcomeStep { withAnimation(.spring) { step = 1 } }
                case 1: LocationStep(engine: model.locationEngine) {
                    withAnimation(.spring) { step = 2 }
                }
                default: FamilySetupStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .tint(.accentLime)
    }

    private var background: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            Circle()
                .fill(Color.accentLime.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: 130, y: -280)
            Circle()
                .fill(Color.accentLime.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Passo 1: boas-vindas

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                PulseRing(color: .accentLime).scaleEffect(2.6)
                Circle()
                    .fill(Color.accentLime)
                    .frame(width: 110, height: 110)
                Image(systemName: "location.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            .frame(height: 160)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            Text("Família")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(Color.paper)
                .padding(.top, 28)

            Text("Veja onde cada pessoa da sua família\nestá, em tempo real — com carinho\ne privacidade.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paper.opacity(0.7))
                .padding(.top, 12)

            Spacer()

            Button(action: next) {
                Text("Começar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentLime)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9)) { appeared = true }
        }
    }
}

// MARK: - Passo 2: permissão de localização

private struct LocationStep: View {
    let engine: LocationEngine
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Color.accentLime)
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 32))

            Text("Compartilhe sua posição")
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(Color.paper)
                .padding(.top, 28)

            Text("Sua localização fica visível apenas para a\nsua família. Você pode pausar quando quiser,\ne o app avisa quando está compartilhando.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paper.opacity(0.7))
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    // Só "Durante o uso" aqui: o "Sempre" é pedido pelo
                    // LocationEngine quando este for concedido. Os dois juntos
                    // faziam o segundo pedido ser engolido.
                    engine.requestWhenInUse()
                    next()
                } label: {
                    Label("Permitir localização", systemImage: "location.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentLime)
                .foregroundStyle(Color.ink)

                Button("Agora não", action: next)
                    .buttonStyle(.glass)
                    .foregroundStyle(Color.paper)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Passo 3: criar/entrar na família

private struct FamilySetupStep: View {
    @Bindable var model: AppModel

    // Auth (modo Supabase).
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var emoji = "🙂"
    @State private var isSigningUp = true

    // Família.
    @State private var familyName = ""
    @State private var joinCode = ""
    @State private var busy = false
    @State private var errorText: String?

    private var store: any FamilyStore { model.store }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let code = model.pendingInviteCode {
                    inviteCodeCard(code)
                } else if model.isCreatingFamily {
                    ProgressView().tint(.accentLime).padding(.top, 120)
                } else if store.isDemo {
                    demoContent
                } else {
                    switch store.phase {
                    case .loading:
                        ProgressView().tint(.accentLime).padding(.top, 120)
                    case .signedOut:
                        authForm
                    case .noFamily:
                        familyForm
                    case .ready:
                        Color.clear.onAppear { model.onboardingDone = true }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Color.dangerRed)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Demo

    private var demoContent: some View {
        VStack(spacing: 18) {
            header(title: "Sua família, num só mapa",
                   subtitle: "O backend Supabase ainda não foi configurado\n(veja Config.swift). Enquanto isso, explore o app\ncom uma família de demonstração em São Paulo.")

            Button {
                model.enterDemo()
            } label: {
                Label("Explorar com família demo", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentLime)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 28)

            Text("Mãe, Pai, Ana e Vovó já estão passeando por lá.")
                .font(.footnote)
                .foregroundStyle(Color.paper.opacity(0.55))
        }
    }

    // MARK: Auth

    private var authForm: some View {
        VStack(spacing: 16) {
            header(title: isSigningUp ? "Criar sua conta" : "Entrar",
                   subtitle: "Sua conta conecta você à sua família\nem qualquer aparelho.")

            VStack(spacing: 12) {
                if isSigningUp {
                    glassField("Seu nome", text: $displayName)
                    emojiPicker
                }
                glassField("E-mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                glassSecureField("Senha", text: $password)
            }
            .padding(.horizontal, 28)

            Button {
                run {
                    if isSigningUp {
                        try await store.signUp(email: email, password: password,
                                               displayName: displayName.isEmpty ? "Eu" : displayName,
                                               emoji: emoji)
                    } else {
                        try await store.signIn(email: email, password: password)
                    }
                }
            } label: {
                Group {
                    if busy { ProgressView().tint(Color.ink) }
                    else { Text(isSigningUp ? "Criar conta" : "Entrar").font(.headline) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentLime)
            .foregroundStyle(Color.ink)
            .disabled(busy || email.isEmpty || password.isEmpty)
            .padding(.horizontal, 28)

            Button(isSigningUp ? "Já tenho conta" : "Quero criar uma conta") {
                isSigningUp.toggle()
            }
            .font(.subheadline)
            .foregroundStyle(Color.paper.opacity(0.8))
        }
    }

    private var emojiPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(["🙂", "👩", "👨", "👧", "👦", "👵", "👴", "🧑", "🐶"], id: \.self) { option in
                    Button {
                        emoji = option
                    } label: {
                        Text(option)
                            .font(.system(size: 28))
                            .frame(width: 48, height: 48)
                            .glassEffect(emoji == option
                                         ? .regular.tint(.accentLime.opacity(0.6)).interactive()
                                         : .regular.interactive(),
                                         in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Família

    private var familyForm: some View {
        VStack(spacing: 22) {
            header(title: "Monte sua família",
                   subtitle: "Crie um grupo novo ou entre com o código\nque alguém compartilhou com você.")

            VStack(spacing: 12) {
                glassField("Nome da família (ex.: Família Silva)", text: $familyName)
                Button {
                    model.isCreatingFamily = true
                    busy = true
                    errorText = nil
                    Task {
                        do {
                            try await store.createFamily(
                                named: familyName.isEmpty ? "Minha família" : familyName)
                            model.pendingInviteCode = store.family?.inviteCode
                        } catch {
                            errorText = error.localizedDescription
                            model.isCreatingFamily = false
                        }
                        busy = false
                    }
                } label: {
                    Label("Criar família", systemImage: "house.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentLime)
                .foregroundStyle(Color.ink)
                .disabled(busy)
            }
            .padding(.horizontal, 28)

            Text("ou")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.paper.opacity(0.5))

            VStack(spacing: 12) {
                glassField("Código de convite (6 letras)", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    run {
                        try await store.joinFamily(code: joinCode)
                        model.onboardingDone = true
                    }
                } label: {
                    Label("Entrar com código", systemImage: "person.badge.key.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .disabled(busy || joinCode.count < 6)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: Código gigante

    private func inviteCodeCard(_ code: String) -> some View {
        VStack(spacing: 24) {
            header(title: "Família criada!",
                   subtitle: "Compartilhe este código para\ntodo mundo entrar.")

            Text(code)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .tracking(10)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color.accentLime)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
                .background(Color.ink.opacity(0.85), in: .rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Color.accentLime.opacity(0.5), lineWidth: 2)
                )
                .padding(.horizontal, 28)

            ShareLink(item: "Entre na nossa família no app Família! Código: \(code)") {
                Label("Compartilhar código", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentLime)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 28)

            Button("Ir para o mapa") {
                model.pendingInviteCode = nil
                model.isCreatingFamily = false
                model.onboardingDone = true
            }
            .buttonStyle(.glass)
            .foregroundStyle(Color.paper)
        }
    }

    // MARK: Helpers

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.paper)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paper.opacity(0.7))
        }
        .padding(.horizontal, 24)
    }

    private func glassField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(Color.paper)
    }

    private func glassSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(Color.paper)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        errorText = nil
        Task {
            do { try await work() }
            catch { errorText = error.localizedDescription }
            busy = false
        }
    }
}
