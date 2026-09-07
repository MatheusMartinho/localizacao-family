import Foundation

/// Configuração do backend Supabase.
///
/// Os valores **não ficam neste arquivo**: vêm do `Secrets.xcconfig`, que é
/// ignorado pelo git, entram no `Info.plist` pelo XcodeGen e são lidos aqui.
/// Copie o `ios/Secrets.example.xcconfig` para `ios/Secrets.xcconfig` e
/// preencha (veja o README).
///
/// Sem esse arquivo o app **não quebra**: cai no modo demonstração, com uma
/// família fictícia se movendo por São Paulo (`MockFamilyStore`). É de propósito
/// — quem clona o repositório consegue rodar e ver tudo sem backend nenhum.
enum Config {
    /// Guardado como host puro, sem esquema: no xcconfig, `//` começa um
    /// comentário e comeria o resto da linha de uma URL completa.
    private static let supabaseHost = value(for: "SupabaseHost")
    static let supabaseAnonKey = value(for: "SupabaseAnonKey")

    static var supabaseURL: String { "https://\(supabaseHost)" }

    /// `true` quando as credenciais reais foram preenchidas.
    static var isConfigured: Bool {
        guard !supabaseHost.isEmpty, !supabaseAnonKey.isEmpty,
              !supabaseHost.contains("SEU-PROJETO"),
              !supabaseAnonKey.contains("COLOQUE"),
              let url = URL(string: supabaseURL), url.host != nil else { return false }
        return true
    }

    private static func value(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
