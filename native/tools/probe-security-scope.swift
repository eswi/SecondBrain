// probe-security-scope.swift — 샌드박스 **없는** 프로세스에서 보안 스코프가 어떻게 되는지 잰다.
//
// 왜 있나: 설계 `media-icloud-design.md` §2-A가 오래 **「Mac에서 걸린다」**로 적고 있었다.
//   2026-08-20에 이 스크립트로 재서 **그것이 틀렸다는 것**을 확인했다 —
//   §2-A의 「✅ 쟀다」 표가 이 스크립트의 출력이다. **의심이 들면 다시 돌려라.**
//
// 왜 CLI가 유효한 대조군인가: 맥 앱도 이 CLI도 **둘 다 샌드박스가 없다**
//   (`native/`에 `*.entitlements` 0개 · `project.yml`에 `sandbox` 키 0개).
//   ⚠️ **못 답하는 것:** 맥 **앱**은 문서 피커가 준 URL로 북마크를 만든다(출처가 다를 수 있다).
//   그리고 **iOS는 이것으로 못 잰다** — 폰은 무조건 샌드박스이고 탐침 빌드가 필요하다.
//
// 2026-08-20 맥미니 실측: 북마크 성공(808B) · 해소 성공(stale=false) ·
//   `startAccessingSecurityScopedResource()` = **true** · **스코프 닫은 뒤에도 읽혔다**(160,345B).
//
// 쓰는 법: swift native/tools/probe-security-scope.swift
// ⚠️ 상태를 안 바꾼다 — 이미 받아진 파일로만 읽기를 시험한다(dataless 표본을 소비하지 않는다).

import Foundation

// 「흔들린 전제」 확인 — 설계 §2-A.
// 묻는 것: 샌드박스가 없는 프로세스에서 .withSecurityScope 북마크가 되는가,
//          그리고 스코프를 닫은 뒤에도 iCloud 파일을 읽을 수 있는가.
// ⚠️ 이 CLI는 맥 앱과 같이 **샌드박스가 없다** → 스코프 의미론에 대해 유효한 대조군이다.
//    (다른 것: 앱은 번들이고 문서 피커로 URL을 받는다. 아래 4번에 그 차이를 적었다.)

let base = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/SecondBrain")

print("대상: \(base.path)")
print("샌드박스 환경변수 APP_SANDBOX_CONTAINER_ID: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "없음(=샌드박스 아님)")")
print("")

// ── 1. .withSecurityScope 북마크를 만들 수 있나 (FragmentFolder.saveBookmark의 macOS 갈래)
print("① bookmarkData(options: [.withSecurityScope])")
var data: Data?
do {
    data = try base.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    print("   → 성공. \(data!.count) bytes")
} catch let e as NSError {
    print("   → ⛔ 던졌다: \(e.domain)/\(e.code) — \(e.localizedDescription)")
}

// ── 2. 해소할 수 있나
print("② URL(resolvingBookmarkData:, options: [.withSecurityScope])")
var resolved: URL?
var stale = false
if let data {
    do {
        resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        print("   → 성공. stale=\(stale) · path=\(resolved!.path)")
    } catch let e as NSError {
        print("   → ⛔ 던졌다: \(e.domain)/\(e.code) — \(e.localizedDescription)")
    }
} else {
    print("   → 건너뜀(①이 실패)")
}

// ── 3. startAccessingSecurityScopedResource()의 반환값
print("③ startAccessingSecurityScopedResource()")
let target = resolved ?? base
let accessed = target.startAccessingSecurityScopedResource()
print("   → \(accessed)   (false = 스코프가 안 걸린다 = no-op)")
if accessed { target.stopAccessingSecurityScopedResource() }
print("   스코프를 닫았다.")

// ── 4. ★ 스코프가 닫힌 뒤에 iCloud 파일을 읽을 수 있나
//     이미 받아둔(Current) 파일로 잰다 — dataless 표본을 더 소비하지 않기 위해서.
print("④ 스코프 닫힌 뒤 읽기 (이미 Current인 파일로 — dataless 표본 보존)")
let fm = FileManager.default
var probed = false
for sub in ["audio", "photo"] {
    let d = base.appendingPathComponent(sub)
    guard let names = try? fm.contentsOfDirectory(atPath: d.path) else { continue }
    for n in names.sorted() {
        let u = d.appendingPathComponent(n)
        guard let v = try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey,
                                                      .totalFileAllocatedSizeKey]),
              (v.totalFileAllocatedSize ?? 0) > 0 else { continue }
        do {
            let bytes = try Data(contentsOf: u)
            print("   → ✅ 읽혔다. \(sub)/\(String(n.prefix(8))) · \(bytes.count) bytes · status=\((v.ubiquitousItemDownloadingStatus?.rawValue ?? "nil").replacingOccurrences(of: "NSURLUbiquitousItemDownloadingStatus", with: ""))")
        } catch let e as NSError {
            print("   → ⛔ 못 읽었다: \(e.domain)/\(e.code)")
        }
        probed = true
        break
    }
    if probed { break }
}
if !probed { print("   → 잴 대상이 없다(바이트 있는 파일 0)") }

print("")
print("⚠️ 이 CLI가 답하지 못하는 것: 맥 **앱**은 문서 피커가 준 URL로 북마크를 만든다.")
print("   피커 URL은 CLI가 만든 URL과 출처가 다를 수 있다 — 앱에서의 최종 확인은 남는다.")
