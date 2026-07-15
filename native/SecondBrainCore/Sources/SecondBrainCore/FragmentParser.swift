import Foundation

/// 조각 파일 하나(평문 마크다운)를 `InboxItem` 배열로 파싱한다. **읽기 전용, 원문 불변.**
/// 웹 v0(parser.js)를 재사용하지 않고 새로 작성(초안 §8). 여러 조각 파일을 하나의
/// 받은함으로 합치는 로직은 별도(합치기 엔진 — 수정 이벤트 범위 확정 후, §6 미결 #2).
public enum FragmentParser {

    private static let knownFields: Set<String> = ["type", "due", "resurface", "status"]

    /// - Parameters:
    ///   - text: 조각 파일 내용
    ///   - sourceFile: 출처 파일명(선택) — 각 항목에 기록
    public static func parse(_ text: String, sourceFile: String? = nil) -> [InboxItem] {
        // "- 2026-07-15 10:51 | voice | 원문"
        let itemRegex = try! NSRegularExpression(
            pattern: #"^-\s+(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})\s+\|\s+([^|]+?)\s+\|\s+(.*)$"#)
        // 들여쓴 "key: value"
        let fieldRegex = try! NSRegularExpression(
            pattern: #"^\s+([A-Za-z_]+):\s*(.*)$"#)

        var items: [InboxItem] = []
        var current: InboxItem?
        func flush() { if let c = current { items.append(c); current = nil } }

        for line in text.components(separatedBy: "\n") {
            let full = NSRange(line.startIndex..<line.endIndex, in: line)

            func cap(_ m: NSTextCheckingResult, _ i: Int) -> String {
                guard let r = Range(m.range(at: i), in: line) else { return "" }
                return String(line[r])
            }

            // 항목 헤더?
            if let m = itemRegex.firstMatch(in: line, range: full) {
                flush()
                current = InboxItem(
                    date: cap(m, 1),
                    time: cap(m, 2),
                    source: cap(m, 3).trimmingCharacters(in: .whitespaces).lowercased(),
                    raw: cap(m, 4).trimmingCharacters(in: .whitespaces),
                    sourceFile: sourceFile)
                continue
            }
            guard current != nil else { continue }  // 항목 밖의 줄(제목 # 등) 무시

            // 필드 줄?
            if let fm = fieldRegex.firstMatch(in: line, range: full) {
                let key = cap(fm, 1).lowercased()
                let val = cap(fm, 2).trimmingCharacters(in: .whitespaces)
                if knownFields.contains(key) {
                    switch key {
                    case "type": current?.type = val
                    case "due": current?.due = val
                    case "resurface": current?.resurface = val
                    case "status": current?.status = val
                    default: break
                    }
                    continue
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("? ") {                 // "? 질문"(§3)
                current?.question = String(trimmed.dropFirst(2))
            } else if trimmed.isEmpty {                  // 빈 줄 = 구분자(항목 유지)
                continue
            } else if line.first == " " || line.first == "\t" {  // 이어지는 들여쓴 원문/메모
                current?.notes.append(trimmed)
            }
        }
        flush()
        return items
    }
}
