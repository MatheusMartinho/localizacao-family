import simd
import CoreLocation

/// Geometria do globo: coordenadas ↔ vetores na esfera unitária, arcos de
/// grande círculo e distâncias.
enum GlobeMath {
    /// Deslocamento em graus entre a longitude real e a posição em que ela
    /// aparece na malha usada, porque cada uma alinha o centro da textura de
    /// um jeito. Sem a correção os pins caem longe do lugar certo — Lisboa
    /// chegou a aparecer no Himalaia. Quem define o valor é a `GlobeScene`,
    /// conforme a Terra que conseguiu carregar.
    enum Alignment {
        /// `MeshResource.generateSphere`: centro da textura 90° adiante do
        /// eixo que aponta para a câmera.
        static let sphere: Double = -90
    }

    /// Vetor unitário para (lat, lon). Longitude 0 fica no eixo +Z, que é o
    /// lado voltado para a câmera quando o globo está em repouso.
    static func unitVector(lat: Double, lon: Double, offset: Double) -> SIMD3<Float> {
        let la = Float(lat * .pi / 180)
        let lo = Float((lon + offset) * .pi / 180)
        return SIMD3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
    }

    /// Yaw/pitch (em radianos) que trazem (lat, lon) para o centro da tela.
    static func facing(lat: Double, lon: Double, offset: Double) -> (yaw: Float, pitch: Float) {
        (yaw: Float(-(lon + offset) * .pi / 180),
         pitch: Float(lat * .pi / 180))
    }

    /// Pontos ao longo do grande círculo entre `a` e `b`, levemente
    /// elevados no meio (`lift`) para o arco "sair" da superfície.
    static func greatCircle(from a: SIMD3<Float>, to b: SIMD3<Float>,
                            samples: Int, lift: Float) -> [SIMD3<Float>] {
        let dot = max(-1, min(1, simd_dot(a, b)))
        let omega = acos(dot)
        guard omega > 1e-4 else { return [a] }
        let so = sin(omega)
        return (0...samples).map { i in
            let t = Float(i) / Float(samples)
            let p = (sin((1 - t) * omega) / so) * a + (sin(t * omega) / so) * b
            return simd_normalize(p) * (1 + lift * sin(t * .pi))
        }
    }

    static func distanceMeters(_ a: FamilyMember, _ b: FamilyMember) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Diferença angular mínima (para animar o yaw pelo caminho curto).
    static func shortestDelta(from: Float, to: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}
