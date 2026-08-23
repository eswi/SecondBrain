import SwiftUI
import SecondBrainCore
import AVFoundation
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

    /// 이 종류의 포인터 필드 이름. ⚠️ **넷은 아직 필드가 없다** — 종류가 늘 때 여기를 채운다.
    var field: String? {
        switch self {
        case .voice: return "audio"
        case .photo: return "photo"
        case .video, .url, .pdf, .other: return nil
        }
    }
}

// MARK: - 네모 하나

/// 네모의 상태 — **§0 20번의 실패 셋**과 「보인다」.
enum MediaTileState {
    case ready                 // 그림(또는 음성 아이콘)이 있다
    case cannotDraw            // ① 자료는 있고 그림만 못 만들었다 — **눌러 들어가면 볼 수 있다**
    case notFetched            // ② 가져오지 못했다 (`notDownloaded`·`absent`를 **하나로** 본다 · §0 21번)
    case unsupported           // ③ 포맷 지원이 안 된다
}

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

    static let side: CGFloat = 62      // §0 6번
    private var side: CGFloat { Self.side }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface2)
            face
            if count > 1 { badge }     // §0 8번 — ⚠️ 지금 데이터에서는 늘 1이라 안 뜬다
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(state == .ready ? Palette.border : Palette.overdue.opacity(0.55)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var face: some View {
        switch state {
        case .ready:       readyFace
        case .cannotDraw:  failFace("hand.tap.fill", "눌러서\n보기", Palette.overdue)
        case .notFetched:  failFace("icloud.and.arrow.down", "아직\n못 받음", Palette.textSecondary)
        case .unsupported: failFace("nosign", "지원\n안 함", Palette.overdue)
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
        case .video, .url, .pdf, .other:
            // ⚠️ 지금 데이터로는 여기 올 일이 없다(포인터가 없다). 종류가 늘 때 채운다.
            Image(systemName: "doc").font(.system(size: side * 0.34))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 실패 셋 — **글자만으로는 62pt에서 안 갈린다.** 아이콘도 함께 가른다(설계 §3-D-6).
    private func failFace(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        VStack(spacing: max(2, side * 0.05)) {
            Image(systemName: kind == .voice ? "waveform" : "photo")
                .font(.system(size: side * 0.26)).foregroundStyle(Palette.textTertiary)
            Image(systemName: symbol).font(.system(size: side * 0.17)).foregroundStyle(tint)
            Text(text).font(.system(size: max(7, side * 0.115)))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                .padding(.horizontal, side * 0.06)
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

/// 자료가 하나도 없을 때 — **점선 네모 하나**(㉮ · §0 10번).
/// ⛔ **추가 경로를 하나로 유지하려는 것이다** — 자료가 있든 없든 「네모를 눌러 뷰어로」가 같다.
/// ⚠️ 살아있는 항목의 **44%가 여기 해당한다**(2026-08-23 실측 46/105 · 설계 §3-H-7).
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
    /// 네모를 눌렀을 때 — **뷰어로 간다**(§0 24~26번). 다음 커밋에서 채운다.
    var onTap: (MediaCardKind) -> Void = { _ in }

    private static let gap: CGFloat = 8        // §0 6번

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보조 자료")                                   // §0 2번 — 사용자가 고른 말
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            tiles
        }
        .padding(14).card()
        .task(id: item.id) {
            if item.fields["audio"] != nil { audioFetch.start(.audio, id: item.id) }
            if item.fields["photo"] != nil { photoFetch.start(.photo, id: item.id) }
        }
    }

    @ViewBuilder private var tiles: some View {
        let kinds = presentKinds
        GeometryReader { geo in
            let need = CGFloat(kinds.count) * MediaTile.side
                + CGFloat(max(0, kinds.count - 1)) * Self.gap
            let overflows = need > geo.size.width + 0.5
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.gap) {
                    if kinds.isEmpty {
                        Button { onTap(.other) } label: { MediaEmptyTile() }
                            .buttonStyle(.plain)
                    }
                    ForEach(kinds) { k in
                        Button { onTap(k) } label: { tile(k) }
                            .buttonStyle(.plain)
                    }
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

    /// 높이를 정하려면 넘치는지 **미리** 알아야 한다(`GeometryReader` 안에서는 늦다).
    /// 폭은 §0 6번의 **342pt**를 쓴다 — 화면 폭 402 − `ScrollView` 16×2 − 카드 14×2.
    private var overflowsNow: Bool {
        let n = presentKinds.count
        guard n > 0 else { return false }
        return CGFloat(n) * MediaTile.side + CGFloat(n - 1) * Self.gap > 342
    }

    /// 0개인 종류는 네모를 안 보인다(§0 7번).
    private var presentKinds: [MediaCardKind] {
        MediaCardKind.allCases.filter { k in
            guard let f = k.field else { return false }
            return item.fields[f] != nil
        }
    }

    @ViewBuilder private func tile(_ k: MediaCardKind) -> some View {
        switch k {
        case .voice:
            MediaTile(kind: .voice, state: state(audioFetch, url: AudioStore.url(forId: item.id)),
                      count: 1, duration: MediaCard.durationText(AudioStore.url(forId: item.id)))
        case .photo:
            let url = PhotoStore.url(forId: item.id)
            let img = url.flatMap { PlatformMedia.image(contentsOfFile: $0.path) }
            MediaTile(kind: .photo,
                      state: img != nil ? .ready : state(photoFetch, url: url),
                      count: 1, image: img,
                      hasPlace: PhotoStore.coordinate(forId: item.id) != nil)
        default:
            MediaTile(kind: k, state: .unsupported, count: 1)
        }
    }

    /// 세 갈래를 **네모의 두 상태로 접는다**(§0 21번) — `notDownloaded`·`absent`는 **하나로**.
    /// ⛔ 「다시 시도」를 안 쓰는 이유가 이것이다: `absent`에서 거짓말이 된다(설계 §3-E-3).
    private func state(_ fetch: MediaFetch, url: URL?) -> MediaTileState {
        switch fetch.state {
        case .here:          return url == nil ? .notFetched : .cannotDraw
        case .notDownloaded: return .notFetched
        case .absent:        return .notFetched
        }
    }

    /// 음성 길이 — 「0:37」. 파일이 없으면 nil.
    /// ⚠️ **로컬 파일에서 바로 읽는다**(`AVAudioPlayer`) — 네트워크·iCloud 대기 없음.
    static func durationText(_ url: URL?) -> String? {
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let s = Int(p.duration.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
