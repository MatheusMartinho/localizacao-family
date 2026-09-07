import CoreGraphics
import UIKit

/// Texturas geradas em tempo de execução para o globo. Não dependem de
/// nenhum arquivo: o céu estrelado é procedural (a menos que exista um
/// `sky.jpg` no bundle) e a Terra "neon" é o fallback quando não há modelo.
enum GlobeTextures {
    private static let lime = UIColor(red: 0xD4 / 255, green: 1, blue: 0x3F / 255, alpha: 1)

    /// Céu equiretangular: faixa da Via Láctea com núcleo brilhante, faixas de
    /// poeira escura e milhares de estrelas. Desenhado para lembrar uma foto de
    /// longa exposição do céu do hemisfério sul.
    static func starfield(width: Int = 4096, height: Int = 2048) -> CGImage {
        draw(width: width, height: height) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            var rng = SystemRandomNumberGenerator()

            // Fundo: preto azulado, não preto puro — dá profundidade.
            ctx.setFillColor(UIColor(red: 0.008, green: 0.010, blue: 0.022, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // A faixa da galáxia atravessa o céu na diagonal.
            let phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            func bandY(_ x: CGFloat) -> CGFloat { h * 0.52 + h * 0.20 * sin(x / w * 2 * .pi + phase) }
            /// Onde o núcleo (mais denso e mais quente) fica.
            let coreX = CGFloat.random(in: 0.2...0.8, using: &rng) * w
            func coreness(_ x: CGFloat) -> CGFloat {
                let d = min(abs(x - coreX), w - abs(x - coreX)) / (w * 0.22)
                return max(0, 1 - d * d)
            }

            ctx.setBlendMode(.plusLighter)

            // 1) Brilho difuso: manchas grandes e suaves ao longo da faixa.
            for _ in 0..<2600 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let spread = h * (0.055 + 0.05 * c)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * spread
                let r = CGFloat.random(in: 30...130, using: &rng) * (0.7 + c)
                // Núcleo puxa para o âmbar; as bordas, para o azul frio.
                let warm = min(1, c + CGFloat.random(in: 0...0.4, using: &rng))
                let color = UIColor(red: 0.30 + 0.34 * warm,
                                    green: 0.26 + 0.22 * warm,
                                    blue: 0.24 + 0.06 * warm,
                                    alpha: CGFloat.random(in: 0.006...0.022, using: &rng) * (0.5 + c))
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }

            // 2) Poeira: manchas escuras recortando a faixa, o que dá a
            //    textura "rasgada" característica da Via Láctea.
            ctx.setBlendMode(.normal)
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * h * 0.05
                let rx = CGFloat.random(in: 40...220, using: &rng)
                let ry = rx * CGFloat.random(in: 0.25...0.7, using: &rng)
                ctx.setFillColor(UIColor(red: 0.01, green: 0.012, blue: 0.03,
                                         alpha: CGFloat.random(in: 0.05...0.22, using: &rng) * (0.4 + c)).cgColor)
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: CGFloat.random(in: -0.6...0.6, using: &rng))
                ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
                ctx.restoreGState()
            }

            // 3) Estrelas da faixa: muitas, pequenas e amareladas.
            ctx.setBlendMode(.plusLighter)
            for _ in 0..<26000 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let c = coreness(x)
                let y = bandY(x) + CGFloat(gaussian(&rng)) * h * (0.05 + 0.04 * c)
                let r = CGFloat.random(in: 0.5...1.5, using: &rng)
                let warm = CGFloat.random(in: 0...1, using: &rng)
                ctx.setFillColor(UIColor(red: 1, green: 0.93 - 0.12 * warm, blue: 0.82 - 0.22 * warm,
                                         alpha: CGFloat.random(in: 0.10...0.55, using: &rng) * (0.5 + c)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }

            // 4) Estrelas do resto do céu, com distribuição de tamanhos em lei
            //    de potência: muitas fracas, poucas grandes.
            for _ in 0..<14000 {
                let x = CGFloat.random(in: 0..<w, using: &rng)
                let y = CGFloat.random(in: 0..<h, using: &rng)
                let t = CGFloat.random(in: 0...1, using: &rng)
                let r = 0.45 + pow(t, 7) * 3.2
                let roll = Double.random(in: 0...1, using: &rng)
                let color: UIColor = roll < 0.10 ? UIColor(red: 0.72, green: 0.82, blue: 1, alpha: 1)
                    : roll < 0.20 ? UIColor(red: 1, green: 0.86, blue: 0.72, alpha: 1)
                    : roll < 0.225 ? UIColor(red: 1, green: 0.72, blue: 0.62, alpha: 1)
                    : .white
                let alpha = CGFloat.random(in: 0.25...1, using: &rng)
                // As maiores ganham um halo, como numa foto de verdade.
                if r > 2 {
                    ctx.setFillColor(color.withAlphaComponent(0.10).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x - r * 4, y: y - r * 4, width: 8 * r, height: 8 * r))
                }
                ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            ctx.setBlendMode(.normal)
        }
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
    private static func gaussian(_ rng: inout SystemRandomNumberGenerator) -> Double {
        let u1 = max(Double.random(in: 0...1, using: &rng), 1e-9)
        let u2 = Double.random(in: 0...1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
