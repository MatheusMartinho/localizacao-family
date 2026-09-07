import SwiftUI

/// Raiz do app de Watch: lista da família com status ao vivo.
struct WatchRootView: View {
    @Bindable var model: WatchModel

    private var store: any FamilyStore { model.store }

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .loading:
                    ProgressView()
                        .tint(.accentLime)
                case .signedOut, .noFamily:
                    setupHint
                case .ready:
                    memberList
                }
            }
            .navigationTitle(store.family?.name ?? "Família")
        }
        .onAppear { model.startIfNeeded() }
    }

    /// No modo Supabase o login/família são feitos no iPhone.
    private var setupHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentLime)
            Text("Abra o Família no iPhone para entrar na sua família.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var memberList: some View {
        List {
            ForEach(store.sortedMembers) { member in
                NavigationLink(value: member.id) {
                    WatchMemberRow(member: member)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.background.secondary)
                )
            }
        }
        .listStyle(.carousel)
        .navigationDestination(for: String.self) { id in
            WatchMemberDetail(model: model, memberID: id)
        }
    }
}

/// Linha compacta: avatar com anel de status, nome, status + tempo.
struct WatchMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.background.secondary)
                Text(member.emoji)
                    .font(.system(size: 20))
                Circle()
                    .strokeBorder(member.isMoving ? Color.accentLime : Color.stoppedGray,
                                  lineWidth: 2.5)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.isSelf ? "\(member.name) (você)" : member.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(member.statusLine)
                    .font(.footnote)
                    .foregroundStyle(member.isMoving ? Color.accentLime : Color.stoppedGray)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
