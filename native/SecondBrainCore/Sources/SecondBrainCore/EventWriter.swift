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
        // 최종 판단은 **문자 목록이 아니라 왕복 검증**이다: 평문 `set k=v` 후보를 만들어 직렬화→파싱했을 때
        // 원본 이벤트와 정확히 일치할 때만 그 경로를 쓰고, 아니면 fields.v1 JSON 편집 블록으로 보낸다.
        // (isPlaintextSafe는 대부분의 위험 값을 왕복 없이 즉시 걸러내는 **빠른 1차 거르기**일 뿐 — 최종 게이트 아님.
        //  JSON 경로는 파서가 개별 필드로 펼쳐 넘기므로 per-field LWW 그대로 — MergeEngine·merge-design 무변경.
        //  설계 `docs/native/photo-capture-design.md` §3. B2=펼침. 덩어리 LWW인 B1은 병합 퇴화라 금지.)
        if f.keys.allSatisfy(isPlaintextSafe) && f.values.allSatisfy(isPlaintextSafe) {
            let candidate = "@ \(e.hlc.serialized) | \(e.id) | set " +
                f.keys.sorted().map { "\($0)=\(f[$0] ?? "")" }.joined(separator: " ")   // 키 정렬 → 결정적
            if plaintextRoundtrips(candidate, to: e) { return candidate }
        }
        return "@ \(e.hlc.serialized) | \(e.id) | edit\n  fields.v1: \(compactJSON(f))"
    }

    /// 평문 `set` 후보가 **무손실 왕복**하는지 — 직렬화 판단의 **최종 게이트**(문자 목록이 아님).
    ///  ① Foundation의 줄 경계(`.newlines`: `\n`·`\r`·U+0085·U+000B·U+000C·U+2028·U+2029)로
    ///     쪼개지지 않아야 한다. 우리 파서는 `\n`만 나누지만, 다른/미래 리더(`enumerateLines`·`.newlines`)가
    ///     한 이벤트를 여러 줄로 보면 안 되므로 방어한다(웹 복사 텍스트로 U+2028 등이 실제로 들어올 수 있음).
    ///  ② 실제 파서로 되읽었을 때 원본 이벤트(id·hlc·fields)와 정확히 일치해야 한다
    ///     — `|`(줄이 '|'로 쪼개져 유실)·공백 분리·앞뒤 trim 손실을 여기서 잡는다.
    private static func plaintextRoundtrips(_ candidate: String, to e: Event) -> Bool {
        if candidate.components(separatedBy: .newlines).count != 1 { return false }   // ①
        return EventLog.parse(candidate) == [e]                                        // ②
    }

    /// 평문 `set k=v` 경로가 값을 못 담는 대표 문자를 즉시 걸러내는 **빠른 1차 거르기**(성능용).
    /// 최종 판단은 `plaintextRoundtrips`가 한다 — 여기서 놓친 값(예: U+2028)도 왕복 검증에서 걸러진다.
    /// 빈 문자열은 `set k=`로 무손실 왕복이라 통과시킨다(미분류 되돌리기 `set type=`가 이 형태).
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
        return escapeLineBreaks(s)
    }

    /// JSON 문자열 안에 **리터럴로 남은 줄 구분자**를 `\uXXXX` JSON 이스케이프로 바꾼다.
    /// `\n`·`\r`은 JSONSerialization이 이미 `\n`·`\r`로 이스케이프하지만, U+000B·U+000C·U+0085·
    /// U+2028·U+2029 등은 **리터럴로 남긴다.** fields.v1은 한 줄이어야 하는데 이것들이 리터럴이면
    /// 파서 정규식(`.`·`$`)·다른 리더(`.newlines`·`enumerateLines`)가 줄을 쪼개 값이 잘린다.
    /// 판단 기준은 문자 목록이 아니라 Foundation **`.newlines` 집합** — 유지보수할 목록이 없다.
    private static func escapeLineBreaks(_ s: String) -> String {
        let newlines = CharacterSet.newlines
        var out = ""
        out.reserveCapacity(s.unicodeScalars.count)
        for u in s.unicodeScalars {
            if newlines.contains(u) { out += String(format: "\\u%04x", u.value) }
            else { out.unicodeScalars.append(u) }
        }
        return out
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
