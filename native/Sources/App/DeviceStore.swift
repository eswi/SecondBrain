import Foundation
import SecondBrainCore

/// 이 기기의 정체성·시계·조각 파일 위치. UserDefaults에 영속(앱 재시작해도 유지).
enum DeviceStore {
    private static let idKey = "sb_device_id"
    private static let clockKey = "sb_hlc_last"

    /// 기기 고유 id(최초 1회 발급 후 고정). 조각 파일명·HLC deviceId에 사용.
    static var deviceId: String {
        if let s = UserDefaults.standard.string(forKey: idKey) { return s }
        let s = "dev-" + UUID().uuidString.prefix(8).lowercased()
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

    static func documents() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 이 기기가 쓰는 조각 파일: inbox-<deviceId>.md
    static func fragmentURL(_ deviceId: String) -> URL {
        documents().appendingPathComponent("inbox-\(deviceId).md")
    }
}
