import Foundation
import SecondBrainCore

// 레거시 → UUID 마이그레이션 도구 (설계: docs/native/legacy-uuid-migration.md).
// 현재 구현: --dry-run (파일 무변경, 사전점검 + before==after 시뮬 + D1 규명 리포트).
// apply(--out 새 디렉터리)는 dry-run 검토 후 별도로 추가한다.

func die(_ m: String) -> Never {
    FileHandle.standardError.write(("ERROR: " + m + "\n").data(using: .utf8)!)
    exit(1)
}

func read(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }

// 내용키 (해시 원재료와 동일: date time|source|raw)
func ckey(_ f: [String: String]) -> String {
    "\(f["date"] ?? "")\u{1}\(f["time"] ?? "")\u{1}\(f["source"] ?? "")\u{1}\(f["raw"] ?? "")"
}
// §7 기기 역산(동결)
func inferredDevice(_ source: String?) -> String { source == "voice" ? "iPhone 16 Pro" : "MacBook Pro" }
func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }
func rawOf(_ key: String) -> String { key.split(separator: "\u{1}").last.map(String.init) ?? "" }

// 비교 대상 상태 필드(device·성역키 제외)
func stateFields(_ it: ResolvedItem) -> [String: String] {
    var f: [String: String] = [:]
    for k in ["type", "due", "resurface", "status", "order"] { if let v = it.fields[k] { f[k] = v } }
    f["·deleted"] = it.deleted ? "1" : "0"
    f["·confirmed"] = it.confirmed ? "1" : "0"
    return f
}
func groupByKey(_ r: MergeResult) -> [String: [ResolvedItem]] {
    var d: [String: [ResolvedItem]] = [:]
    for it in (r.live + r.deleted) { d[ckey(it.fields), default: []].append(it) }
    return d
}
func eventCountByKey(_ evs: [Event], _ m: MergeResult) -> [String: Int] {
    var byId: [String: Int] = [:]
    for e in evs { byId[e.id, default: 0] += 1 }
    var byKey: [String: Int] = [:]
    for it in (m.live + m.deleted) { byKey[ckey(it.fields)] = byId[it.id] ?? 0 }
    return byKey
}

func dryRun(folder: URL) {
    let fm = FileManager.default
    let legacyURL = folder.appendingPathComponent("inbox.md")
    guard fm.fileExists(atPath: legacyURL.path) else { die("inbox.md 없음: \(legacyURL.path)") }
    let allEntries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    let fragmentURLs = allEntries
        .filter { $0.pathExtension == "md" && $0.lastPathComponent.hasPrefix("inbox-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    // 파싱 (앱과 동일: 각 파일 parse 후 concat)
    let legacyEvents = EventLog.parse(read(legacyURL))
    var fragmentEvents: [Event] = []
    for u in fragmentURLs { fragmentEvents.append(contentsOf: EventLog.parse(read(u))) }
    let before = legacyEvents + fragmentEvents

    // 레거시 create 분석 (D1 + 사전점검)
    let legacyCreates = legacyEvents.filter { $0.id.hasPrefix("legacy:") && $0.fields["raw"] != nil }
    let legacyLineCount = legacyCreates.count
    let distinctHashes = Set(legacyCreates.map(\.id))
    let distinctContent = Set(legacyCreates.map { ckey($0.fields) })
    var contentGroups: [String: [Event]] = [:]
    for e in legacyCreates { contentGroups[ckey(e.fields), default: []].append(e) }
    let dupGroups = contentGroups.filter { $0.value.count > 1 }
    let referencedLegacy = Set(fragmentEvents.map(\.id).filter { $0.hasPrefix("legacy:") })
    let orphans = referencedLegacy.subtracting(distinctHashes)

    // 해시 → UUID 맵
    var idMap: [String: String] = [:]
    for h in distinctHashes.sorted() { idMap[h] = UUID().uuidString }

    // after 시뮬 (id 리네임 + create에 device 동결)
    let after: [Event] = before.map { e in
        guard e.id.hasPrefix("legacy:"), let uuid = idMap[e.id] else { return e }
        var f = e.fields
        if f["raw"] != nil, f["device"] == nil { f["device"] = inferredDevice(f["source"]) }
        return Event(id: uuid, hlc: e.hlc, fields: f)
    }

    let mBefore = MergeEngine.merge(before)
    let mAfter = MergeEngine.merge(after)
    let gBefore = groupByKey(mBefore)
    let gAfter = groupByKey(mAfter)
    let cntBefore = eventCountByKey(before, mBefore)
    let cntAfter = eventCountByKey(after, mAfter)

    // ==================== 리포트 ====================
    var out: [String] = []
    func p(_ s: String = "") { out.append(s) }

    p("═══════════════════════════════════════════════════")
    p(" 레거시 → UUID 마이그레이션 · DRY-RUN 리포트 (파일 무변경)")
    p(" 폴더: \(folder.path)")
    p("═══════════════════════════════════════════════════")
    p()
    p("[파일]")
    p("  inbox.md (레거시)")
    for u in fragmentURLs { p("  \(u.lastPathComponent) (조각)") }
    p()

    // D1: 68 vs 71 규명
    p("[D1] 레거시 닫힌 집합 규명")
    p("  inbox.md 레거시 줄(create)      : \(legacyLineCount)")
    p("  고유 내용(date·time·source·raw) : \(distinctContent.count)")
    p("  고유 해시 id                    : \(distinctHashes.count)")
    if distinctHashes.count < distinctContent.count {
        p("  ⚠️ 해시 충돌! 서로 다른 내용이 같은 해시 → 위험.")
    } else if distinctContent.count < legacyLineCount {
        p("  → 완전 중복 줄 \(legacyLineCount - distinctContent.count)개(같은 내용=같은 해시 → 병합에서 이미 1개로 합쳐짐).")
        p("     실제 항목 수 = \(distinctContent.count). '68'과의 차이는 이 중복 때문일 수 있음.")
    } else {
        p("  → 중복·충돌 없음. 실제 레거시 항목 = \(distinctContent.count)개.")
    }
    if !dupGroups.isEmpty {
        p("  중복 줄 그룹:")
        for (k, evs) in dupGroups.sorted(by: { $0.value.count > $1.value.count }) {
            p("    · \(evs.count)회: \(rawOf(k).prefix(60))")
        }
    }
    p()

    // 사전점검 #7
    p("[사전점검] 고아 참조(대응 create 없는 legacy: 참조)")
    if orphans.isEmpty {
        p("  ✅ 없음 — 조각의 모든 legacy 참조가 inbox.md 항목에 대응.")
    } else {
        p("  ❌ \(orphans.count)개 — apply 전 반드시 해결:")
        for o in orphans.sorted() { p("    · \(o)") }
    }
    p()

    // 분포(참고)
    let voice = legacyCreates.filter { $0.fields["source"] == "voice" }.count
    p("[분포] 레거시 기기 역산(§7): voice→iPhone 16 Pro \(voice) · 그 외→MacBook Pro \(legacyLineCount - voice)")
    let confBefore = (mBefore.live + mBefore.deleted).filter(\.confirmed).count
    let princBefore = (mBefore.live + mBefore.deleted).filter { $0.type == "principle" }.count
    p("[스냅샷·before] 기억하기=\(confBefore) · 원칙=\(princBefore) · 삭제(숨김)=\(mBefore.deleted.count) · 전체=\(mBefore.live.count + mBefore.deleted.count)")
    p()

    // ==================== 검증 (before == after) ====================
    p("[검증] 같은 MergeEngine으로 before vs after")
    var pass = true
    func check(_ ok: Bool, _ label: String, _ detail: String = "") {
        p("  \(ok ? "✅" : "❌") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { pass = false }
    }

    let nBefore = mBefore.live.count + mBefore.deleted.count
    let nAfter = mAfter.live.count + mAfter.deleted.count
    check(nBefore == nAfter, "① 항목 수 불변", "before \(nBefore) / after \(nAfter)")

    let keysBefore = Set(gBefore.keys), keysAfter = Set(gAfter.keys)
    let onlyBefore = keysBefore.subtracting(keysAfter)
    let onlyAfter = keysAfter.subtracting(keysBefore)
    let multi = gBefore.filter { $0.value.count > 1 }.count + gAfter.filter { $0.value.count > 1 }.count
    check(onlyBefore.isEmpty && onlyAfter.isEmpty && multi == 0,
          "② 내용키 전단사(고아·유령·중복 0)",
          "onlyBefore \(onlyBefore.count) / onlyAfter \(onlyAfter.count) / dup \(multi)")

    var stateMismatch: [String] = []
    var histMismatch: [String] = []
    for (k, bs) in gBefore {
        guard let asum = gAfter[k]?.first, let b = bs.first else { continue }
        if stateFields(b) != stateFields(asum) {
            stateMismatch.append("\(rawOf(k).prefix(40)) | \(stateFields(b)) → \(stateFields(asum))")
        }
        if (cntBefore[k] ?? -1) != (cntAfter[k] ?? -2) {
            histMismatch.append("\(rawOf(k).prefix(40)) | \(cntBefore[k] ?? -1) → \(cntAfter[k] ?? -2)")
        }
    }
    check(stateMismatch.isEmpty, "③ 상태 동일(type·due·resurface·status·order·confirmed·deleted)")
    for m in stateMismatch.prefix(10) { p("       · \(m)") }

    var idFail = 0
    for (k, asum) in gAfter {
        guard let a = asum.first else { continue }
        let wasLegacy = gBefore[k]?.first?.id.hasPrefix("legacy:") ?? false
        if wasLegacy { if !isUUID(a.id) { idFail += 1 } }
        else if a.id != gBefore[k]?.first?.id { idFail += 1 }
    }
    check(idFail == 0, "④ id: 레거시→유효 UUID, native 불변", "위반 \(idFail)")

    var devFail = 0
    for (k, asum) in gAfter {
        guard let a = asum.first, (gBefore[k]?.first?.id.hasPrefix("legacy:") ?? false) else { continue }
        if a.fields["device"] != inferredDevice(a.fields["source"]) { devFail += 1 }
    }
    check(devFail == 0, "⑤ device 동결 = §7 역산", "위반 \(devFail)")

    check(histMismatch.isEmpty, "⑥ 이력(이벤트 수) 내용키별 동일")
    for m in histMismatch.prefix(10) { p("       · \(m)") }

    p()
    p("═══════════════════════════════════════════════════")
    p(pass && orphans.isEmpty ? " 결과: ✅ 모든 검증 통과 — apply 진행 가능(위대표 검토 후)"
                              : " 결과: ❌ 실패 항목 있음 — apply 금지")
    p("═══════════════════════════════════════════════════")

    let report = out.joined(separator: "\n")
    print(report)
    let reportURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("sb-migration-dryrun.txt")
    try? report.write(to: reportURL, atomically: true, encoding: .utf8)
    FileHandle.standardError.write(("\n[리포트 저장] \(reportURL.path)\n").data(using: .utf8)!)
}

// ---- entry ----
let argv = CommandLine.arguments
guard argv.count >= 3, argv[1] == "--dry-run" else { die("usage: sb-migrate --dry-run <folder>") }
dryRun(folder: URL(fileURLWithPath: argv[2], isDirectory: true))
