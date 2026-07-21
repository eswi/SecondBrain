import Foundation

/// **임시** 탭 튐 진단 — 탭/scenePhase 변화를 UserDefaults에 남긴다(프로세스가 죽었다 복원돼도 유지).
/// 화면 오버레이(RootView.tabDebugOverlay)로 실사용 조건에서 눈으로 본다. 실험 후 제거(git restore + 파일 삭제).
enum TabDebug {
    private static let key = "tabDebugLog"
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func log(_ s: String) {
        var arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        arr.append("\(fmt.string(from: Date())) \(s)")
        if arr.count > 40 { arr.removeFirst(arr.count - 40) }
        UserDefaults.standard.set(arr, forKey: key)
    }

    static var entries: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
