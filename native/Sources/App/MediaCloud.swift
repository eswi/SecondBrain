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

        let fm = FileManager.default
        let coord = NSFileCoordinator()
        var cerr: NSError?
        coord.coordinate(writingItemAt: target, options: [], error: &cerr) { w in
            let data = Data(add.utf8)
            if fm.fileExists(atPath: w.path), let h = try? FileHandle(forWritingTo: w) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: w, options: .atomic)
            }
        }
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
