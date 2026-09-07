import SwiftUI

/// Paleta da linguagem de design "Família" (DESIGN.md).
///
/// Regra de contraste: **`accentLime` só sobre fundo escuro** (globo,
/// onboarding, Live Activity, botões de fundo `ink`). Sobre vidro claro ou
/// mapa, use `accentDeep` — o limão puro sobre branco fica ilegível.
extension Color {
    /// Verde-limão neon. Só sobre fundo escuro.
    static let accentLime = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3F / 255)
    /// Verde profundo para texto e ícones sobre fundo claro (contraste ~8:1).
    static let accentDeep = Color(red: 0x4C / 255, green: 0x5E / 255, blue: 0x18 / 255)
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
    /// Bateria baixa, SOS.
    static let dangerRed = Color(red: 0xD9 / 255, green: 0x2B / 255, blue: 0x1F / 255)

    /// Cor do status de movimento, conforme o fundo.
    static func movement(_ isMoving: Bool, onDark: Bool = false) -> Color {
        if isMoving { return onDark ? .accentLime : .accentDeep }
        return onDark ? Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA6 / 255) : .stoppedGray
    }

    /// Cor para o nível de bateria, legível sobre fundo claro.
    static func battery(_ pct: Int) -> Color {
        if pct < 20 { return .dangerRed }
        if pct > 30 { return .accentDeep }
        return Color(red: 0xB0 / 255, green: 0x6A / 255, blue: 0x00 / 255)
    }
}
