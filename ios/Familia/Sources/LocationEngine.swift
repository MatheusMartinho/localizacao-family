import Foundation
import CoreLocation
import MapKit
import UIKit
import Observation

/// Motor de localização: CoreLocation com atualizações em background e a
/// máquina de estado movendo/parado do DESIGN.md:
///
/// - `speed > 1.4 m/s` sustentado por 30 s → **em movimento**
/// - 90 s abaixo do limiar → **parado**
/// - `stateSince` marca quando o estado atual começou.
@Observable
final class LocationEngine: NSObject, CLLocationManagerDelegate {
    /// Chamado na main queue a cada snapshot novo da própria posição.
    @ObservationIgnored var onSnapshot: ((OwnLocationSnapshot) -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isMoving = false
    private(set) var stateSince = Date.now
    private(set) var lastLocation: CLLocation?
    private(set) var placeHint: String?

    private let manager = CLLocationManager()
    private static let movingThreshold: CLLocationSpeed = 1.4
    private static let promoteAfter: TimeInterval = 30
    private static let demoteAfter: TimeInterval = 90

    /// Desde quando a velocidade está acima do limiar (candidato a "movendo").
    private var aboveSince: Date?
    /// Desde quando está abaixo do limiar (candidato a "parado").
    private var belowSince: Date?
    private var lastGeocode = Date.distantPast
    private var isGeocoding = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Controle

    /// Pede só "Durante o uso". O "Sempre" vem depois, sozinho, quando este
    /// primeiro for concedido — veja `locationManagerDidChangeAuthorization`.
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// O sistema só mostra o pedido de "Sempre" uma vez por instalação; a flag
    /// evita repetir a chamada a cada mudança de estado.
    private var askedForAlways = false

    func startIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        default:
            break
        }
    }

    private func startUpdating() {
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Força uma leitura imediata — usado quando alguém pede "cadê você?".
    func requestImmediateUpdate() {
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.startIfAuthorized()

            // "Sempre" só pode ser pedido **depois** que "Durante o uso" foi
            // concedido. Pedir os dois em seguida, como o onboarding fazia,
            // faz o CoreLocation ignorar o segundo pedido enquanto o primeiro
            // alerta está na tela: o app ficava só com "Durante o uso" e
            // portanto sem localização em segundo plano — que é o app inteiro.
            if status == .authorizedWhenInUse, !self.askedForAlways {
                self.askedForAlways = true
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.ingest(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// Uma linha curta para caber na pílula do mapa, na lista e no widget.
    ///
    /// O `shortAddress` do MapKit é bem menos curto do que o nome sugere —
    /// "Avenida Paulista, 1578, Bela Vista, São Paulo". O primeiro componente
    /// é a rua (ou o nome do lugar), que é o que o `CLGeocoder` dava antes.
    private static func shortHint(from item: MKMapItem) -> String? {
        if let short = item.address?.shortAddress,
           let primeiro = short.split(separator: ",").first {
            let rua = primeiro.trimmingCharacters(in: .whitespaces)
            if !rua.isEmpty { return rua }
        }
        return item.addressRepresentations?.cityName ?? item.name
    }

    // MARK: - Máquina de estado

    @MainActor
    private func ingest(_ location: CLLocation) {
        lastLocation = location
        let now = Date.now
        let speed = max(0, location.speed)

        if speed > Self.movingThreshold {
            belowSince = nil
            if aboveSince == nil { aboveSince = now }
            if !isMoving, let since = aboveSince, now.timeIntervalSince(since) >= Self.promoteAfter {
                isMoving = true
                stateSince = since
            }
        } else {
            aboveSince = nil
            if belowSince == nil { belowSince = now }
            if isMoving, let since = belowSince, now.timeIntervalSince(since) >= Self.demoteAfter {
                isMoving = false
                stateSince = since
            }
        }

        // Lugar aproximado, no máximo a cada 60 s.
        //
        // `MKReverseGeocodingRequest` no lugar do `CLGeocoder`, depreciado no
        // iOS 26. De quebra, o callback dele já é `@MainActor`, o que resolve
        // o aviso de captura de `self` não-Sendable que virava erro no Swift 6.
        if now.timeIntervalSince(lastGeocode) > 60, !isGeocoding,
           let request = MKReverseGeocodingRequest(location: location) {
            lastGeocode = now
            isGeocoding = true
            Task { @MainActor [weak self] in
                defer { self?.isGeocoding = false }
                guard let item = try? await request.mapItems.first else { return }
                self?.placeHint = Self.shortHint(from: item)
            }
        }

        let level = UIDevice.current.batteryLevel
        let battery = level >= 0 ? Int((level * 100).rounded()) : 100

        let snapshot = OwnLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            speedMps: speed,
            heading: location.course >= 0 ? location.course : nil,
            batteryPct: battery,
            isMoving: isMoving,
            stateSince: stateSince,
            placeHint: placeHint
        )
        onSnapshot?(snapshot)
    }
}
