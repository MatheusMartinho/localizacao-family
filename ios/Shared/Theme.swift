import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Paleta da linguagem de design "Família" (DESIGN.md).
///
/// Regra de contraste: `accentLime` só sobre fundo **sempre** escuro (globo,
/// onboarding, Live Activity, botões de fundo `ink`), porque limão sobre
/// branco é ilegível. Onde a superfície acompanha o sistema — vidro, mapa,
/// listas — use `accentAdaptive`, que troca sozinho entre os dois.
extension Color {
    /// Verde-limão neon. Só sobre fundo escuro.
    static let accentLime = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3F / 255)
    /// Verde profundo para texto e ícones sobre fundo claro (contraste ~8:1).
    static let accentDeep = Color(red: 0x4C / 255, green: 0x5E / 255, blue: 0x18 / 255)
    /// O verde da marca **na versão que dá para ler no fundo atual**: oliva
    /// escuro no modo claro, limão no modo escuro.
    ///
    /// A regra acima sempre valeu, mas era aplicada à mão, e no modo escuro o
    /// app inteiro ficava com ícones oliva sobre vidro escuro — invisíveis. Use
    /// esta cor para tudo que é **desenhado por cima** de uma superfície que
    /// acompanha o sistema: ícone, texto, traço, `tint`. Para um preenchimento
    /// sólido que já traz o próprio texto claro em cima (um badge, por exemplo),
    /// continue usando `accentDeep`, que aí o contraste é interno.
    static let accentAdaptive: Color = {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3F / 255, alpha: 1)
                : UIColor(red: 0x4C / 255, green: 0x5E / 255, blue: 0x18 / 255, alpha: 1)
        })
        #else
        accentDeep
        #endif
    }()

    /// Verde-oliva da marca, usado em superfícies e realces suaves.
    static let accentOlive = Color(red: 0x6E / 255, green: 0x75 / 255, blue: 0x55 / 255)
    /// Preto quase puro: texto primário, botões escuros.
    static let ink = Color(red: 0x10 / 255, green: 0x12 / 255, blue: 0x10 / 255)
    /// Texto secundário.
    static let inkSoft = Color(red: 0x3A / 255, green: 0x3D / 255, blue: 0x38 / 255)
    /// Off-white: cartões, sheets.
    static let paper = Color(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF2 / 255)
    /// Paper no dark mode.
    static let paperDark = Color(red: 0x1A / 255, green: 0x1C / 255, blue: 0x19 / 255)
    /// Cinza-azulado: status "parado".
    static let stoppedGray = Color(red: 0x5C / 255, green: 0x62 / 255, blue: 0x75 / 255)
    /// Azul de rota. Deliberadamente fora da paleta da marca: rota tem que se
    /// distinguir da trilha e dos anéis dos avatares, todos verdes, e o azul
    /// é a convenção que todo mundo já lê como "caminho a seguir".
    static let routeBlue = Color(red: 0x1E / 255, green: 0x8B / 255, blue: 0xFF / 255)
    /// Bateria baixa, SOS.
    static let dangerRed = Color(red: 0xD9 / 255, green: 0x2B / 255, blue: 0x1F / 255)

    /// Cor do status de movimento, conforme o fundo.
    static func movement(_ isMoving: Bool, onDark: Bool = false) -> Color {
        if isMoving { return onDark ? .accentLime : .accentAdaptive }
        return onDark ? Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA6 / 255) : .stoppedGray
    }

    /// Cor para o nível de bateria, legível sobre fundo claro.
    static func battery(_ pct: Int) -> Color {
        if pct < 20 { return .dangerRed }
        if pct > 30 { return .accentAdaptive }
        return Color(red: 0xB0 / 255, green: 0x6A / 255, blue: 0x00 / 255)
    }
}
