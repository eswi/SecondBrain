import Foundation

/// 이벤트 로그 파일(평문)을 이벤트 배열로 파싱한다. **관용적** — 깨진/알 수 없는 줄은 스킵(설계 §6).
/// 포맷: create=항목 블록(+ id/hlc), 변이=`@ <hlc> | <id> | verb`. id/hlc 없는 create 블록은 레거시로 편입.
public enum EventLog {
    public static func parse(_ text: String) -> [Event] {
        let itemRe = try! NSRegularExpression(
            pattern: #"^-\s+(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})\s+\|\s+([^|]+?)\s+\|\s+(.*)$"#)
        // key에 '.'·숫자 허용(예: `fields.v1`). 기존 키(id/type/…)는 그대로 매치 — charset 확장은 무해.
        let fieldRe = try! NSRegularExpression(pattern: #"^\s+([A-Za-z0-9_.]+):\s*(.*)$"#)
        func cap(_ m: NSTextCheckingResult, _ idx: Int, _ s: String) -> String {
            guard let r = Range(m.range(at: idx), in: s) else { return "" }
            return String(s[r])
        }
        func matches(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
            re.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s))
        }

        var events: [Event] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var legacyIndex = 0

        while i < lines.count {
            let line = lines[i]

            // 1) create 블록
            if let m = matches(itemRe, line) {
                let date = cap(m, 1, line), time = cap(m, 2, line)
                let source = cap(m, 3, line).trimmingCharacters(in: .whitespaces).lowercased()
                let raw = cap(m, 4, line).trimmingCharacters(in: .whitespaces)
                var fields: [String: String] = [:]
                var id: String?
                var hlc: HLC?
                var j = i + 1
                while j < lines.count {
                    let l2 = lines[j]
                    let t2 = l2.trimmingCharacters(in: .whitespaces)
                    if matches(itemRe, l2) != nil { break }
                    if t2.isEmpty { break }
                    if l2.hasPrefix("@") { break }
                    if !(l2.first == " " || l2.first == "\t") { break }
                    if let fm = matches(fieldRe, l2) {
                        let k = cap(fm, 1, l2).lowercased()
                        let v = cap(fm, 2, l2).trimmingCharacters(in: .whitespaces)
                        if k == "id" { id = v }
                        else if k == "hlc" { hlc = HLC(serialized: v) }
                        else { fields[k] = v }
                    }
                    j += 1
                }
                fields["date"] = date; fields["time"] = time; fields["source"] = source; fields["raw"] = raw
                if let id = id, let hlc = hlc {
                    events.append(Event(id: id, hlc: hlc, fields: fields))
                } else {
                    // id/hlc 없음 → 레거시 create(최하 우선순위). 토큰 안전 해시 id(변이 이벤트 왕복 위해).
                    let legacyId = Event.legacyID(date: date, time: time, source: source, raw: raw)
                    events.append(Event(id: legacyId,
                                        hlc: HLC(wallMillis: 0, counter: legacyIndex, deviceId: "legacy"),
                                        fields: fields))
                    legacyIndex += 1
                }
                i = j
                continue
            }

            // 2) 변이 이벤트 줄: @ <hlc> | <id> | verb...
            if line.hasPrefix("@") {
                let parts = line.dropFirst().components(separatedBy: "|").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count >= 3, let hlc = HLC(serialized: parts[0]) {
                    let id = parts[1]
                    let verb = parts[2]
                    if verb == "delete" {
                        events.append(.delete(id: id, hlc: hlc))
                    } else if verb == "undelete" {
                        events.append(.undelete(id: id, hlc: hlc))
                    } else if verb == "edit" {
                        // 블록형 편집: 다음 들여쓴 줄들의 `fields.v1: <JSON>`을 읽어 **개별 필드로 펼친다**.
                        // (공백 있는 값을 담는 경로 — set k=v가 못 함. 엔진엔 평평한 [String:String]로 전달 →
                        //  per-field LWW 그대로. 설계 `photo-capture-design.md` §3.)
                        var fields: [String: String] = [:]
                        var j = i + 1
                        while j < lines.count {
                            let l2 = lines[j]
                            if l2.trimmingCharacters(in: .whitespaces).isEmpty { break }
                            if l2.hasPrefix("@") { break }
                            if !(l2.first == " " || l2.first == "\t") { break }
                            if let fm = matches(fieldRe, l2) {
                                let k = cap(fm, 1, l2).lowercased()
                                let v = cap(fm, 2, l2)
                                if k == "fields.v1" || k == "fieldsv1" {
                                    let js = v.trimmingCharacters(in: .whitespaces)
                                    if let d = js.data(using: .utf8),
                                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                                        for (kk, vv) in obj {
                                            fields[kk] = (vv as? String) ?? String(describing: vv)
                                        }
                                    }
                                } else {
                                    fields[k] = v.trimmingCharacters(in: .whitespaces)
                                }
                            }
                            j += 1
                        }
                        if !fields.isEmpty { events.append(Event(id: id, hlc: hlc, fields: fields)) }
                        i = j
                        continue
                    } else if verb.hasPrefix("set ") {
                        var f: [String: String] = [:]
                        for a in verb.dropFirst(4).split(separator: " ") {
                            // 빈 값도 유지(`type=` → 미분류로 되돌리기). omittingEmpty=false로 뒤쪽 빈 조각 보존.
                            let kv = a.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                            if kv.count == 2 { f[String(kv[0])] = String(kv[1]) }
                        }
                        if !f.isEmpty { events.append(Event(id: id, hlc: hlc, fields: f)) }
                    }
                    // 알 수 없는 verb → 스킵
                }
                i += 1
                continue
            }

            // 3) 그 외(제목 #, 깨진 줄 등) → 스킵
            i += 1
        }
        return events
    }
}
