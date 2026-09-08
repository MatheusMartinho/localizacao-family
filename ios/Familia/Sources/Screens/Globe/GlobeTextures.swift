import CoreGraphics
import UIKit

/// Texturas geradas em tempo de execução para o globo. Não dependem de
/// nenhum arquivo: o céu estrelado é procedural (a menos que exista um
/// `sky.jpg` no bundle) e a Terra "neon" é o fallback quando não há modelo.
enum GlobeTextures {
    private static let lime = UIColor(red: 0xD4 / 255, green: 1, blue: 0x3F / 255, alpha: 1)

    /// Céu equiretangular: a faixa da Via Láctea com núcleo quente, faixas de
    /// poeira e dezenas de milhares de estrelas.
    ///
    /// Duas decisões que a primeira versão errava:
    ///
    /// - **Semente fixa.** O céu era sorteado a cada abertura, então o desenho
    ///   inteiro mudava toda vez que o globo abria. Céu não muda; é o mesmo céu.
    /// - **Brilho por gradiente, não por círculo.** As manchas eram elipses
    ///   chapadas em `plusLighter`: as bordas duras se acumulavam e viravam
    ///   borrões amarelados. Agora cada mancha é um gradiente radial que morre
    ///   em transparente, então elas se somam sem deixar contorno.
    static func starfield(width: Int = 4096, height: Int = 2048) -> CGImage {
        draw(width: width, height: height) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            var rng = SeededGenerator(seed: 0x5EED_5C1E_0000_C4FE)

            // Fundo: preto azulado, não preto puro — dá profundidade.
            ctx.setFillColor(UIColor(red: 0.006, green: 0.008, blue: 0.020, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // A faixa atravessa o céu na diagonal, com o núcleo galáctico
            // deslocado para um lado, como se vê do hemisfério sul.
            func bandY(_ x: CGFloat) -> CGFloat { h * 0.52 + h * 0.17 * sin(x / w * 2 * .pi + 1.1) }
            let coreX = w * 0.63
            func coreness(_ x: CGFloat) -> CGFloat {
                let d = min(abs(x - coreX), w - abs(x - coreX)) / (w * 0.26)
                return max(0, 1 - d * d)
            }

            ctx.setBlendMode(.plusLighter)

            // 1) Brilho difuso da faixa. Poucas manchas, grandes e macias.
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * h * (0.05 + 0.05 * c)
                let r = CGFloat.random(in: 90...320, using: &rng) * (0.6 + 0.8 * c)
                // O núcleo puxa para o creme; as asas, para o azul frio. Bem
                // menos saturado que antes — o amarelo forte é que dava o ar
                // de mancha de café.
                let warm = min(1, c + CGFloat.random(in: 0...0.25, using: &rng))
                let cor = UIColor(red: 0.42 + 0.28 * warm,
                                  green: 0.40 + 0.20 * warm,
                                  blue: 0.46 + 0.02 * warm, alpha: 1)
                blob(ctx, x, y, r, cor, CGFloat.random(in: 0.018...0.048, using: &rng) * (0.35 + c))
            }

            // 2) Poeira: manchas escuras recortando a faixa, também suaves.
            ctx.setBlendMode(.normal)
            for _ in 0..<420 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * h * 0.045
                let r = CGFloat.random(in: 70...260, using: &rng)
                blob(ctx, x, y, r, UIColor(red: 0.005, green: 0.007, blue: 0.018, alpha: 1),
                     CGFloat.random(in: 0.10...0.34, using: &rng) * (0.35 + c))
            }

            // 3) Estrelas da faixa: muitas, minúsculas, levemente quentes.
            ctx.setBlendMode(.plusLighter)
            for _ in 0..<42000 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * h * (0.045 + 0.04 * c)
                let r = CGFloat.random(in: 0.4...1.3, using: &rng)
                let warm = CGFloat.random(in: 0...1, using: &rng)
                ctx.setFillColor(UIColor(red: 1, green: 0.95 - 0.10 * warm, blue: 0.88 - 0.18 * warm,
                                         alpha: CGFloat.random(in: 0.10...0.55, using: &rng) * (0.45 + c)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }

            // 4) Estrelas do resto do céu, com distribuição de tamanhos em lei
            //    de potência: muitas fracas, poucas grandes.
            for _ in 0..<22000 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let y = CGFloat.random(in: 0..<h, using: &rng)
                let t = CGFloat.random(in: 0...1, using: &rng)
                let r = 0.4 + pow(t, 8) * 3.4
                let roll = Double.random(in: 0...1, using: &rng)
                let cor: UIColor = roll < 0.12 ? UIColor(red: 0.70, green: 0.80, blue: 1, alpha: 1)
                    : roll < 0.22 ? UIColor(red: 1, green: 0.87, blue: 0.74, alpha: 1)
                    : roll < 0.245 ? UIColor(red: 1, green: 0.74, blue: 0.64, alpha: 1)
                    : .white
                let alpha = CGFloat.random(in: 0.25...1, using: &rng)
                if r > 1.9 {
                    // Halo e cruz de difração: é o que faz uma estrela parecer
                    // fotografada em vez de um ponto colado na tela.
                    blob(ctx, x, y, r * 7, cor, 0.16)
                    let braco = r * 7
                    ctx.setFillColor(cor.withAlphaComponent(0.20).cgColor)
                    ctx.fill(CGRect(x: x - braco, y: y - 0.4, width: 2 * braco, height: 0.8))
                    ctx.fill(CGRect(x: x - 0.4, y: y - braco, width: 0.8, height: 2 * braco))
                }
                ctx.setFillColor(cor.withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            ctx.setBlendMode(.normal)
        }
    }

    /// Mancha macia: gradiente radial que morre em transparente, para as
    /// manchas se somarem sem deixar borda visível.
    private static func blob(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat,
                             _ r: CGFloat, _ cor: UIColor, _ alpha: CGFloat) {
        let cores = [cor.withAlphaComponent(alpha).cgColor,
                     cor.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: cores, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                               endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }

    /// Terra "neon": oceano escuro com grade de latitude/longitude verde-limão.
    /// Usada quando o modelo 3D não está disponível.
    static func neonEarth(width: Int = 2048, height: Int = 1024) -> CGImage {
        draw(width: width, height: height) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            ctx.setFillColor(UIColor(red: 0.043, green: 0.07, blue: 0.125, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let colors = [UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 0).cgColor,
                          UIColor(red: 0.09, green: 0.16, blue: 0.22, alpha: 0.55).cgColor,
                          UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
            }

            ctx.setLineCap(.round)
            // O contexto tem origem embaixo, então `+ deg` deixa o norte no
            // topo da imagem — a convenção equiretangular padrão.
            for deg in stride(from: -75, through: 75, by: 15) {
                let y = h * 0.5 + CGFloat(deg) / 180 * h
                let strong = deg == 0 || abs(deg) == 30
                ctx.setStrokeColor(lime.withAlphaComponent(strong ? 0.55 : 0.22).cgColor)
                ctx.setLineWidth(strong ? 2.6 : 1.4)
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)); ctx.strokePath()
            }
            for deg in stride(from: -180, to: 180, by: 15) {
                let x = w * 0.5 + CGFloat(deg) / 360 * w
                let strong = deg == 0
                ctx.setStrokeColor(lime.withAlphaComponent(strong ? 0.55 : 0.2).cgColor)
                ctx.setLineWidth(strong ? 2.6 : 1.4)
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)); ctx.strokePath()
            }
            var rng = SystemRandomNumberGenerator()
            ctx.setFillColor(lime.withAlphaComponent(0.10).cgColor)
            for _ in 0..<6000 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let y = CGFloat.random(in: 0..<h, using: &rng)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2.2, height: 2.2))
            }
        }
    }

    // MARK: - Helpers

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(ctx)
        return ctx.makeImage()!
    }

    /// Amostra gaussiana (Box–Muller) para espalhar estrelas e poeira.
    private static func gaussian(_ rng: inout SeededGenerator) -> Double {
        let u1 = max(Double.random(in: 0...1, using: &rng), 1e-9)
        let u2 = Double.random(in: 0...1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// Gerador determinístico (SplitMix64). O céu precisa ser sempre o mesmo céu:
/// com o gerador do sistema, cada abertura do globo sorteava um desenho novo.
struct SeededGenerator: RandomNumberGenerator {
    private var estado: UInt64
    init(seed: UInt64) { estado = seed }

    mutating func next() -> UInt64 {
        estado &+= 0x9E37_79B9_7F4A_7C15
        var z = estado
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
