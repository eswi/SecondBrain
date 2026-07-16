import Foundation

/// 읽기 경로: 여러 기기별 조각 파일(`inbox*.md`)을 파싱·병합해 받은함 상태를 만든다.
/// 조각은 네이티브 이벤트 로그든 레거시 v0 블록이든 `EventLog.parse`가 함께 처리(설계 §1·§6).
public enum InboxStore {

    /// 조각 파일들의 '텍스트'를 병합(테스트·순수 로직용).
    public static func merge(fragmentTexts: [String]) -> MergeResult {
        var all: [Event] = []
        for t in fragmentTexts { all.append(contentsOf: EventLog.parse(t)) }
        return MergeEngine.merge(all)
    }

    /// 디렉터리에서 `inbox*.md`를 모두 찾아 병합(앱 런타임). 못 읽으면 빈 결과.
    /// - Returns: 병합 결과 + 실제로 읽은 파일명들.
    public static func loadDirectory(_ dir: URL) -> (result: MergeResult, files: [String]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return (MergeEngine.merge([]), [])
        }
        let frags = entries
            .filter { $0.lastPathComponent.hasPrefix("inbox") && $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var texts: [String] = []
        var names: [String] = []
        for u in frags {
            if let t = try? String(contentsOf: u, encoding: .utf8) {
                texts.append(t)
                names.append(u.lastPathComponent)
            }
        }
        return (merge(fragmentTexts: texts), names)
    }
}
