import Foundation

/// 최초 수집 기기 표시명 (edit-policy.md §4-1 불변 성역 · §7 레거시 역산).
///
/// 레거시 68개(닫힌 집합)는 create 이벤트의 `deviceId == "legacy"`라 실제 기기를 모른다.
/// §7 규칙으로 source에서 역산한다:
///   - 음성(`voice`) 수집 → **iPhone 16 Pro** (주 시험 기기)
///   - 그 외 방식 → **MacBook Pro**
/// 그 외 기기로 수집된 레거시 데이터는 없다(§7).
///
/// 네이티브 항목(실제 deviceId)은 `currentDeviceLabel`을 그대로 쓴다.
public enum CaptureDevice {
    public static let legacyMarker = "legacy"

    public static func label(source: String?, createdDeviceId: String,
                             currentDeviceLabel: String = "이 기기") -> String {
        if createdDeviceId == legacyMarker {
            return source == "voice" ? "iPhone 16 Pro" : "MacBook Pro"
        }
        return currentDeviceLabel
    }
}
