import SwiftUI

@main
struct FamiliaWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .tint(.accentLime)
        }
    }
}

/// Coordenador do app de Watch: mesmo FamilyStore compartilhado do iPhone
/// (demo ou Supabase, conforme Config).
@MainActor
@Observable
final class WatchModel {
    let store: any FamilyStore
    private var started = false

    init() {
        store = Config.isConfigured ? SupabaseFamilyStore() : MockFamilyStore()
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { await store.start() }
    }
}
