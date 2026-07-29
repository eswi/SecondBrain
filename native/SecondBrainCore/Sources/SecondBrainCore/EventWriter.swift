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
            // device = 최초 수집 기기(성역), audio = 원본 음성 포인터(<uuid>.m4a), photo = 원본 사진 포인터(<uuid>.jpg).
            // 모두 create 블록에만 쓰고 이후 안 건드림(성역·불변). 블록의 `key: value`는 값에 공백 허용(파싱 안전).
            for k in ["type", "due", "resurface", "status", "device", "audio", "photo"] {
                if let v = f[k] { lines.append("  \(k): \(v)") }
            }
            return lines.joined(separator: "\n")
        }
        if f["deleted"] == "true" { return "@ \(e.hlc.serialized) | \(e.id) | delete" }
        if f["deleted"] == "false" { return "@ \(e.hlc.serialized) | \(e.id) | undelete" }
        // 편집 이벤트 직렬화 — **판단은 "안전하다고 확신할 때만 평문"**(위험 문자 나열이 아니라 뒤집힌 기본값).
        // 평문 `set k=v`가 무손실 왕복된다고 **모든** 키·값에 대해 확신할 때만 그 경로를 쓰고,
        // 하나라도 확신 못 하면 fields.v1 JSON 편집 블록으로 보낸다. 특정 필드(raw 등)만이 아니라 **값 자체**로 판단.
        // (JSON 경로는 파서가 개별 필드로 펼쳐 넘기므로 per-field LWW 그대로 — MergeEngine·merge-design 무변경.
        //  설계 `docs/native/photo-capture-design.md` §3. B2=펼침. 덩어리 LWW인 B1은 병합 퇴화라 금지.)
        if f.keys.allSatisfy(isPlaintextSafe) && f.values.allSatisfy(isPlaintextSafe) {
            // set k=v ... (키 정렬 → 결정적).
            let sets = f.keys.sorted().map { "\($0)=\(f[$0] ?? "")" }.joined(separator: " ")
            return "@ \(e.hlc.serialized) | \(e.id) | set \(sets)"
        }
        return "@ \(e.hlc.serialized) | \(e.id) | edit\n  fields.v1: \(compactJSON(f))"
    }

    /// 이 문자열이 평문 `set k=v` 경로로 **손실 없이 왕복된다고 확신**할 수 있는가.
    /// 평문 경로는 `@ hlc | id | set k=v k2=v2` **한 줄**이라, 다음이 있으면 깨진다:
    ///  - 앞뒤 공백: 파서가 `@`-분해 조각을 trim → 잘림
    ///  - 공백·탭: `set k=v` 조각이 공백으로 쪼개짐
    ///  - 줄바꿈(`\n`·`\r`): 줄 자체가 나뉨
    ///  - `|`: `@ ... | ... | verb` 줄이 파싱 때 '|'로 쪼개져 값이 **유실**됨
    ///    (레거시 id를 해시로 만든 것과 동종 함정 — `MergeEngineTests` "레거시 id `|`" 케이스 참조).
    /// 하나라도 있으면 "확신 불가" → 호출부가 JSON 편집 블록으로 보낸다.
    /// 빈 문자열은 `set k=`로 무손실 왕복(파서 `omittingEmptySubsequences:false`) → 안전으로 본다
    /// (미분류 되돌리기 `set type=`가 이 형태를 쓴다).
    static func isPlaintextSafe(_ s: String) -> Bool {
        if s != s.trimmingCharacters(in: .whitespacesAndNewlines) { return false }  // 앞뒤 공백
        for u in s.unicodeScalars where u == " " || u == "\t" || u == "\n" || u == "\r" || u == "|" {
            return false
        }
        return true
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
