#if os(iOS)
import Foundation
import CoreLocation

/// 사진 EXIF에 박을 **촬영 위치**를 취득한다(사진 안에만 저장 · 그릇엔 안 박음 — 프라이버시,
/// 설계 `docs/native/photo-capture-design.md` §5). 카메라 열 때 시작해 프레이밍하는 동안 위치를 확보.
/// 권한 거부·신호 없음이면 `last == nil` → GPS 없이 저장(graceful).
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published private(set) var last: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 카메라 진입 시 호출 — 권한(when-in-use) 요청 + 위치 취득 시작.
    func begin() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break   // 거부/제한 → GPS 없이 진행
        }
    }

    func stop() { manager.stopUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.startUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last { last = l }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // graceful — 위치 없이 진행. (실내·신호 약함 등)
    }
}
#endif
