import Foundation

/// 쓰기 경로: 이벤트를 평문으로 직렬화하고 기기 조각 파일에 **append-only**로 붙인다(설계 §5·§6).
/// 파일은 절대 되쓰지 않는다 — 오직 끝에 한 줄/블록 추가.
public enum EventWriter {

    /// 이벤트 → 평문. create(헤더 블록) / delete / undelete / set(필드) 를 구분해 직렬화.
    /// EventLog.parse 와 왕복 가능해야 한다.
    public static func serialize(_ e: Event) -> String {
        let f = e.fields
        if let date = f["date"], let time = f["time"], let source = f["source"], let raw = f["raw"] {
            var lines = ["- \(date) \(time) | \(source) | \(raw)",
                         "  id: \(e.id)",
                         "  hlc: \(e.hlc.serialized)"]
            // device = 최초 수집 기기(성역), audio = 원본 음성 포인터(<uuid>.m4a, 성역·불변).
            // 둘 다 create 블록에만 쓰고 이후 안 건드림. 블록의 `key: value`는 값에 공백 허용(파싱 안전).
            for k in ["type", "due", "resurface", "status", "device", "audio"] {
                if let v = f[k] { lines.append("  \(k): \(v)") }
            }
            return lines.joined(separator: "\n")
        }
        if f["deleted"] == "true" { return "@ \(e.hlc.serialized) | \(e.id) | delete" }
        if f["deleted"] == "false" { return "@ \(e.hlc.serialized) | \(e.id) | undelete" }
        // 값에 공백·줄바꿈이 있으면 `set k=v` 경로가 못 담는다(공백으로 쪼개짐 — 예: 위치 설명·메모·question).
        // → fields.v1 JSON 편집 블록. create 블록처럼 들여쓴 한 줄에 JSON을 담아 줄 끝까지 읽게 한다(파싱 안전).
        // 병합: 파서가 이 JSON을 **개별 필드로 펼쳐** 넘기므로 per-field LWW 그대로 — MergeEngine·merge-design 무변경.
        // (설계 `docs/native/photo-capture-design.md` §3. B2=펼침. 덩어리 LWW인 B1은 병합 퇴화라 금지.)
        if f.values.contains(where: { $0.contains(" ") || $0.contains("\n") }) {
            return "@ \(e.hlc.serialized) | \(e.id) | edit\n  fields.v1: \(compactJSON(f))"
        }
        // set k=v ... (키 정렬 → 결정적). 값에 공백 없는 필드만 이 경로로 온다(raw는 create 블록).
        let sets = f.keys.sorted().map { "\($0)=\(f[$0] ?? "")" }.joined(separator: " ")
        return "@ \(e.hlc.serialized) | \(e.id) | set \(sets)"
    }

    /// 필드 딕셔너리 → 결정적 compact JSON(키 정렬). 한글은 UTF-8 그대로(= 평문 자산 유지, `\uXXXX` 아님).
    private static func compactJSON(_ f: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(
                withJSONObject: f, options: [.sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// 이벤트를 파일 끝에 append. 파일 없으면 생성. (append-only, 원자성은 append 자체로 충분.)
    public static func append(_ e: Event, to url: URL) throws {
        let line = serialize(e) + "\n"
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            if let d = line.data(using: .utf8) { try h.write(contentsOf: d) }
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
