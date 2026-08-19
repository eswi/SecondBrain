import Foundation

/// **자료를 iCloud 폴더의 어디에 두나** — 설계 `docs/native/media-icloud-design.md` §2.
///
/// 이 파일은 **판정과 형식만** 담는다. 실제 디렉터리 생성·파일 쓰기는 App(`MediaCloud`)이 한다 —
/// 보안 스코프·`FileManager`는 헤드리스로 못 잡기 때문이다. **`FolderLinkJudge`와 같은 구조다:
/// 사실 수집(I/O)은 App, 판정은 여기.**
///
/// **왜 갈림이 필요한가:** 폰이 iCloud 폴더 **안에 디렉터리를 만들 수 있는지**를 아직 못 쟀다
/// (2026-08-19 · 맥 앱은 App Sandbox entitlement가 없어 대조군이 못 된다). 되면 `audio/`·`photo/`,
/// 안 되면 폴더 루트에 `sb-` 접두사. **갈림이 이 파일 안에서 끝나므로 나머지 설계가 안 무너진다.**

/// 자료의 종류. 하위 폴더 이름과 확장자를 함께 정한다.
public enum MediaKind: String, Sendable, CaseIterable {
    case audio, photo

    /// 파일 확장자. 로컬(`AudioStore`/`PhotoStore`)이 쓰는 것과 같아야 한다.
    public var ext: String {
        switch self {
        case .audio: return "m4a"
        case .photo: return "jpg"
        }
    }

    /// 하위 폴더 이름. 로컬 `Application Support/SecondBrain/{audio,photo}/`와 **1:1 대칭**.
    public var subdir: String { rawValue }
}

/// iCloud 폴더에서 자료가 놓이는 자리.
public enum MediaPlace: String, Sendable, Equatable {
    /// `audio/<id>.m4a` — 하위 폴더가 만들어졌다. **이것이 설계의 기본**(§2).
    case subdir
    /// `sb-<id>.m4a` — 하위 폴더를 못 만들어 루트에 접두사로 둔다(§2 폴백).
    /// ⚠️ 이 자리가 되면 **설계 문서와 worklog에 기록해야 한다**(사용자 지시 2026-08-19).
    case root
}

public enum MediaPlaceJudge {
    /// 하위 폴더가 **실제로 쓸 수 있는 상태인가** 하나로 자리가 정해진다.
    /// (App이 `createDirectory`를 시도하고 그 뒤 「디렉터리로 존재하나」를 확인해 넘긴다 —
    /// `createDirectory`가 던지지 않아도 존재를 다시 보는 이유는, 이미 있을 때도 성공으로 오기 때문이다.)
    public static func place(subdirReady: Bool) -> MediaPlace { subdirReady ? .subdir : .root }

    /// iCloud 폴더 기준 **상대 경로**.
    ///
    /// ⚠️ **로컬 파일명(`<id>.m4a`)은 이 갈림에 안 따라간다.** 포인터 필드 `audio:`/`photo:`는
    /// create 블록의 **성역**이고 값이 그 파일명이므로, 자리가 바뀌어도 **필드는 안 건드린다**(§4).
    public static func relativePath(kind: MediaKind, id: String, place: MediaPlace) -> String {
        switch place {
        case .subdir: return "\(kind.subdir)/\(id).\(kind.ext)"
        case .root:   return "sb-\(id).\(kind.ext)"
        }
    }
}

// MARK: 자리 로그 (`.sb-media.log`)

/// 자리 판정 결과 한 건. **성공이든 실패든 남긴다**(사용자 지시 2026-08-19) —
/// B안(자리 계산을 업로더에 묶는다)은 그 시도가 첫 실행에 묻혀 있어서,
/// **조용히 폴백으로 넘어가면 이번 걸음의 답을 못 본다.**
public struct MediaPlaceRecord: Equatable, Sendable {
    public let kind: MediaKind
    public let place: MediaPlace
    /// 실패 원인 — **`<domain>/<code>`, 시스템이 준 값 그대로.**
    /// ⚠️ **해석을 붙이지 않는다.** 오류와 원인의 대응이 문서로 보장되지 않아 추측을 문장으로 만들면
    /// 틀린 안내가 된다(`FolderLink.unreachable` 주석이 세운 경계와 같다).
    public let err: String?

    public init(kind: MediaKind, place: MediaPlace, err: String? = nil) {
        self.kind = kind
        self.place = place
        self.err = err
    }
}

/// 자리 로그의 **형식과 「남길지 말지」 판정.** 파일 쓰기는 App이 한다.
///
/// **왜 「바뀔 때만」인가**(사용자 결정 2026-08-19): 실행마다 남기면 켤 때마다 줄이 늘어
/// 몇 주면 「자리가 어디로 정해졌나」를 읽을 수 없다. 진단용인데 진단이 안 된다.
/// 바뀔 때만 남기면 **파일 자체가 상태를 말한다** — 두 줄이면 정상, 세 번째 줄이 있으면 그때 무슨 일이 있었다.
public enum MediaPlaceLog {
    /// iCloud 폴더 루트의 **숨김** 파일. 파일 앱·Finder에 안 보이고, 맥에서 `cat`으로 읽는다.
    /// (같은 폴더의 `.DS_Store`·`.claude/`가 이미 동기화되는 것을 2026-08-19에 확인했다 —
    /// 숨김 이름도 iCloud를 넘어온다.)
    public static let fileName = ".sb-media.log"

    /// 한 줄. `timestamp`는 **App이 그때 읽은 값**을 넘긴다(Core는 시계를 안 만든다).
    public static func line(at timestamp: String, device: String, _ r: MediaPlaceRecord) -> String {
        var s = "\(timestamp) \(device) \(r.kind.rawValue) place=\(r.place.rawValue)"
        if let e = r.err { s += " err=\(e)" }
        return s + "\n"
    }

    /// 그 종류의 **마지막 기록**. 없으면 nil(= 아직 한 번도 안 적혔다).
    /// 읽을 수 없는 줄은 조용히 지나간다 — 손으로 뭘 적어 넣어도 판정이 안 망가지게.
    public static func last(_ text: String, kind: MediaKind) -> MediaPlaceRecord? {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let t = raw.split(separator: " ").map(String.init)
            guard t.count >= 4, t[2] == kind.rawValue else { continue }
            // `uniqueKeysWithValues`를 쓰지 않는다 — 손으로 고친 줄에 같은 키가 둘이면 **크래시**한다.
            var fields: [String: String] = [:]
            for tok in t.dropFirst(3) {
                guard let eq = tok.firstIndex(of: "=") else { continue }
                let k = String(tok[tok.startIndex..<eq])
                if fields[k] == nil { fields[k] = String(tok[tok.index(after: eq)...]) }
            }
            guard let p = fields["place"], let place = MediaPlace(rawValue: p) else { continue }
            return MediaPlaceRecord(kind: kind, place: place, err: fields["err"])
        }
        return nil
    }

    /// **이번 결과를 남겨야 하나** — 남길 줄, 또는 nil(앞 기록과 같다 → 안 적는다).
    /// 첫 실행은 앞 기록이 없으므로 **반드시 남는다.**
    public static func appendIfChanged(existing: String, at timestamp: String,
                                      device: String, _ r: MediaPlaceRecord) -> String? {
        if let prev = last(existing, kind: r.kind), prev == r { return nil }
        return line(at: timestamp, device: device, r)
    }
}
