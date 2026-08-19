// measure-icloud-download.swift — iCloud dataless 파일의 **실제 다운로드 시간**을 잰다.
//
// 왜 있나: 「얼마나 기다리면 안 온 것인가」(`MediaFetch.waitSeconds`)를 짐작으로 두지 않기 위해서다.
//   설계 `docs/native/media-icloud-design.md` §6이 **자료 확장 ②(PDF·동영상)에서 다시 재라**고 적어 뒀다.
//   ⛔ **그때 이 도구를 새로 쓰지 말 것** — 새로 쓰면 오늘 값과 비교가 안 된다(CLAUDE.md 계측 규칙 5).
//
// 2026-08-20 맥미니 실측(이 스크립트로): 표본 16개 · **526~924ms**(중앙 604 · 평균 654) ·
//   유선 2500Base-T · 다운 850.7Mbps. **크기와 무관**(r=−0.364).
//   전말: `docs/worklog/2026-08-20-macmini.md` §2.
//
// 쓰는 법:
//   1) 표본 목록 파일을 만든다 — 한 줄에 절대 경로 하나. **크기 분위로 고르고 종류를 섞을 것.**
//   2) swift native/tools/measure-icloud-download.swift <목록파일>
//
// ⚠️ **이 스크립트는 상태를 바꾼다 — 되돌릴 수 없다.** 받은 파일은 dataless가 아니게 된다
//   (다시 만들려면 `brctl evict`). **표본만 받고 나머지는 남길 것.**
// ⚠️ **부분 진행률은 관측 불가다** — `totalFileAllocatedSize`가 0에서 완주값으로 한 번에 바뀐다.
//   그래서 「최초바이트」 칸이 완료와 같은 값으로 나온다. **버그가 아니다**(설계 §6·§8).

import Foundation

// iCloud dataless 파일의 실제 다운로드 시간을 잰다.
// startDownloadingUbiquitousItem 호출 → 상태가 .current 가 될 때까지 폴링.
// 값은 밀리초. 못 받으면 「못 잼」으로 남기고 값을 만들지 않는다.

let fm = FileManager.default
let timeoutSec: Double = 60.0
let pollSec: Double = 0.005

func probe(_ path: String) -> (status: String, size: Int, alloc: Int) {
    var u = URL(fileURLWithPath: path)
    u.removeAllCachedResourceValues()
    let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .fileSizeKey, .totalFileAllocatedSizeKey]
    guard let v = try? u.resourceValues(forKeys: keys) else { return ("ERR", -1, -1) }
    let st = v.ubiquitousItemDownloadingStatus?.rawValue ?? "nil"
    let short = st.replacingOccurrences(of: "NSURLUbiquitousItemDownloadingStatus", with: "")
    return (short, v.fileSize ?? -1, v.totalFileAllocatedSize ?? -1)
}

let paths = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .split(separator: "\n").map(String.init).filter { !$0.isEmpty }

let iso = ISO8601DateFormatter()
print("측정 시작 \(iso.string(from: Date()))")
print("순서\t종류\tid\t논리크기B\t시작상태\t최초바이트ms\t완료ms\t완료상태\t결과")

for (i, p) in paths.enumerated() {
    let name = (p as NSString).lastPathComponent
    let kind = name.hasSuffix(".m4a") ? "audio" : "photo"
    let id = String(name.prefix(8))
    let before = probe(p)

    guard before.status == "Downloaded" || before.status == "NotDownloaded" || before.status == "Current" else {
        print("\(i+1)\t\(kind)\t\(id)\t\(before.size)\t\(before.status)\t-\t-\t-\t상태읽기실패")
        continue
    }
    if before.status == "Current" {
        print("\(i+1)\t\(kind)\t\(id)\t\(before.size)\tCurrent\t-\t-\tCurrent\t이미받아짐-표본아님")
        continue
    }

    let t0 = Date()
    do { try fm.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: p)) }
    catch {
        print("\(i+1)\t\(kind)\t\(id)\t\(before.size)\t\(before.status)\t-\t-\t-\t시작실패:\(error)")
        continue
    }

    var firstByteMs: String = "못잼"
    var doneMs: String = "못잼"
    var endStatus = before.status
    var result = "시간초과"

    while Date().timeIntervalSince(t0) < timeoutSec {
        let s = probe(p)
        if firstByteMs == "못잼", s.alloc > 0 {
            firstByteMs = String(Int(Date().timeIntervalSince(t0) * 1000))
        }
        if s.status == "Current" {
            doneMs = String(Int(Date().timeIntervalSince(t0) * 1000))
            endStatus = s.status
            result = "완료"
            break
        }
        endStatus = s.status
        Thread.sleep(forTimeInterval: pollSec)
    }
    print("\(i+1)\t\(kind)\t\(id)\t\(before.size)\t\(before.status)\t\(firstByteMs)\t\(doneMs)\t\(endStatus)\t\(result)")
    fflush(stdout)
}
print("측정 끝 \(iso.string(from: Date()))")
