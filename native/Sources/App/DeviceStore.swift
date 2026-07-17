import Foundation
import SecondBrainCore

/// 이 기기의 정체성·시계. UserDefaults에 영속(앱 재시작해도 유지).
/// 조각 파일 위치는 사용자가 고른 iCloud 폴더(`FragmentFolder`)가 담당한다.
enum DeviceStore {
    private static let idKey = "sb_device_id"
    private static let clockKey = "sb_hlc_last"

    /// 기기 고유 id(최초 1회 발급 후 고정). 조각 파일명 `inbox-<id>.md`·HLC deviceId에 사용.
    /// 열린 폴더에서 사람이 읽기 쉽도록 플랫폼 접두어를 붙인다(iphone-/mac-).
    static var deviceId: String {
        if let s = UserDefaults.standard.string(forKey: idKey) { return s }
        #if os(iOS)
        let prefix = "iphone"
        #elseif os(macOS)
        let prefix = "mac"
        #else
        let prefix = "dev"
        #endif
        let s = "\(prefix)-" + UUID().uuidString.prefix(4).lowercased()
        UserDefaults.standard.set(s, forKey: idKey)
        return s
    }

    static func loadLastHLC(_ deviceId: String) -> HLC {
        if let s = UserDefaults.standard.string(forKey: clockKey), let h = HLC(serialized: s) { return h }
        return HLC(wallMillis: 0, counter: 0, deviceId: deviceId)
    }

    static func saveLastHLC(_ h: HLC) {
        UserDefaults.standard.set(h.serialized, forKey: clockKey)
    }
}
