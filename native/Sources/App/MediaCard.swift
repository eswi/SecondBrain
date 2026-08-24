import SwiftUI
import SecondBrainCore
import AVFoundation
import ImageIO
#if os(iOS)
import UIKit
#endif

//
//  MediaCard — **보조 자료 카드** (2026-08-23 신설 · 자료 확장 ② 커밋 ②-1)
//
//  ── 무엇인가 ────────────────────────────────────────────────
//  **자료를 성역에서 떼어 세운 카드**다. 정본 = `docs/native/media-expansion-design.md` **§0**
//  (「정해진 것 전부 — 구현할 때 볼 한 장」). 이 파일은 그 §0의 **0-1·0-2**를 그린다.
//
//  ⛔ **값을 여기서 바꾸지 말 것** — 62pt·8pt·11.3pt·14.9pt는 **재서 정한 값**이고 §0이 정본이다.
//     고치려면 §0과 그 근거 절을 함께 고친다.
//
//  ── 왜 성역에서 뗐나 ────────────────────────────────────────
//  2026-08-13 사용자 판정: *「성역을 펼쳐서 사진을 보는 방식은 매우 불편하다」*.
//  자료는 **보려고 여는 것**인데 성역은 **확인하는 것**이라 성격이 다르다(설계 §3-2).
//
//  ── ⚠️ 지금 데이터로 뜨는 것은 둘뿐이다 ──────────────────────
//  종류는 여섯이지만 **포인터가 있는 것은 `audio`·`photo` 둘**이다(나머지 넷은 필드가 없다).
//  그래서 **네모는 최대 둘**이고 **넘침도 안 생긴다**. ⛔ **막힌 것이 아니라 데이터가 아직 없는 것이다** —
//  종류가 늘면 `pointer(for:)`만 채우면 이 카드는 그대로 산다(설계 §3-J-1).
//

// MARK: - 종류 여섯 (순서가 화면 순서다 · §0 5번)

/// ⛔ **`SecondBrainCore.MediaKind`(audio·photo)와 다른 것이다** — 저쪽은 **파일 종류**,
/// 이쪽은 **카드의 칸**이다. 이름을 갈라 둔다.
enum MediaCardKind: Int, CaseIterable, Identifiable {
    case voice = 0, photo, video, url, pdf, other
    var id: Int { rawValue }

    /// 이 종류의 포인터 필드 이름. ⚠️ **셋은 아직 필드가 없다** — 종류가 늘 때 여기를 채운다.
    /// ✅ **url이 켜졌다**(2026-08-24 · 설계 §3-Z).
    var field: String? {
        switch self {
        case .voice: return "audio"
        case .photo: return "photo"
        case .url:   return "url"
        case .video, .pdf, .other: return nil
        }
    }

    /// Core의 포인터 종류. 필드가 없는 셋은 nil.
    var pointerKind: MediaPointer.Kind? {
        switch self {
        case .voice: return .audio
        case .photo: return .photo
        case .url:   return .url
        case .video, .pdf, .other: return nil
        }
    }
}

extension ResolvedItem {
    /// 이 종류의 **포인터 값들** — ★ **포인터의 값을 읽는다**(2026-08-23 · C · 설계 §3-X).
    ///
    /// ⚠️ **이름이 `mediaNames`였는데 바꿨다**(2026-08-24 · 설계 §3-Z-5) — **값이 파일 이름이 아닐 수 있다.**
    /// 사진·음성은 파일 이름이고 **URL은 URL 문자열 자체**다. 「파일이냐」는 `MediaPointer.Kind.valueIsFilename`이 안다.
    ///
    /// ⛔ **옛 코드는 `fields["photo"] != nil`로 「있나 없나」만 봤다**(제약 9-b) — 그래서
    /// 조회는 항목 id에서 이름을 계산할 수밖에 없었고, **한 항목에 자료 하나**가 상한이었다.
    /// **옛 단일 필드와 새 필드(`photo.<자료id>`)를 함께** 읽는다(`MediaPointer`).
    ///
    /// ⚠️ **지금 데이터에서는 언제나 0개 또는 1개다** — 여럿인 항목이 아직 없다(표본은 3단계에서 생긴다).
    func mediaValues(_ k: MediaCardKind) -> [String] {
        guard let pk = k.pointerKind else { return [] }
        return MediaPointer.pointers(pk, in: fields).map(\.value)
    }
}

// MARK: - 네모 하나

/// 네모의 상태 — **§0 20번의 실패 셋**과 「보인다」.
enum MediaTileState {
    case ready                 // 정상 — 그림(또는 음성 아이콘)이 있다        → 밝은 무채색
    case notDownloaded         // 파일은 iCloud에 있는데 **아직 못 받았다**    → 앰버
    case cannotDraw            // 파일은 **열리는데 그림만** 못 만들었다        → 앰버 (뷰어에서는 보인다)
    case absent                // **어디에도 없다**                          → 빨강
    case unreadable            // 파일은 있는데 **열 수 없다**(잘못된 파일)     → 빨강 (뷰어에서도 못 본다)
    case unsupported           // 포맷 지원이 안 된다                        → 빨강
}

/// ⚠️ **2026-08-23에 `notFetched` 하나를 둘(`notDownloaded`·`absent`)로 갈랐다** — **색이 갈라야 해서다**
/// (사용자: *"파일이 존재하지 않는 경우 … 빨간색, 파일이 있으나 아직 가져오지 못한 경우 앰버"*).
/// ⛔ **§0 21번(「②는 하나로 본다」)이 통째로 뒤집힌 것이 아니다** — **문구는 아직 하나**이고
/// **색만 갈렸다.** 문구를 가를지는 사용자 결정 대기(설계 §3-N).

/// 62pt 정사각형 하나. **한 변이 값이라 안쪽 치수는 전부 그 비율이다**(§0 6·16·18번).
struct MediaTile: View {
    let kind: MediaCardKind
    let state: MediaTileState
    let count: Int
    /// 사진일 때 — 그릴 그림(중앙 크롭은 `scaledToFill` + `frame` + `clipped`가 한다).
    var image: Image? = nil
    /// 음성·동영상일 때 — 「0:37」 꼴.
    var duration: String? = nil
    /// 사진에 EXIF 위치가 있나(§0 18·19번 — **있을 때만 그리고 누를 수 없다**).
    var hasPlace: Bool = false
    /// URL일 때 — 「example」 꼴의 짧은 이름(`URLAsset.shortName`).
    /// ⛔ **도메인 전체가 아니다** — 62pt에 안 들어간다(2026-08-24 쟀다 · 설계 §3-Z-4).
    var shortName: String? = nil

    static let side: CGFloat = 62      // §0 6번
    private var side: CGFloat { Self.side }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface2)
            face
            if count > 1 { badge }     // §0 8번 — ⚠️ 지금 데이터에서는 늘 1이라 안 뜬다
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(borderColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 테두리 색 — ⛔ **②만 무채색이다**(2026-08-23 사용자 · §0 20번의 뜻을 테두리까지 넓혔다).
    ///
    /// **왜:** ②는 **「고장」이 아니라 「아직」**이다. 아이콘·글자만 무채색으로 두고 테두리를 coral로 두니
    /// **화면에서 테두리가 가장 크게 보여 그 뜻을 덮었다** — 자료가 둘 다 ②인 항목에서 **「고장 둘」로 읽혔다.**
    /// ⚠️ **랩에서는 안 보였다** — 꼴 X는 ①②③을 나란히 두어 **아이콘 차이로 갈렸는데**,
    /// 실제 화면은 **②만 여럿**이라 비교 대상이 없었다. **나란히 두면 갈리고 혼자 있으면 안 갈린다.**
    /// ★ **색 규칙 (2026-08-23 사용자)** — 세 갈래다:
    /// **정상 = 밝은 무채색** · **아직 못 받음 = 앰버**(파일은 iCloud에 있다) ·
    /// **없거나 못 보는 것 = 빨강**(어디에도 없다 · 파일이 잘못됐다 · 포맷 미지원).
    /// ⚠️ 앞선 판단(「②는 무채색」)에서 **한 칸 갈렸다** — 「아직」과 「없음」이 **같은 색이면 안 된다.**
    /// ★ **색 규칙 (2026-08-23 사용자)** — **테두리만으로 말한다**(글자·아이콘은 무채색이다).
    /// **정상 = 밝은 무채색**(원문 글자색 정도) · **앰버 = 지금은 못 보여주지만 길이 있다** ·
    /// **빨강 = 없거나, 있어도 못 본다.**
    /// ★ 앰버와 빨강을 가르는 것은 **「기다리거나 눌러서 볼 수 있나」**다 — 심각도가 아니라 **길의 유무**다.
    private var borderColor: Color {
        switch state {
        case .ready:                       return Palette.textPrimary         // 밝은 무채색
        case .notDownloaded, .cannotDraw:  return Palette.today               // 앰버 — 길이 있다
        case .absent, .unreadable, .unsupported:
            return Palette.overdue.opacity(0.75)                              // 빨강 — 길이 없다
        }
    }

    @ViewBuilder private var face: some View {
        // ⛔ **글자·아이콘은 상태 색을 안 따라간다** — *"글자는 그대로 두자. 테두리만으로 말한다"*(사용자).
        switch state {
        case .ready:          readyFace
        case .cannotDraw:     failFace("hand.tap.fill", "눌러서\n보기")
        case .notDownloaded:  failFace("icloud.and.arrow.down", "아직\n못 받음")
        // ★ **빨강이 여럿이라 글자가 「왜 빨간가」를 말해야 한다**(사용자 2026-08-23):
        //   *"빨간색인 경우가 여럿이라 왜 빨간 테두리인지 못 알아채면 곤란하잖아?"*
        //   ⚠️ **아래 둘은 내가 고른 임시 문구다** — 사용자가 확정하면 바꾼다(항시 규칙 6 · 설계 §3-N-5).
        case .absent:         failFace("icloud.and.arrow.down", "못 찾음")          // ⏸ 임시
        case .unreadable:     failFace("exclamationmark.triangle.fill", "깨진\n파일") // ⏸ 임시
        case .unsupported:    failFace("nosign", "지원\n안 함")
        }
    }

    @ViewBuilder private var readyFace: some View {
        switch kind {
        case .voice:
            // ★ 음성만 미리보기가 없다 — **아이콘 + 길이 한 줄**(날짜는 뺐다 · §0 11번).
            VStack(spacing: max(1, side * 0.04)) {
                Image(systemName: "waveform")
                    .font(.system(size: side * 0.34)).foregroundStyle(Palette.accent)
                if let duration {
                    Text(duration).font(.system(size: side * 0.15 + 2, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .offset(y: 1)                       // §0 16번 — 음성·동영상 둘 다 1pt 내린다
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .photo:
            ZStack {
                if let image {
                    image.resizable().scaledToFill()        // §0 12번 — **중앙이 포함되는 정사각형**
                        .frame(width: side, height: side)
                        .clipped()
                }
                if hasPlace {
                    // §0 18번 — 우하단 · **누르는 것이 아니다**(위치 보기는 뷰어에서 · §0 26번)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: side * 0.24))
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(side * 0.05)
                }
            }
        case .url:
            // ★★ **뽑아 둔 대표 그림이 있으면 그것을 「온전히」 그린다** (사용자 결정 · 설계 §3-Z-2 C).
            //   ⛔ **사진처럼 중앙을 자르지 않는다** — 2026-08-24에 재 보니 og:image는 아이콘이 아니라
            //   **대표 이미지**여서 띠(367×75)·세로로 긴 것(960×2119)이 온다. **자르면 로고 글자만 남는다**
            //   (실데이터 `wowanalytica`가 그 경우다). 그래서 **`scaledToFit` + 남는 데를 비운다.**
            if let image {
                image.resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(side * 0.06)
            } else {
            // ★ **못 뽑았으면 ①** — 음성과 같은 꼴이다(아이콘 + 짧은 글자 한 줄).
            //   ⚠️ 글자 크기는 **11pt 자리**다 — 그 폭에서 쟀다(§3-Z-4). `daum` 29.1 · `wikipedia` 49.1pt
            //   이고 안쪽은 **54.6pt**다. **넘치는 이름**(`stackoverflow` 72.9)은 줄여 그린다.
            VStack(spacing: max(1, side * 0.04)) {
                Image(systemName: "link")
                    .font(.system(size: side * 0.34)).foregroundStyle(Palette.accent)
                if let shortName {
                    Text(shortName).font(.system(size: side * 0.15 + 2, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, side * 0.06)
                        .offset(y: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .video, .pdf, .other:
            // ⚠️ 지금 데이터로는 여기 올 일이 없다(포인터가 없다). 종류가 늘 때 채운다.
            Image(systemName: "doc").font(.system(size: side * 0.34))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 실패 셋 — **글자만으로는 62pt에서 안 갈린다.** 아이콘도 함께 가른다(설계 §3-D-6).
    private func failFace(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: max(2, side * 0.05)) {
            Image(systemName: kind == .voice ? "waveform" : (kind == .url ? "link" : "photo"))
                .font(.system(size: side * 0.26)).foregroundStyle(Palette.textTertiary)
            Image(systemName: symbol).font(.system(size: side * 0.17))
                .foregroundStyle(Palette.textSecondary)          // ⛔ 무채색 — 색은 테두리가 말한다
            if !text.isEmpty {
                Text(text).font(.system(size: max(7, side * 0.115)))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    .padding(.horizontal, side * 0.06)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var badge: some View {
        Text("\(count)")
            .font(.system(size: max(9, side * 0.19), weight: .bold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, max(3, side * 0.07)).padding(.vertical, max(1, side * 0.03))
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .padding(max(2, side * 0.05))
    }
}

/// **추가 네모** — 점선 + `+`. **자료가 있든 없든 늘 맨 뒤에 있다**(2026-08-23 사용자).
/// ⛔ **추가 경로를 하나로 유지하려는 것이다** — 그리고 **빈 카드가 다른 화면이 되지 않게** 한다.
/// ⚠️ 자료 0개인 항목은 살아있는 것의 **44%**다(2026-08-23 실측 46/105 · 설계 §3-H-7) —
/// 그 항목에서는 **이 네모 하나만** 보인다.
struct MediaEmptyTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.textTertiary.opacity(0.6),
                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay(Image(systemName: "plus")
                .font(.system(size: MediaTile.side * 0.30, weight: .light))
                .foregroundStyle(Palette.textTertiary))
            .frame(width: MediaTile.side, height: MediaTile.side)
    }
}

// MARK: - 카드

/// 보조 자료 카드 — **폭 전체 · 접기 없음**(§0 1·2·4번).
struct MediaCard: View {
    let item: ResolvedItem
    @ObservedObject var audioFetch: MediaFetch
    @ObservedObject var photoFetch: MediaFetch
    /// 네모를 눌렀을 때 — **뷰어로 간다**(§0 24~26번).
    var onTap: (MediaCardKind) -> Void = { _ in }
    /// **추가 네모(`+`)를 눌렀을 때** — 종류를 고르는 시트로 간다(2026-08-23 · 3단계).
    var onAdd: () -> Void = {}
    /// **URL 하나를 열라** — 앱 안 보기는 상세가 띄운다(2026-08-25 · §3-Z-9).
    var onOpenURL: (String) -> Void = { _ in }
    /// **이 URL을 떼라** — ⚠️ **여기서 지우지 않는다.** 상세가 **확인을 묻고** 지운다
    /// (정본: *"되돌리기 없음"* · `edit-policy.md` ③ · §3-Z-10).
    var onDeleteURL: (String?) -> Void = { _ in }

    #if os(iOS)
    /// URL이 **둘 이상**일 때 그 네모에 붙는 팝오버. ⚠️ **자리가 네모에 걸려 있어서 여기 있다** —
    /// 상세(`DetailView`)에 두면 **어느 네모 아래인지**를 알려줄 수가 없다(§3-Z-9).
    @State private var urlPick: URLPick?
    #endif

    private static let gap: CGFloat = 8        // §0 6번

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // §0 2번 — 사용자가 고른 말. ⚠️ **글꼴은 다른 카드 제목과 같아야 한다**
            // (`DetailView.sectionLabel` = `.caption.weight(.semibold)` + `textSecondary`).
            // ⛔ 처음엔 `.callout`으로 넣었더니 **이 카드만 제목이 컸다**(2026-08-23 실기기에서 사용자가 잡았다).
            Text("보조 자료")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            tiles
        }
        .padding(14).card()
        .task(id: item.id) {
            // ⚠️ **자료 하나짜리 상태다** — `MediaFetch`는 종류마다 하나이므로 **첫 자료의 상태**를 본다.
            //    여럿이 되면 **자료마다 상태**가 필요하다(3단계에서 표본과 함께 걸린다 · §3-X-4).
            if let n = item.mediaValues(.voice).first { audioFetch.start(.audio, name: n) }
            if let n = item.mediaValues(.photo).first { photoFetch.start(.photo, name: n) }
        }
    }

    @ViewBuilder private var tiles: some View {
        let kinds = presentKinds
        GeometryReader { geo in
            // ⚠️ **추가 네모(+)를 함께 센다** — 늘 있으므로 **네모 수 = 종류 수 + 1**이다.
            let n = kinds.count + 1
            let need = CGFloat(n) * MediaTile.side + CGFloat(n - 1) * Self.gap
            let overflows = need > geo.size.width + 0.5
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.gap) {
                    ForEach(kinds) { k in
                        #if os(iOS)
                        if k == .url { urlTileButton } else { plainTileButton(k) }
                        #else
                        plainTileButton(k)
                        #endif
                    }
                    // ★★ **추가 네모는 늘 맨 뒤에 있다** (2026-08-23 사용자 · §0 10번 개정).
                    //
                    // ⛔ **옛 꼴은 「자료가 0개일 때만」 점선 네모를 뒀다** — 그러면
                    //    **빈 카드가 다른 화면**이 된다(자료가 생기는 순간 추가 자리가 사라졌다).
                    //    사용자: *"그러면 빈 카드와 자료 있는 카드가 **같은 구조**가 된다."*
                    // ✅ **2026-08-23부터 눌린다** — `MediaAddSheet`(종류를 먼저 고른다)로 간다.
                    //    ⛔ **옛 서술(지우지 않는다):** *"⏸ 아직 안 눌린다 … 누르면 아무 일 없는 단추를
                    //    만들지 않고, 없는 기능을 알리는 문구도 짓지 않는다."*
                    //    ⚠️ **뒷문장이 뒤집혔다**(사용자 결정): 시트는 **종류 여섯을 다 보이고**
                    //    아직 안 되는 다섯을 누르면 **「아직 못 담아요」**를 그 줄에 띄운다.
                    //    **앞문장은 유지된다** — `+` 자체는 이제 **실제로 무언가를 연다.**
                    Button { onAdd() } label: { MediaEmptyTile() }
                        .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) {
                // §0 9번 — ㉰ 아래 점. **네모를 안 덮는 대신 카드가 12pt 높아진다.**
                // ⚠️ 지금 데이터(최대 둘)로는 안 뜬다.
                if overflows {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.textSecondary).frame(width: 5, height: 5)
                        Circle().fill(Palette.textTertiary.opacity(0.5)).frame(width: 5, height: 5)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.textTertiary)
                    }
                    .offset(y: 12)
                }
            }
        }
        .frame(height: MediaTile.side + (overflowsNow ? 12 : 0))
    }

    private func plainTileButton(_ k: MediaCardKind) -> some View {
        Button { onTap(k) } label: { tile(k) }.buttonStyle(.plain)
    }

    #if os(iOS)
    /// ★ **URL 네모만 다르다** — 하나면 바로 열고, **둘 이상이면 이 네모에 붙어 목록이 내려온다**
    /// (2026-08-25 사용자: *"내가 누른 네모 바로 아래에 붙어서 내려오는 형식"*).
    /// ⚠️ **`arrowEdge: .top`이 「네모 아래로 펼친다」는 뜻이다** — 화살표가 팝오버의 위쪽에 붙는다.
    @ViewBuilder private var urlTileButton: some View {
        Button {
            let e = urlEntries
            if e.count > 1 { urlPick = URLPick(urls: e) }
            else if let first = e.first { onOpenURL(first.value) }
        } label: {
            tile(.url)
        }
        .buttonStyle(.plain)
        .popover(item: $urlPick, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { p in
            URLPickSheet(urls: p.urls,
                         onPick: { e in
                             urlPick = nil          // 먼저 닫는다 — 팝오버 위에 브라우저를 겹치지 않는다
                             onOpenURL(e.value)
                         },
                         onDelete: { e in
                             urlPick = nil          // 팝오버를 닫고 **상세가 확인을 묻는다**
                             onDeleteURL(e.assetId)
                         })
        }
    }

    /// URL 줄들 — ⛔ **값만 읽으면 안 된다.** 같은 URL을 두 번 붙일 수 있어서
    /// 「어느 것을 지우나」는 **자료 id**로만 정해진다(§3-Z-10). 그래서 `pointers`를 쓴다.
    private var urlEntries: [URLEntry] {
        MediaPointer.pointers(.url, in: item.fields)
            .map { URLEntry(assetId: $0.assetId, value: $0.value) }
    }
    #endif

    /// 높이를 정하려면 넘치는지 **미리** 알아야 한다(`GeometryReader` 안에서는 늦다).
    /// 폭은 §0 6번의 **342pt**를 쓴다 — 화면 폭 402 − `ScrollView` 16×2 − 카드 14×2.
    private var overflowsNow: Bool {
        let n = presentKinds.count + 1        // 추가 네모(+)가 늘 있다
        return CGFloat(n) * MediaTile.side + CGFloat(n - 1) * Self.gap > 342
    }

    /// 0개인 종류는 네모를 안 보인다(§0 7번). **포인터 값을 읽어** 센다(C 뒤 — 9-b 해소).
    private var presentKinds: [MediaCardKind] {
        MediaCardKind.allCases.filter { !item.mediaValues($0).isEmpty }
    }

    @ViewBuilder private func tile(_ k: MediaCardKind) -> some View {
        switch k {
        case .voice:
            // ★ **개수는 포인터를 센 값이다**(§0 8번). ⚠️ 지금 데이터에서는 늘 1이라 배지가 안 뜬다.
            let names = item.mediaValues(.voice)
            let aurl = names.first.flatMap { AudioStore.url(name: $0) }
            MediaTile(kind: .voice,
                      state: state(audioFetch, url: aurl, drawable: aurl != nil),   // 음성은 그림이 없다
                      count: names.count, duration: MediaCard.durationText(aurl))
        case .photo:
            let names = item.mediaValues(.photo)
            let url = names.first.flatMap { PhotoStore.url(name: $0) }
            let img = url.flatMap { MediaCard.thumbnail($0, side: MediaTile.side) }
            MediaTile(kind: .photo,
                      state: state(photoFetch, url: url, drawable: img != nil),
                      count: names.count, image: img,
                      hasPlace: names.first.flatMap { PhotoStore.coordinate(name: $0) } != nil)
        case .url:
            // ★ **URL은 파일이 없다** — 그래서 `MediaFetch`의 세 상태(here/notDownloaded/absent)를
            //    아예 지나간다. **포인터 값이 곧 자료라서 늘 「있다」**(설계 §3-Z-2 A).
            //    ⏸ 미리보기 그림은 아직 없다 — **①(아이콘 + 도메인 이름)이 지금의 얼굴**이다(§3-Z-2 C).
            let urls = item.mediaValues(.url)
            // ⛔ **캐시만 읽는다 — 여기서 연결하지 않는다**(설계 §3-Z-2 D).
            #if os(iOS)
            let preview = urls.first.flatMap { URLPreview.cached($0) }.map { Image(uiImage: $0) }
            #else
            let preview: Image? = nil
            #endif
            MediaTile(kind: .url, state: .ready, count: urls.count, image: preview,
                      shortName: urls.first.flatMap { URLAsset.shortName($0) })
        default:
            MediaTile(kind: k, state: .unsupported, count: 1)
        }
    }

    /// 세 갈래를 **네모의 두 상태로 접는다**(§0 21번) — `notDownloaded`·`absent`는 **하나로**.
    /// ⛔ 「다시 시도」를 안 쓰는 이유가 이것이다: `absent`에서 거짓말이 된다(설계 §3-E-3).
    /// ⛔ **2026-08-23 결함 수정** — 옛 코드는 `.here`이고 파일이 있으면 **무조건 `.cannotDraw`**를 냈다.
    /// 사진에서는 맞았지만(그림 디코드가 실패했을 때만 여기 온다) **음성에서는 틀렸다** —
    /// **파일이 멀쩡히 있는데 「눌러서 보기」(빨강)로 그렸다.**
    /// ⚠️ **시뮬에서는 안 드러났다** — 샘플에 **파일이 없어서** 늘 「아직 못 받음」으로 빠졌다.
    /// ★ **포인터만 있고 파일이 없는 표본은 이 갈래를 못 가른다**(설계 §3-N-2).
    ///
    /// - `drawable`: **그림까지 만들어졌나.** 음성은 그림이 필요 없으므로 **파일이 있으면 참**이다.
    private func state(_ fetch: MediaFetch, url: URL?, drawable: Bool) -> MediaTileState {
        switch fetch.state {
        case .here:
            if url == nil { return .absent }        // 판정과 파일이 어긋난 순간(evict 직후 등)
            // ⚠️ **파일이 있는데 그림이 안 나오면 「못 읽는 파일」이다** — 사진은 디코드가 실패하면
            //    **뷰어에서도 못 본다.** 그래서 `.unreadable`(빨강)이지 `.cannotDraw`(앰버)가 아니다.
            //    ⏸ **`.cannotDraw`는 지금 아무도 안 낸다** — **종류가 늘 때** 열린다(PDF·URL·동영상은
            //    **파일은 열리는데 썸네일만** 실패할 수 있다 · 설계 §3-N-3 ㉠).
            return drawable ? .ready : .unreadable
        case .notDownloaded: return .notDownloaded
        case .absent:        return .absent
        }
    }

    /// ★ **네모용 축소본** — 원본을 통째로 디코드하지 않는다 (2026-08-23).
    ///
    /// ⛔ **왜 필요해졌나:** 같은 날 촬영이 **축소를 그만뒀다**(4032×3024). 옛 코드처럼
    /// `PlatformMedia.image(contentsOfFile:)`로 **전체를 디코드해서 62pt 네모에 그리면**
    /// **12MP를 메모리에 펼친 뒤 버리는 꼴**이다. `CGImageSource`의 **썸네일 생성**은 그 일을 안 한다.
    /// ⚠️ **뷰어는 여전히 원본을 쓴다** — 거기서는 **확대하니까** 픽셀이 필요하다.
    static func thumbnail(_ url: URL, side: CGFloat) -> Image? {
        let px = Int(side * 3)          // @3x 기준 — 62pt면 186px
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,      // 방향 반영
            kCGImageSourceThumbnailMaxPixelSize: px,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Image(decorative: cg, scale: 3)
    }

    /// 음성 길이 — 「0:37」. 파일이 없으면 nil.
    /// ⚠️ **로컬 파일에서 바로 읽는다**(`AVAudioPlayer`) — 네트워크·iCloud 대기 없음.
    static func durationText(_ url: URL?) -> String? {
        guard let s = durationSeconds(url) else { return nil }
        let n = Int(s.rounded())
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    /// 초 단위 길이 — 뷰어가 「경과 / 길이」를 그릴 때도 쓴다.
    static func durationSeconds(_ url: URL?) -> TimeInterval? {
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return p.duration
    }
}
