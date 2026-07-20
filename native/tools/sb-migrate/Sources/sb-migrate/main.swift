import Foundation
import SecondBrainCore

// 레거시 → UUID 마이그레이션 도구 (설계: docs/native/legacy-uuid-migration.md).
//   --dry-run <folder>               : 파일 무변경. 사전점검 + before==after 시뮬 + D1 리포트.
//   --apply <folder> --out <outdir>  : 원본 무변경. 새 디렉터리에 마이그레이션 산출물 생성 후 재검증.
// 해시·병합·검증은 앱과 '동일한' SecondBrainCore 코드로 수행(재구현 divergence 방지).

func die(_ m: String) -> Never {
    FileHandle.standardError.write(("ERROR: " + m + "\n").data(using: .utf8)!); exit(1)
}
func eprint(_ m: String) { FileHandle.standardError.write((m + "\n").data(using: .utf8)!) }
func read(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }

func ckey(_ f: [String: String]) -> String {
    "\(f["date"] ?? "")\u{1}\(f["time"] ?? "")\u{1}\(f["source"] ?? "")\u{1}\(f["raw"] ?? "")"
}
func rawOf(_ key: String) -> String { key.split(separator: "\u{1}", omittingEmptySubsequences: false).last.map(String.init) ?? "" }
func inferredDevice(_ source: String?) -> String { source == "voice" ? "iPhone 16 Pro" : "MacBook Pro" }
func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }

// 비교 대상: 헤더(성역)·device를 뺀 '모든' 콘텐츠 필드 + 제어 2개. → 어떤 필드 누락도 잡힌다.
func contentState(_ it: ResolvedItem) -> [String: String] {
    var f = it.fields
    for k in ["date", "time", "source", "raw", "device"] { f[k] = nil }
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

struct Loaded {
    let legacyURL: URL
    let fragmentURLs: [URL]
    let legacyEvents: [Event]
    let fragmentEvents: [Event]
    var before: [Event] { legacyEvents + fragmentEvents }
}
func loadFolder(_ folder: URL) -> Loaded {
    let fm = FileManager.default
    let legacyURL = folder.appendingPathComponent("inbox.md")
    guard fm.fileExists(atPath: legacyURL.path) else { die("inbox.md 없음: \(legacyURL.path)") }
    let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    let frags = entries.filter { $0.pathExtension == "md" && $0.lastPathComponent.hasPrefix("inbox-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let legacy = EventLog.parse(read(legacyURL))
    var fragEv: [Event] = []
    for u in frags { fragEv.append(contentsOf: EventLog.parse(read(u))) }
    return Loaded(legacyURL: legacyURL, fragmentURLs: frags, legacyEvents: legacy, fragmentEvents: fragEv)
}

// 해시 → UUID 맵 (레거시 create id만).
func buildMap(_ legacyEvents: [Event]) -> [String: String] {
    let hashes = Set(legacyEvents.filter { $0.id.hasPrefix("legacy:") && $0.fields["raw"] != nil }.map(\.id))
    var m: [String: String] = [:]
    for h in hashes.sorted() { m[h] = UUID().uuidString }
    return m
}

// ── 검증: before(원본 이벤트) vs after(시뮬 또는 재파싱 이벤트) ──
func compare(before: [Event], after: [Event]) -> (pass: Bool, lines: [String]) {
    let mB = MergeEngine.merge(before), mA = MergeEngine.merge(after)
    let gB = groupByKey(mB), gA = groupByKey(mA)
    let cB = eventCountByKey(before, mB), cA = eventCountByKey(after, mA)
    var lines: [String] = []; var pass = true
    func check(_ ok: Bool, _ label: String, _ d: String = "") {
        lines.append("  \(ok ? "✅" : "❌") \(label)\(d.isEmpty ? "" : " — \(d)")"); if !ok { pass = false }
    }
    let nB = mB.live.count + mB.deleted.count, nA = mA.live.count + mA.deleted.count
    check(nB == nA, "① 항목 수 불변", "before \(nB) / after \(nA)")

    let onlyB = Set(gB.keys).subtracting(gA.keys), onlyA = Set(gA.keys).subtracting(gB.keys)
    let multi = gB.filter { $0.value.count > 1 }.count + gA.filter { $0.value.count > 1 }.count
    check(onlyB.isEmpty && onlyA.isEmpty && multi == 0, "② 내용키 전단사(고아·유령·중복 0)",
          "onlyBefore \(onlyB.count) / onlyAfter \(onlyA.count) / dup \(multi)")

    var stateBad: [String] = [], histBad: [String] = []
    for (k, bs) in gB {
        guard let a = gA[k]?.first, let b = bs.first else { continue }
        if contentState(b) != contentState(a) { stateBad.append("\(rawOf(k).prefix(40)) | \(contentState(b)) → \(contentState(a))") }
        if (cB[k] ?? -1) != (cA[k] ?? -2) { histBad.append("\(rawOf(k).prefix(40)) | \(cB[k] ?? -1)→\(cA[k] ?? -2)") }
    }
    check(stateBad.isEmpty, "③ 상태 동일(모든 콘텐츠 필드 + confirmed + deleted)")
    for m in stateBad.prefix(10) { lines.append("       · \(m)") }

    var idBad = 0
    for (k, av) in gA {
        guard let a = av.first else { continue }
        let wasLegacy = gB[k]?.first?.id.hasPrefix("legacy:") ?? false
        if wasLegacy { if !isUUID(a.id) { idBad += 1 } } else if a.id != gB[k]?.first?.id { idBad += 1 }
    }
    check(idBad == 0, "④ id: 레거시→유효 UUID, native 불변", "위반 \(idBad)")

    var devBad = 0
    for (k, av) in gA {
        guard let a = av.first, (gB[k]?.first?.id.hasPrefix("legacy:") ?? false) else { continue }
        if a.fields["device"] != inferredDevice(a.fields["source"]) { devBad += 1 }
    }
    check(devBad == 0, "⑤ device 동결 = §7 역산", "위반 \(devBad)")
    check(histBad.isEmpty, "⑥ 이력(이벤트 수) 내용키별 동일")
    for m in histBad.prefix(10) { lines.append("       · \(m)") }
    return (pass, lines)
}

// ── 산출물 텍스트 ──
func migratedInboxText(_ legacyEvents: [Event], _ map: [String: String]) -> String {
    var blocks: [String] = []
    for e in legacyEvents where e.fields["raw"] != nil {     // 레거시 create
        guard let uuid = map[e.id] else { continue }
        var f = e.fields
        if f["device"] == nil { f["device"] = inferredDevice(f["source"]) }
        blocks.append(EventWriter.serialize(Event(id: uuid, hlc: e.hlc, fields: f)))
    }
    return blocks.joined(separator: "\n") + "\n"
}
func migratedFragmentText(_ original: String, _ map: [String: String]) -> String {
    original.components(separatedBy: "\n").map { line -> String in
        guard line.hasPrefix("@") else { return line }
        let parts = line.components(separatedBy: " | ")
        guard parts.count >= 3, let uuid = map[parts[1].trimmingCharacters(in: .whitespaces)] else { return line }
        var p = parts; p[1] = uuid
        return p.joined(separator: " | ")
    }.joined(separator: "\n")
}

// ── D1/사전점검 (dry-run·apply 공통) ──
func precheckLines(_ L: Loaded) -> (lines: [String], orphans: Set<String>) {
    let creates = L.legacyEvents.filter { $0.id.hasPrefix("legacy:") && $0.fields["raw"] != nil }
    let hashes = Set(creates.map(\.id)), contents = Set(creates.map { ckey($0.fields) })
    var groups: [String: Int] = [:]; for e in creates { groups[ckey(e.fields), default: 0] += 1 }
    let dups = groups.filter { $0.value > 1 }
    let refd = Set(L.fragmentEvents.map(\.id).filter { $0.hasPrefix("legacy:") })
    let orphans = refd.subtracting(hashes)
    var out: [String] = []
    out.append("[D1] 레거시 줄 \(creates.count) · 고유내용 \(contents.count) · 고유해시 \(hashes.count)")
    if hashes.count < contents.count { out.append("  ⚠️ 해시 충돌!") }
    else if contents.count < creates.count { out.append("  → 완전중복 \(creates.count - contents.count)개(병합서 이미 합쳐짐). 실제=\(contents.count)") }
    else { out.append("  → 중복·충돌 없음. 실제 레거시 항목 = \(contents.count)") }
    if !dups.isEmpty { for (k, n) in dups.sorted(by: { $0.value > $1.value }) { out.append("    · \(n)회: \(rawOf(k).prefix(50))") } }
    out.append("[사전점검] 고아 참조: " + (orphans.isEmpty ? "✅ 없음" : "❌ \(orphans.count)개"))
    for o in orphans.sorted() { out.append("    · \(o)") }
    let voice = creates.filter { $0.fields["source"] == "voice" }.count
    out.append("[분포] voice→iPhone 16 Pro \(voice) · 그 외→MacBook Pro \(creates.count - voice)")
    return (out, orphans)
}

// ── 모드 ──
func runDryRun(_ folder: URL) {
    let L = loadFolder(folder)
    let map = buildMap(L.legacyEvents)
    let after = L.before.map { e -> Event in
        guard e.id.hasPrefix("legacy:"), let uuid = map[e.id] else { return e }
        var f = e.fields; if f["raw"] != nil, f["device"] == nil { f["device"] = inferredDevice(f["source"]) }
        return Event(id: uuid, hlc: e.hlc, fields: f)
    }
    let pc = precheckLines(L)
    let (pass, vlines) = compare(before: L.before, after: after)
    var out = ["═══ DRY-RUN (파일 무변경) ═══", "폴더: \(folder.path)", ""]
    out += pc.lines + [""] + ["[검증] before == after"] + vlines
    out.append("")
    out.append(pass && pc.orphans.isEmpty ? "결과: ✅ 통과 — apply 가능" : "결과: ❌ 실패")
    print(out.joined(separator: "\n"))
}

func runApply(_ folder: URL, _ outdir: URL) {
    let fm = FileManager.default
    let L = loadFolder(folder)
    let pc = precheckLines(L)
    if !pc.orphans.isEmpty { print(pc.lines.joined(separator: "\n")); die("고아 참조 있음 — apply 중단") }
    let map = buildMap(L.legacyEvents)

    // 산출물 디렉터리(비어 있어야 안전)
    if fm.fileExists(atPath: outdir.path) { die("out 디렉터리가 이미 존재: \(outdir.path) (새 경로 지정)") }
    try? fm.createDirectory(at: outdir, withIntermediateDirectories: true)

    // 1) inbox.md (마이그레이션)
    try? migratedInboxText(L.legacyEvents, map).write(to: outdir.appendingPathComponent("inbox.md"), atomically: true, encoding: .utf8)
    // 2) 조각들 (legacy 참조만 UUID로 치환, 나머지 그대로)
    for u in L.fragmentURLs {
        let t = migratedFragmentText(read(u), map)
        try? t.write(to: outdir.appendingPathComponent(u.lastPathComponent), atomically: true, encoding: .utf8)
    }
    // 3) idmap 감사 파일
    var mapLines = ["# legacy hash → UUID (감사용)"]
    let creates = L.legacyEvents.filter { $0.id.hasPrefix("legacy:") && $0.fields["raw"] != nil }
    for e in creates { mapLines.append("\(e.id)  ->  \(map[e.id] ?? "?")  |  \((e.fields["raw"] ?? "").prefix(50))") }
    try? mapLines.joined(separator: "\n").write(to: outdir.appendingPathComponent("idmap.txt"), atomically: true, encoding: .utf8)

    // 4) 산출물을 '다시 파싱'해서 재검증 (round-trip 포함)
    let after = loadFolder(outdir).before
    let (pass, vlines) = compare(before: L.before, after: after)

    var out = ["═══ APPLY (원본 무변경 · 산출물=새 디렉터리) ═══",
               "원본: \(folder.path)", "산출물: \(outdir.path)", ""]
    out += pc.lines + [""]
    out.append("[재검증] 원본 before == 산출물 재파싱 after")
    out += vlines
    out.append("")
    out.append(pass ? "결과: ✅ 산출물 검증 통과 — 위대표 검토 후 ④원본 교체 가능"
                    : "결과: ❌ 산출물 검증 실패 — 교체 금지")
    let report = out.joined(separator: "\n")
    print(report)
    try? report.write(to: outdir.appendingPathComponent("apply-report.txt"), atomically: true, encoding: .utf8)
}

// 앱과 동일한 필터로 대시보드 수치 재현(InboxModel.resolve 로직 그대로).
func runStats(_ folder: URL) {
    let L = loadFolder(folder)
    let r = MergeEngine.merge(L.before)
    let all = r.live.count + r.deleted.count
    let discardLive = r.live.filter { $0.type == "discard" }.count
    let active = r.live.filter { $0.type != "discard" }
    let done = active.filter { $0.status == "done" }.count
    let liveNonDone = active.filter { $0.status != "done" }
    let princ = liveNonDone.filter { $0.type == "principle" }.count
    let conf = (r.live + r.deleted).filter(\.confirmed).count
    let princAll = (r.live + r.deleted).filter { $0.type == "principle" }.count
    print("""
    [\(folder.lastPathComponent)]
      총 distinct 항목(역대 전체)        : \(all)
        ├ 삭제 tombstone (r.deleted)     : \(r.deleted.count)
        ├ discard(삭제취급)              : \(discardLive)
        ├ 완료 done                      : \(done)
        └ liveNonDone (=대시보드 '총 기억'): \(liveNonDone.count)
            └ 그중 원칙(principle)        : \(princ)
      보관된 기억(삭제+discard+완료) 합   : \(r.deleted.count + discardLive + done)
      confirmed(보관 포함 전체)          : \(conf)   · principle(보관 포함 전체): \(princAll)
    """)
}

// ── entry ──
let a = CommandLine.arguments
if a.count >= 3, a[1] == "--dry-run" {
    runDryRun(URL(fileURLWithPath: a[2], isDirectory: true))
} else if a.count >= 5, a[1] == "--apply", a[3] == "--out" {
    runApply(URL(fileURLWithPath: a[2], isDirectory: true), URL(fileURLWithPath: a[4], isDirectory: true))
} else if a.count >= 3, a[1] == "--stats" {
    runStats(URL(fileURLWithPath: a[2], isDirectory: true))
} else {
    die("usage:\n  sb-migrate --dry-run <folder>\n  sb-migrate --apply <folder> --out <outdir>\n  sb-migrate --stats <folder>")
}
