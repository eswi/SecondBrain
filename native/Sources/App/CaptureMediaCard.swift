#if os(iOS)
import SwiftUI
import SecondBrainCore
import UIKit

//
//  CaptureMediaCard — **수집 화면의 「보조 자료」 카드** (2026-08-30 신설)
//
//  ── 왜 있나 ────────────────────────────────────────────────
//  사용자 지시(2026-08-30): *"'수집 화면'의 사진 찍기 인터페이스를 없애고 '보조 자료' 카드를
//  추가하자. 텍스트 화면은 높이를 절반 정도로 줄이고 그 아래에 자료 카드를 붙이는 것으로 하자."*
//  계기: *"지금 상세화면에서 '보조 자료' 카드가 매우 훌륭하게 잘 만들어졌어."*
//
//  ── ⛔ 왜 `MediaCard`를 그대로 못 쓰나 — **아직 항목이 없다** ────
//  `MediaCard`는 **저장된 항목**(`ResolvedItem`)의 포인터를 읽는다. 수집 화면에는
//  **[저장]을 누르기 전이라 항목도, 확정된 파일도 없다.** 임시 파일뿐이다.
//  ⛔ **가짜 `ResolvedItem`을 만들어 넘기지 말 것** — 포인터 값으로 저장소를 찾으므로
//     임시 파일은 **하나도 안 찾히고 네모가 전부 빨강(`absent`)이 된다.**
//  ⛔ **항목을 미리 만들어 두는 길도 안 골랐다** — 「원문 없는 기억」이 생기고,
//     [취소]해도 tombstone이 남는다(완전 삭제 코드는 0줄).
//  ✅ **그래서 껍데기만 함께 쓴다** — 제목·62pt 네모·`+`·넘침 점은 `MediaStrip`·`MediaTile`이 그리고,
//     **내용만 임시 파일에서** 만든다. 값이 한 자리(§0)에 남는다.
//
//  ── 저장 전 네모의 상태는 늘 `.ready`다 ─────────────────────
//  임시 파일은 **이 기기에 방금 만들어진 것**이라 「아직 못 받음」·「못 찾음」이 있을 수 없다.
//  ⚠️ **그러니 이 카드에서는 테두리 색이 한 가지다** — 색 셋(무채색·앰버·빨강)은 저장 뒤 상세에서 갈린다.
//
//  ── ⛔ 소리 네모는 안 그린다 (2026-08-30 사용자 결정) ─────────
//  녹음한 소리는 **[저장] 때 파일로 확정된다.** 저장 전에는 마이크 줄(「듣는 중…」·침묵 막대)이
//  이미 그 상태를 말하고 있어서, 카드에 또 그리면 **같은 것을 두 곳에서 말하게** 된다.
//  ✅ **저장한 뒤 상세 화면에서 소리 네모가 나타난다.**
//

/// 수집 화면의 「보조 자료」 카드 — **저장 전 임시 자료**를 그린다.
struct CaptureMediaCard: View {
    /// 임시 사진 파일들 — **붙인 순서**(첫째가 네모의 얼굴이 된다).
    let photos: [URL]
    /// 정규화를 통과한 URL 문자열들(`URLAsset.normalized`).
    let urls: [String]
    /// `+`를 눌렀을 때 — 종류 시트로 간다(상세와 **같은 시트**).
    var onAdd: () -> Void = {}
    /// 사진 네모를 눌렀을 때 — 크게 보기.
    var onTapPhoto: () -> Void = {}
    /// URL 네모를 눌렀을 때 — 앱 안 보기.
    var onTapURL: (String) -> Void = { _ in }
    /// **하나 지우라** — 길게 눌러 고른 것. 붙인 순서의 자리(index)를 넘긴다.
    /// ⚠️ **여기서 지우지 않는다** — 임시 파일을 지우는 것은 수집 시트의 몫이다
    /// (상세의 URL 떼기가 `MediaCard`가 아니라 `DetailView`에서 일어나는 것과 같은 결).
    var onRemovePhoto: (Int) -> Void = { _ in }
    var onRemoveURL: (Int) -> Void = { _ in }

    var body: some View {
        MediaStrip(tileCount: tileCount) {
            if !photos.isEmpty { photoTile }
            if !urls.isEmpty { urlTile }
            Button { onAdd() } label: { MediaEmptyTile() }
                .buttonStyle(.plain)
        }
    }

    /// 추가 네모(`+`)를 포함한 수 — `MediaStrip`의 넘침 판정이 이 수로 난다.
    private var tileCount: Int {
        (photos.isEmpty ? 0 : 1) + (urls.isEmpty ? 0 : 1) + 1
    }

    @ViewBuilder private var photoTile: some View {
        // 얼굴은 **첫째 것** — `MediaCard`와 같은 규칙(§0 8번의 개수 배지도 같다).
        let first = photos.first
        let img = first.flatMap { MediaCard.thumbnail($0, side: MediaTile.side) }
        Button { onTapPhoto() } label: {
            MediaTile(kind: .photo,
                      state: img == nil ? .cannotDraw : .ready,
                      count: photos.count,
                      image: img,
                      // 방금 찍은 사진은 EXIF에 위치가 박혀 있을 수 있다(`PhotoStore.saveCaptured`).
                      hasPlace: first.flatMap { PhotoStore.coordinate(fileURL: $0) } != nil)
        }
        .buttonStyle(.plain)
        // **길게 눌러 지우기** — ⚠️ **이 앱이 이미 쓰는 손짓이고 이미 있는 말이다**
        //   (목록 줄의 `contextMenu` · 「지우기」는 2026-08-25에 사용자가 고른 말).
        //   ⛔ 새 문구를 짓지 않았다(항시 규칙 6).
        .contextMenu {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, _ in
                Button("지우기\(photos.count > 1 ? " (\(i + 1)번째)" : "")", role: .destructive) {
                    onRemovePhoto(i)
                }
            }
        }
    }

    @ViewBuilder private var urlTile: some View {
        let first = urls.first
        let preview = first.flatMap { URLPreview.cached($0) }.map { Image(uiImage: $0) }
        Button { if let f = first { onTapURL(f) } } label: {
            MediaTile(kind: .url, state: .ready, count: urls.count, image: preview,
                      shortName: first.flatMap { URLAsset.shortName($0) })
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                Button("지우기 — \(URLAsset.shortName(u) ?? u)", role: .destructive) {
                    onRemoveURL(i)
                }
            }
        }
    }
}
#endif
