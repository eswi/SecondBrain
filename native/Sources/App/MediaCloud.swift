import Foundation
import SecondBrainCore

/// **자료(음성·사진)의 iCloud 자리 — I/O 쪽.** 설계 `docs/native/media-icloud-design.md` §2.
/// 판정과 로그 형식은 Core(`MediaPlace.swift`)에 있고, 여기서는 **실제로 시도해 본 것만** 한다
/// (`FragmentFolder`가 사실을 모으고 `FolderLinkJudge`가 판정하는 것과 같은 구조).
///
/// **이 파일이 답하는 질문 하나:** 폰이 사용자가 고른 iCloud 폴더 **안에 디렉터리를 만들 수 있나.**
/// 2026-08-19까지 **안 재봤다.** 파일을 만드는 것은 확실하지만(`inbox-iphone-4532.md`가 폰이 만든 파일이다)
/// 하위 폴더는 처음이고, **맥 앱은 App Sandbox entitlement가 없어 대조군이 못 된다.**
///
/// ⚠️ **그래서 시도 결과를 반드시 로그로 남긴다**(사용자 지시 2026-08-19).
/// 자리 계산이 업로더 첫 실행에 묶여 있어서, **조용히 폴백으로 넘어가면 이번 걸음의 답을 못 본다.**
/// 맥에서 셋이 갈려야 한다: 「폴더가 있다」 · 「만들려다 실패해서 루트로 갔다」 · 「아직 아무것도 안 적혔다」.
enum MediaCloud {

    /// 자료 디렉터리를 **준비하고 자리를 돌려준다.** 폴더 미선택·못 열면 nil.
    ///
    /// 한 번에 둘(`audio`·`photo`)을 처리한다 — 로그를 **한 번만 읽고 한 번만 쓰기** 위해서다.
    /// 이 함수는 포그라운드 복귀마다 돌므로(§3의 도는 시점) I/O를 늘리지 않는 편이 낫다.
    ///
    /// ⚠️ **보안 스코프는 이 함수 안에서만 열려 있다.** 돌려주는 URL을 나중에 읽는 것은
    /// **아직 안 정한 것**이다 — 설계 §2-A 미결(단계 5에서 정한다).
    @discardableResult
    static func prepare() -> [MediaKind: MediaPlace]? {
        FragmentFolder.withFolder { folder in
            let fm = FileManager.default
            var records: [MediaPlaceRecord] = []
            var places: [MediaKind: MediaPlace] = [:]

            for kind in MediaKind.allCases {
                let sub = folder.appendingPathComponent(kind.subdir, isDirectory: true)
                var thrown: NSError?
                do {
                    // 이미 있으면 성공으로 온다(`withIntermediateDirectories: true`) → 아래에서 존재를 다시 본다.
                    try fm.createDirectory(at: sub, withIntermediateDirectories: true)
                } catch let e as NSError {
                    thrown = e
                }
                let ready = isDirectory(sub, fm)
                let place = MediaPlaceJudge.place(subdirReady: ready)
                places[kind] = place
                // 자리가 잡혔으면 원인 칸은 없다(던졌어도 결과가 좋으면 적을 것이 없다).
                // 못 잡았는데 던진 것도 없으면(같은 이름의 **파일**이 있는 경우 등) 원인은 **비운다** —
                // 시스템이 준 값이 없으므로 **만들지 않는다**(추측을 문장으로 만들지 않는다).
                records.append(MediaPlaceRecord(kind: kind, place: place,
                                                err: ready ? nil : thrown.map { "\($0.domain)/\($0.code)" }))
            }

            appendChangedLines(records, in: folder)
            return places
        }
    }

    /// 자리에 맞는 iCloud 쪽 파일 URL. 단계 2·3(찾기·업로더)이 쓴다.
    /// 자리가 `.root`면 폴더 루트의 `sb-<id>.<ext>`가 된다.
    static func fileURL(_ kind: MediaKind, id: String, place: MediaPlace, folder: URL) -> URL {
        folder.appendingPathComponent(MediaPlaceJudge.relativePath(kind: kind, id: id, place: place))
    }

    // MARK: 찾기 (§4) — 판정은 Core(`MediaAvailabilityJudge`), 사실 수집만 여기

    /// **지금 자리** — 만들지도 적지도 않고 **읽기만** 한다(`prepare()`가 만들고 적는 쪽).
    /// 상태를 저장하지 않는다 — **자리도 iCloud 폴더를 보고 매번 안다.**
    static func currentPlace(_ kind: MediaKind, folder: URL) -> MediaPlace {
        MediaPlaceJudge.place(subdirReady: isDirectory(folder.appendingPathComponent(kind.subdir,
                                                                                    isDirectory: true),
                                                       FileManager.default))
    }

    /// 그 id를 찾아볼 iCloud 쪽 자리들 — **지금 자리 먼저, 그다음 다른 자리.**
    /// ⚠️ 둘 다 보는 이유: **폴백을 한 번 쓴 뒤 나중에 하위 폴더가 되면 두 자리에 흩어져 있을 수 있다.**
    /// 한쪽만 보면 이미 올라간 파일을 「없다」로 읽고 **다시 올린다.**
    static func candidates(_ kind: MediaKind, id: String, folder: URL) -> [URL] {
        let now = currentPlace(kind, folder: folder)
        let other: MediaPlace = now == .subdir ? .root : .subdir
        return [now, other].map { fileURL(kind, id: id, place: $0, folder: folder) }
    }

    /// iCloud 쪽 사실 둘. 폴더 미선택·못 열면 **둘 다 false**(= 판정은 「어디에도 없다」).
    /// - `nameExists`: 이름이라도 있나. ⚠️ **dataless에도 true다**(§0-B) — 이것만으로 「여기 있다」를 못 준다.
    /// - `bytesPresent`: 실체가 내려와 있나.
    static func cloudFacts(_ kind: MediaKind, id: String) -> (nameExists: Bool, bytesPresent: Bool) {
        let f: (Bool, Bool)? = FragmentFolder.withFolder { folder in
            let fm = FileManager.default
            var nameExists = false
            for u in candidates(kind, id: id, folder: folder) {
                guard fm.fileExists(atPath: u.path) else { continue }
                nameExists = true
                if hasBytes(u, fm) { return (true, true) }   // 첫 히트를 쓴다(중복은 정상 — write-once)
            }
            return (nameExists, false)
        }
        return f ?? (false, false)
    }

    // MARK: 들여오기 (§2-A C안) — **iCloud 쪽 URL을 밖으로 내보내지 않는다**

    /// **iCloud 쪽 실체를 로컬로 들여온다.** 들여왔으면 true.
    ///
    /// ## ⛔ 왜 URL을 돌려주지 않나 — 옛 `readableURL`이 있던 자리다
    ///
    /// 여기엔 `readableURL(_:id:)`가 있었다. **바이트가 있는 iCloud URL을 돌려주는** 함수였고,
    /// 주석이 스스로 미결을 적어 뒀다: *"돌려준 뒤에는 보안 스코프가 닫혀 있다."*
    /// **2026-08-20에 C안으로 닫았다**(설계 §2-A) — **URL을 내보내지 않고, 바이트를 로컬로 옮긴다.**
    /// 그러면 **스코프 밖에서 읽는 코드가 아예 없어진다.**
    ///
    /// **유지되는 것:** 찾는 순서 `[로컬, iCloud]`(§4) · 중복 허용(write-once라 내용이 같다) ·
    /// 포인터 필드 불변 · 확정 목적지는 로컬(§3-①).
    ///
    /// **원자성 — §3 업로더와 같은 패턴이다:** 로컬 디렉터리 안에 임시 이름(`sb-adopting-…part`)으로
    /// 복사한 뒤 **같은 폴더에서 rename.** 반대로 목적지에 바로 복사하면, 도중에 죽었을 때
    /// **온전한 것처럼 보이는 반쪽 파일**이 로컬에 남고 — 그 순간
    /// **「로컬은 바이트가 보장된 층」이라는 §4의 전제가 거짓이 된다.** 그게 거짓이면 찾는 순서가 무의미해진다.
    ///
    /// ⚠️ **이 함수만 로컬 쪽에 쓴다**(다른 `MediaCloud` 함수는 iCloud만 만진다).
    /// 여기 있는 이유는 **보안 스코프를 여는 자리가 여기**라서다 — 읽기와 쓰기가 한 스코프 안에서 끝나야 한다.
    @discardableResult
    static func adopt(_ kind: MediaKind, id: String, intoDir localDir: URL) -> Bool {
        let ok: Bool? = FragmentFolder.withFolder { folder in
            let fm = FileManager.default
            // 바이트가 **실제로 있는** 것만. 이름만 있는 것(dataless)을 복사하면 빈 파일이 된다(§0-B).
            guard let src = candidates(kind, id: id, folder: folder)
                    .first(where: { fm.fileExists(atPath: $0.path) && hasBytes($0, fm) })
            else { return false }

            let part = localDir.appendingPathComponent(MediaAdoptNaming.partName(kind: kind, id: id))
            let dest = localDir.appendingPathComponent("\(id).\(kind.ext)")
            var copied = false

            let coord = NSFileCoordinator()
            var cerr: NSError?
            coord.coordinate(readingItemAt: src, options: [], error: &cerr) { r in
                do {
                    if fm.fileExists(atPath: part.path) { try fm.removeItem(at: part) }
                    try fm.copyItem(at: r, to: part)
                    copied = true
                } catch {
                    try? fm.removeItem(at: part)   // 찌꺼기를 남기지 않는다
                }
            }
            guard copied, cerr == nil else {
                try? fm.removeItem(at: part)
                return false
            }
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // 방어(멱등)
                try fm.moveItem(at: part, to: dest)
                return true
            } catch {
                try? fm.removeItem(at: part)
                return false
            }
        }
        return ok ?? false
    }

    /// 들여오다 만 찌꺼기 청소 — **로컬** 디렉터리. 업로더의 `sweepLeftovers`와 같은 모양이다(§3).
    ///
    /// ⚠️ 이 찌꺼기는 `localFiles()`의 확장자 필터에 **안 걸리므로 기능을 깨뜨리지 않는다**
    /// (그래서 `.part`를 쓴다 — `MediaAdoptNaming` 참고). 다만 **쌓이면 자리를 차지하므로** 치운다.
    static func sweepAdoptLeftovers(in localDir: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: localDir.path) else { return }
        for n in names where MediaAdoptNaming.isPartName(n) {
            try? fm.removeItem(at: localDir.appendingPathComponent(n))
        }
    }

    /// **실체가 내려와 있나.** ⚠️ `fileExists`로는 절대 못 잰다(§0-B: dataless도 true).
    /// 다운로드 상태를 먼저 보고, iCloud 항목이 아니어서 그 키가 없으면 **할당된 바이트**로 본다
    /// (§0-B에서 dataless의 `totalFileAllocatedSize`는 **0**이었다).
    private static func hasBytes(_ url: URL, _ fm: FileManager) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey,
                                                        .totalFileAllocatedSizeKey]) else { return false }
        if let st = v.ubiquitousItemDownloadingStatus {
            return st != .notDownloaded     // `.current`/`.downloaded`를 이름으로 안 쓴다(하나는 deprecated)
        }
        return (v.totalFileAllocatedSize ?? 0) > 0
    }

    // MARK: 자리 로그 — `.sb-media.log`

    /// **바뀐 것만** append. 정상이면 두 줄(audio·photo)로 영원히 끝난다(사용자 결정 2026-08-19).
    /// 실패해도 조용히 지나간다 — 로그를 못 써서 자료를 못 올리게 되면 목적이 뒤집힌다.
    private static func appendChangedLines(_ records: [MediaPlaceRecord], in folder: URL) {
        let target = folder.appendingPathComponent(MediaPlaceLog.fileName)
        let existing = readLog(target)
        let stamp = timestamp()
        let device = DeviceStore.deviceId

        var add = ""
        var seen = existing
        for r in records {
            if let line = MediaPlaceLog.appendIfChanged(existing: seen, at: stamp, device: device, r) {
                add += line
                seen += line          // 같은 쓰기 안의 앞줄도 「앞 기록」으로 본다
            }
        }
        guard !add.isEmpty else { return }
        append(add, in: folder)
    }

    /// 업로드 **실패** 한 줄(§5 — 성공은 안 적는다). 자리 로그와 **같은 파일**을 쓴다.
    static func appendUploadFailure(kind: MediaKind, id: String, err: String?, in folder: URL) {
        append(MediaUploadLog.failureLine(at: timestamp(), device: DeviceStore.deviceId,
                                          kind: kind, id: id, err: err), in: folder)
    }

    /// `.sb-media.log`에 append. 실패해도 조용히 지나간다 —
    /// **로그를 못 써서 자료를 못 올리게 되면 목적이 뒤집힌다.**
    private static func append(_ text: String, in folder: URL) {
        let target = folder.appendingPathComponent(MediaPlaceLog.fileName)
        let fm = FileManager.default
        let coord = NSFileCoordinator()
        var cerr: NSError?
        coord.coordinate(writingItemAt: target, options: [], error: &cerr) { w in
            let data = Data(text.utf8)
            if fm.fileExists(atPath: w.path), let h = try? FileHandle(forWritingTo: w) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: w, options: .atomic)
            }
        }
    }

    // MARK: 업로더가 쓰는 사실들 (§3·§5)

    /// 그 id가 **iCloud에 이름이라도 있나** — 업로더의 「이미 올렸나」 판정.
    ///
    /// ⚠️ **바이트를 보지 않는다.** iCloud가 실체를 걷어낸(evict) 파일도 **올라간 것**이다.
    /// 바이트로 판정하면 맥에서 evict된 순간 **131개를 영원히 다시 올린다.**
    static func cloudNameExists(_ kind: MediaKind, id: String, folder: URL) -> Bool {
        let fm = FileManager.default
        return candidates(kind, id: id, folder: folder).contains { fm.fileExists(atPath: $0.path) }
    }

    /// iCloud 폴더에 있는 **자료 파일 수**. 「첫 실행인가」를 이 수로 안다(§5 — 상태 저장 0).
    /// 하위 폴더 둘 + 루트 폴백(`sb-<id>.<ext>`)을 센다. **올리다 만 찌꺼기(`sb-uploading-`)는 안 센다.**
    static func cloudMediaCount(folder: URL) -> Int {
        let fm = FileManager.default
        var n = 0
        for kind in MediaKind.allCases {
            let sub = folder.appendingPathComponent(kind.subdir, isDirectory: true)
            if let e = try? fm.contentsOfDirectory(atPath: sub.path) {
                n += e.filter { ($0 as NSString).pathExtension == kind.ext }.count
            }
        }
        if let e = try? fm.contentsOfDirectory(atPath: folder.path) {
            n += e.filter { name in
                guard name.hasPrefix("sb-"), !name.hasPrefix(leftoverPrefix) else { return false }
                return MediaKind.allCases.contains { (name as NSString).pathExtension == $0.ext }
            }.count
        }
        return n
    }

    /// 올리다 만 파일의 이름 접두사. **제 이름으로 안 보이게** 하는 것이 목적이다(§3 원자성).
    static let leftoverPrefix = "sb-uploading-"

    /// 안 내려온 자료 받기 시작(§6). 성공/실패만 돌려준다.
    /// 텍스트가 이미 쓰는 API와 **같은 것**이다(`FragmentFolder.read()`) — 다른 것은 **시점**뿐.
    @discardableResult
    static func startDownload(_ kind: MediaKind, id: String) -> Bool {
        let ok: Bool? = FragmentFolder.withFolder { folder in
            let fm = FileManager.default
            for u in candidates(kind, id: id, folder: folder) where fm.fileExists(atPath: u.path) {
                if (try? fm.startDownloadingUbiquitousItem(at: u)) != nil { return true }
            }
            return false
        }
        return ok ?? false
    }

    /// 로그를 읽는다. 없으면 빈 문자열. iCloud에서 안 내려왔으면 당겨오기를 시도한다
    /// (`FragmentFolder.read()`가 조각 파일에 하는 것과 같다 — 안 내려온 것을 「없다」로 보면
    /// **바뀐 적 없는데 첫 줄을 다시 적는다**).
    private static func readLog(_ url: URL) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return "" }
        try? fm.startDownloadingUbiquitousItem(at: url)
        var out = ""
        let coord = NSFileCoordinator()
        var cerr: NSError?
        coord.coordinate(readingItemAt: url, options: [], error: &cerr) { r in
            out = (try? String(contentsOf: r, encoding: .utf8)) ?? ""
        }
        return out
    }

    // MARK: 잔심부름

    /// 그 경로가 **디렉터리로** 있나. 같은 이름의 파일이 있는 경우를 성공으로 읽지 않기 위해 따로 본다.
    private static func isDirectory(_ url: URL, _ fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    /// `2026-08-19T12:10:33+09:00` — 이 기기의 지금. **Core는 시계를 안 만든다**(값은 App이 읽어 넘긴다).
    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: Date())
    }
}
