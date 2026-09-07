import RealityKit
import SwiftUI
import simd

/// Cena 3D do globo: Terra, atmosfera, céu estrelado, pins da família e o
/// arco entre você e a pessoa selecionada. Toda a animação (giro automático,
/// inércia do arrasto, voo até um membro, pulso dos pins) roda no loop de
/// frames para ficar suave.
@MainActor
final class GlobeScene {
    /// Gira com yaw/pitch; tudo que está "na Terra" é filho dele.
    let root = Entity()
    private let camera = PerspectiveCamera()
    private var pins: [String: ModelEntity] = [:]
    private var halos: [String: ModelEntity] = [:]
    private let arc = Entity()
    private var subscription: EventSubscription?
    private var lastArcKey = ""
    /// `true` quando encontrou uma textura fotográfica no bundle.
    private(set) var hasRealEarth = false

    // Estado de animação.
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var yawVelocity: Float = 0
    private var pitchVelocity: Float = 0
    private var targetYaw: Float?
    private var targetPitch: Float?
    private var idle: Float = 3
    private var time: Float = 0
    /// Distância que enquadra o globo pela largura de um iPhone em pé.
    private var cameraDistance: Float = 6.4
    private var targetCameraDistance: Float = 6.4
    private var dragging = false
    /// O giro automático só entra depois que o usuário explora o globo. Logo
    /// após um "voo" até alguém ele fica desligado, senão o globo se afastaria
    /// sozinho da pessoa que você acabou de escolher.
    private var allowAutoSpin = false

    private static let lime = UIColor(red: 0xD4 / 255, green: 1, blue: 0x3F / 255, alpha: 1)
    private static let stopped = UIColor(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA6 / 255, alpha: 1)
    private static let autoSpin: Float = 0.06
    /// Segundos parado antes de o giro automático voltar.
    private static let idleBeforeSpin: Float = 4
    /// Alinhamento da malha do `earth.usdz` (calibrado na tela).
    private static let modelLongitudeOffset: Double = 90

    /// Correção de longitude da Terra que efetivamente carregou.
    private var longitudeOffset: Double = GlobeMath.Alignment.sphere

    // MARK: - Construção

    func build(into content: inout RealityViewCameraContent) async {
        // Desenhar as texturas fora da main thread mantém a abertura suave.
        let (starsImage, neonImage) = await Task.detached(priority: .userInitiated) {
            (GlobeTextures.starfield(), GlobeTextures.neonEarth())
        }.value

        // Céu: quando existe uma foto (`sky.jpg`), ela entra como fundo plano
        // da tela — a `GlobeScreen` cuida disso — porque uma foto comum não é
        // equiretangular e esticaria se envolvesse a esfera. Sem foto, a
        // cúpula procedural.
        if !Self.hasSkyPhoto,
           let stars = try? await TextureResource(image: starsImage, withName: "stars",
                                                  options: .init(semantic: .color)) {
            var sky = UnlitMaterial()
            sky.color = .init(tint: .white, texture: .init(stars))
            sky.faceCulling = .front
            let skyDome = ModelEntity(mesh: .generateSphere(radius: 60), materials: [sky])
            content.add(skyDome)
        }

        // Terra: o modelo 3D do bundle; se faltar, a esfera "neon" procedural.
        if let model = await Self.loadEarthModel() {
            hasRealEarth = true
            longitudeOffset = Self.modelLongitudeOffset
            root.addChild(model)
        } else {
            longitudeOffset = GlobeMath.Alignment.sphere
            var neon = UnlitMaterial()
            if let tex = try? await TextureResource(image: neonImage, withName: "neon-earth",
                                                    options: .init(semantic: .color)) {
                neon.color = .init(tint: .white, texture: .init(tex))
            } else {
                neon.color = .init(tint: UIColor(red: 0.043, green: 0.07, blue: 0.125, alpha: 1), texture: nil)
            }
            root.addChild(ModelEntity(mesh: .generateSphere(radius: 1), materials: [neon]))
        }

        // Atmosfera: cascas translúcidas renderizadas pela face de dentro
        // (`faceCulling = .front`), então só aparecem na borda do disco,
        // como um halo — não por cima da Terra.
        for (radius, alpha) in [(Float(1.008), Float(0.30)), (Float(1.022), Float(0.13)),
                                (Float(1.045), Float(0.06)), (Float(1.075), Float(0.03))] {
            var glow = UnlitMaterial()
            glow.color = .init(tint: UIColor(red: 0.62, green: 0.98, blue: 0.62, alpha: 1), texture: nil)
            glow.blending = .transparent(opacity: .init(floatLiteral: alpha))
            glow.faceCulling = .front
            let shell = ModelEntity(mesh: .generateSphere(radius: radius), materials: [glow])
            root.addChild(shell)
        }

        root.addChild(arc)
        content.add(root)

        // Luz do "sol" vinda da frente-esquerda-cima.
        let sun = DirectionalLight()
        sun.light.intensity = 1800
        sun.look(at: .zero, from: [-2.5, 1.8, 3], relativeTo: nil)
        content.add(sun)

        camera.camera.fieldOfViewInDegrees = 40
        camera.position = [0, 0, cameraDistance]
        camera.look(at: .zero, from: camera.position, relativeTo: nil)
        content.camera = .virtual
        content.add(camera)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(dt: Float(event.deltaTime))
        }
    }

    // MARK: - Dados

    /// Sincroniza pins, halos e o arco com a família atual.
    func update(members: [FamilyMember], selectedID: String?) {
        let located = members.filter { $0.latitude != 0 || $0.longitude != 0 }
        let ids = Set(located.map(\.id))

        for (id, pin) in pins where !ids.contains(id) {
            pin.removeFromParent()
            halos[id]?.removeFromParent()
            pins[id] = nil
            halos[id] = nil
        }

        for member in located {
            let position = GlobeMath.unitVector(lat: member.latitude, lon: member.longitude,
                                                offset: longitudeOffset) * 1.006
            let color = member.isMoving ? Self.lime : Self.stopped
            let isSelected = member.id == selectedID

            if let pin = pins[member.id] {
                pin.move(to: Transform(scale: .one * (isSelected ? 1.5 : 1), rotation: .init(), translation: position),
                         relativeTo: root, duration: 0.8, timingFunction: .easeInOut)
                pin.model?.materials = [Self.unlit(color)]
            } else {
                let pin = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [Self.unlit(color)])
                pin.position = position
                pin.scale = .one * (isSelected ? 1.5 : 1)
                root.addChild(pin)
                pins[member.id] = pin
            }

            if let halo = halos[member.id] {
                halo.position = position
                halo.model?.materials = [Self.unlit(color, opacity: member.isMoving ? 0.35 : 0.18)]
            } else {
                let halo = ModelEntity(mesh: .generateSphere(radius: 0.075),
                                       materials: [Self.unlit(color, opacity: member.isMoving ? 0.35 : 0.18)])
                halo.position = position
                root.addChild(halo)
                halos[member.id] = halo
            }
        }

        rebuildArc(members: located, selectedID: selectedID)
    }

    /// Arco pontilhado entre você e o membro selecionado (ou o único outro).
    private func rebuildArc(members: [FamilyMember], selectedID: String?) {
        guard let me = members.first(where: \.isSelf) else { return }
        let other = members.first { $0.id == selectedID && !$0.isSelf }
            ?? (members.count == 2 ? members.first { !$0.isSelf } : nil)
        let key = other.map { "\(me.latitude),\(me.longitude)->\($0.latitude),\($0.longitude)" } ?? ""
        guard key != lastArcKey else { return }
        lastArcKey = key

        arc.children.removeAll()
        guard let other else { return }
        let a = GlobeMath.unitVector(lat: me.latitude, lon: me.longitude, offset: longitudeOffset)
        let b = GlobeMath.unitVector(lat: other.latitude, lon: other.longitude, offset: longitudeOffset)
        let points = GlobeMath.greatCircle(from: a, to: b, samples: 56, lift: 0.14)
        let dotMaterial = Self.unlit(Self.lime, opacity: 0.9)
        for (i, p) in points.enumerated() {
            let dot = ModelEntity(mesh: .generateSphere(radius: i % 2 == 0 ? 0.009 : 0.006),
                                  materials: [dotMaterial])
            dot.position = p
            arc.addChild(dot)
        }
    }

    // MARK: - Interação

    func flyTo(lat: Double, lon: Double) {
        let facing = GlobeMath.facing(lat: lat, lon: lon, offset: longitudeOffset)
        targetYaw = yaw + GlobeMath.shortestDelta(from: yaw, to: facing.yaw)
        targetPitch = max(-1.2, min(1.2, facing.pitch))
        yawVelocity = 0
        pitchVelocity = 0
        idle = 0
        allowAutoSpin = false
    }

    func dragChanged(dx: Float, dy: Float) {
        dragging = true
        allowAutoSpin = true
        targetYaw = nil
        targetPitch = nil
        yaw += dx * 0.006
        pitch = max(-1.2, min(1.2, pitch + dy * 0.006))
        yawVelocity = dx * 0.35
        pitchVelocity = dy * 0.35
        idle = 0
    }

    func dragEnded() { dragging = false }

    func zoom(by factor: Float) {
        targetCameraDistance = max(2.4, min(9.5, targetCameraDistance / factor))
        idle = 0
    }

    // MARK: - Loop de frames

    private func tick(dt: Float) {
        let dt = min(dt, 1 / 30)
        time += dt
        idle += dt

        if let ty = targetYaw, let tp = targetPitch {
            // Voo suave: aproximação exponencial, sem "cair" no destino.
            let k = 1 - exp(-dt * 4.5)
            yaw += (ty - yaw) * k
            pitch += (tp - pitch) * k
            if abs(ty - yaw) < 0.002 && abs(tp - pitch) < 0.002 {
                targetYaw = nil
                targetPitch = nil
            }
        } else if !dragging {
            // Inércia do arrasto, depois volta ao giro lento automático.
            let damping = exp(-dt * 2.6)
            yawVelocity *= damping
            pitchVelocity *= damping
            let spinning = allowAutoSpin && idle > Self.idleBeforeSpin
            let spin = spinning ? Self.autoSpin * min(1, (idle - Self.idleBeforeSpin) / 2) : 0
            yaw += (yawVelocity + spin) * dt
            // A inclinação nunca é "corrigida" sozinha: ela é o enquadramento
            // que o usuário (ou o voo até alguém) escolheu.
            pitch = max(-1.2, min(1.2, pitch + pitchVelocity * dt))
        }

        root.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])

        cameraDistance += (targetCameraDistance - cameraDistance) * (1 - exp(-dt * 6))
        camera.position = [0, 0, cameraDistance]

        // Pulso dos halos.
        let pulse = 1 + 0.28 * sin(time * 2.6)
        for halo in halos.values { halo.scale = .one * pulse }
    }

    // MARK: - Materiais

    /// Existe uma foto de céu no bundle para usar como fundo?
    static var hasSkyPhoto: Bool { skyPhotoURL != nil }

    static var skyPhotoURL: URL? {
        Bundle.main.url(forResource: "sky", withExtension: "jpg")
            ?? Bundle.main.url(forResource: "sky", withExtension: "png")
    }

    /// Carrega `earth.usdz` do bundle, normaliza para raio 1 centrado na
    /// origem e troca os materiais por *unlit* — o modelo vem com material PBR
    /// e a iluminação de ambiente do RealityView (que não dá para desligar)
    /// estoura a exposição, deixando o globo branco.
    private static func loadEarthModel() async -> Entity? {
        guard let url = Bundle.main.url(forResource: "earth", withExtension: "usdz"),
              let model = try? await Entity(contentsOf: url) else { return nil }

        // A conversão glTF → USD já deixa o polo norte em +Y; qualquer rotação
        // extra aqui deita o globo.
        let bounds = model.visualBounds(recursive: true, relativeTo: nil)
        // `boundingRadius` é o raio da esfera que envolve a *caixa* — para uma
        // esfera isso dá r·√3 e encolheria a Terra em 42%. O raio de verdade é
        // metade da maior extensão.
        let radius = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z)) / 2
        guard radius > 0 else { return nil }
        let scale = 1 / radius
        model.scale = .one * scale
        model.position = -bounds.center * scale

        flattenMaterials(model)
        // Um contêiner isola o transform de normalização das rotações do globo.
        let holder = Entity()
        holder.addChild(model)
        return holder
    }

    /// Troca recursivamente materiais PBR por `UnlitMaterial` com a mesma
    /// textura, preservando a aparência sem depender de iluminação.
    private static func flattenMaterials(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard let pbm = material as? PhysicallyBasedMaterial,
                      let texture = pbm.baseColor.texture else { return material }
                var unlit = UnlitMaterial()
                unlit.color = .init(tint: UIColor(white: 0.9, alpha: 1),
                                    texture: .init(texture.resource))
                return unlit
            }
            entity.components.set(model)
        }
        for child in entity.children { flattenMaterials(child) }
    }

    private static func unlit(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: color, texture: nil)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }
}
