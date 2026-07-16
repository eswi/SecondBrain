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

    /// 디렉터리에서 `inbox*.md`를 모두 찾아 이벤트로 파싱(앱 런타임의 시계 전진·병합 재료).
    public static func eventsInDirectory(_ dir: URL) -> (events: [Event], files: [String]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return ([], [])
        }
        let frags = entries
            .filter { $0.lastPathComponent.hasPrefix("inbox") && $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var events: [Event] = []
        var names: [String] = []
        for u in frags {
            if let t = try? String(contentsOf: u, encoding: .utf8) {
                events.append(contentsOf: EventLog.parse(t))
                names.append(u.lastPathComponent)
            }
        }
        return (events, names)
    }

    /// 디렉터리 → 병합 결과 + 파일명(편의).
    public static func loadDirectory(_ dir: URL) -> (result: MergeResult, files: [String]) {
        let (events, files) = eventsInDirectory(dir)
        return (MergeEngine.merge(events), files)
    }
}
