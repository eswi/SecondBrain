import Foundation
import SecondBrainCore

/// **자료를 iCloud로 올리는 쪽** — 설계 `docs/native/media-icloud-design.md` §3·§5.
///
/// ⛔ **수집 경로(`finalize`)는 안 건드린다.** 확정은 지금도 **로컬**에 하고, 올리기는 **그 뒤 별도**다.
/// 목적지를 iCloud로 바꾸면 **네트워크가 느리거나 끊긴 순간 원본이 영구 유실된다**(§3).
///
/// **대상 = 「로컬에 있는데 iCloud에 없는 것」을 매번 새로 뺀 차집합.**
/// 상태를 저장하지 않으므로 **멱등**이고, 도중에 죽어도 다음 실행이 이어간다.
/// **그래서 기존 131개 이관에 별도 코드가 없다** — 이관 = 이 코드의 첫 실행(§5).
enum MediaUploader {

    struct Item: Sendable, Equatable {
        let kind: MediaKind
        /// **파일 이름 그대로**(2026-08-23 · C). 옛 꼴은 확장자를 뗀 「id」였다 —
        /// 그때는 경로 계산이 확장자를 다시 붙였으므로 결과가 같았고, 지금은 **이름을 그대로 넘긴다.**
        /// ★ 그래서 **새 꼴(`<항목id>-<자료id>.jpg`)도 아무 변경 없이 올라간다.**
        let name: String
        let local: URL
    }

    struct Plan: Sendable, Equatable {
        /// 이번 실행에 올릴 것(한도 적용 뒤).
        let pending: [Item]
        /// 차집합 **전체** 크기 — 배너의 분모(「12/131」의 131).
        let total: Int
        /// 한도 때문에 **나머지가 남았나**(§8 완료 문구를 가른다).
        let capped: Bool
    }

    // MARK: 계획

    /// 올릴 것을 정한다. 폴더 미선택·못 열면 nil(= 아무것도 안 한다 — §3).
    static func plan() -> Plan? {
        FragmentFolder.withFolder { folder in
            sweepLeftovers(in: folder)   // 앞 실행이 죽으며 남긴 찌꺼기부터 치운다(§3)

            // ⚠️ 한도 판정을 **먼저** 잰다 — 올리기 시작한 뒤에 세면 이미 0이 아니다.
            let limit = MediaUploadJudge.limit(cloudMediaCount: MediaCloud.cloudMediaCount(folder: folder))

            let byKind = MediaKind.allCases.map { kind in
                localItems(kind).filter { !MediaCloud.cloudNameExists(kind, name: $0.name, folder: folder) }
            }
            let all = interleave(byKind)
            let capped = MediaUploadJudge.capped(total: all.count, limit: limit)
            let pending = limit.map { Array(all.prefix($0)) } ?? all
            return Plan(pending: pending, total: all.count, capped: capped)
        }
    }

    /// 종류를 **번갈아** 섞는다.
    ///
    /// **왜 그냥 이어붙이지 않나:** 첫 실행 한도가 5개인데 음성이 103개·사진이 28개다.
    /// 종류별로 이어붙이면 **첫 5개가 전부 음성**이 되어 **`photo/`가 만들어지는지 못 본다.**
    /// 한도를 5로 정한 근거가 *"양쪽에 파일이 생기는지 보기 충분하다"* 였으므로(§5) 번갈아 섞는다.
    private static func interleave(_ groups: [[Item]]) -> [Item] {
        var out: [Item] = []
        var i = 0
        while true {
            var added = false
            for g in groups where i < g.count {
                out.append(g[i]); added = true
            }
            if !added { break }
            i += 1
        }
        return out
    }

    private static func localItems(_ kind: MediaKind) -> [Item] {
        let files = kind == .audio ? AudioStore.localFiles() : PhotoStore.localFiles()
        return files.map { Item(kind: kind, name: $0.lastPathComponent, local: $0) }
    }

    // MARK: 올리기 (하나씩 · 원자적)

    /// 하나 올린다. **성공이면 true.** 실패는 `.sb-media.log`에 한 줄 남고 **다음 실행이 다시 집는다.**
    ///
    /// **원자성(§3):** 같은 폴더 안에 임시 이름으로 복사 → **rename**.
    /// 같은 볼륨 rename은 원자적이라 **반쯤 올라간 파일이 제 이름으로 보이는 일이 없다.**
    /// 반대로 복사를 목적지에 바로 하면, 도중에 죽었을 때 **온전한 것처럼 보이는 반쪽 파일**이 남고
    /// 다음 실행은 「이미 올렸다」로 읽는다 — **그 파일은 영원히 깨진 채로 남는다.**
    @discardableResult
    static func upload(_ item: Item) -> Bool {
        let ok: Bool? = FragmentFolder.withFolder { folder in
            let place = MediaCloud.currentPlace(item.kind, folder: folder)
            let dest = MediaCloud.fileURL(item.kind, name: item.name, place: place, folder: folder)
            let tmp = dest.deletingLastPathComponent()
                .appendingPathComponent("\(MediaCloud.leftoverPrefix)\(item.name)")
            let fm = FileManager.default
            var failure: String?

            let coord = NSFileCoordinator()
            var cerr: NSError?
            coord.coordinate(writingItemAt: dest, options: [], error: &cerr) { w in
                do {
                    if fm.fileExists(atPath: tmp.path) { try fm.removeItem(at: tmp) }
                    try fm.copyItem(at: item.local, to: tmp)
                    if fm.fileExists(atPath: w.path) { try fm.removeItem(at: w) }   // 방어(멱등)
                    try fm.moveItem(at: tmp, to: w)
                } catch let e as NSError {
                    failure = "\(e.domain)/\(e.code)"
                    try? fm.removeItem(at: tmp)   // 찌꺼기를 남기지 않는다
                }
            }
            if failure == nil, let c = cerr { failure = "\(c.domain)/\(c.code)" }

            if let failure {
                MediaCloud.appendUploadFailure(kind: item.kind, name: item.name, err: failure, in: folder)
                return false
            }
            return true
        }
        return ok ?? false
    }

    /// 올리다 만 찌꺼기 청소 — 루트와 하위 폴더 둘. **다음 실행이 치운다**(§3).
    private static func sweepLeftovers(in folder: URL) {
        let fm = FileManager.default
        var dirs = [folder]
        dirs += MediaKind.allCases.map { folder.appendingPathComponent($0.subdir, isDirectory: true) }
        for d in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: d.path) else { continue }
            for n in names where n.hasPrefix(MediaCloud.leftoverPrefix) {
                try? fm.removeItem(at: d.appendingPathComponent(n))
            }
        }
    }
}
