#if os(iOS)
import SwiftUI
import UIKit

//
//  ZoomableImage — **사진 뷰어의 확대/축소** (2026-08-23 신설 · 실기기 판정에서 다시 만들었다)
//
//  ⛔ **손으로 만든 확대를 버렸다.** 옛 꼴은 `scaleEffect` + `offset` + `MagnificationGesture`였고
//     사용자가 실기기에서 셋을 잡았다:
//     ① *"두 번 두드린 **그 위치를 중심으로** 확대되는"* — 옛 꼴은 **늘 화면 한가운데**를 기준으로 했다.
//     ② *"확대 축소가 **부드럽게** 이루어지기 (지금은 순식간에 확대가 퍽! 축소가 퍽!)"* —
//        상태를 바로 바꿔서 **중간이 없었다.**
//     ③ *"축소를 하면 **사진이 화면을 벗어나버리는** 경우도 있음. **뻔하게 재현 가능**할 정도."* —
//        `offset`에 **경계가 없었다.** 확대해서 끌어 둔 자리가 축소 뒤에도 남아 사진이 밖으로 나갔다.
//
//  ★ **셋 다 「직접 만든 것」의 대가였다** — `UIScrollView`의 확대는 **이 셋을 원래부터 한다:**
//    지점 확대(`zoom(to:animated:)`) · 애니메이션 · **경계 제한**(콘텐츠가 밖으로 못 나간다).
//    ⛔ **정교하게 만들기 전에, 그 자리가 필요 없어지는 짜임이 이미 있나 본다** —
//    원칙 목록의 잔상·테두리에서 쓴 그 형태다(`HANDOFF.md` §4 머리).
//
//  ⚠️ **iOS 전용이다.** 맥은 전체 보기(고정)로 남는다 — `UIViewRepresentable`이 iOS 것이다
//    (원칙 목록이 맥에서 `List`로 남은 것과 같은 갈림).
//

/// 확대/축소가 되는 사진 한 장. **두 번 두드리면 그 지점을 중심으로 꽉 채우고, 다시 두드리면 전체 보기다.**
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        let v = ZoomScrollView()
        v.set(image: image)
        return v
    }

    func updateUIView(_ v: ZoomScrollView, context: Context) {}
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var didFirstLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(image: UIImage) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let img = imageView.image, img.size.width > 0, img.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        // **전체 보기 배율**(fit)이 최소, 그 6배가 최대.
        let fit = min(bounds.width / img.size.width, bounds.height / img.size.height)
        if abs(minimumZoomScale - fit) > 0.0001 {
            minimumZoomScale = fit
            maximumZoomScale = fit * 6
        }
        if !didFirstLayout {
            didFirstLayout = true
            zoomScale = fit                     // 열면 전체 보기 — §0 23번
        }
        centerContent()
    }

    /// 사진이 화면보다 작을 때 **가운데로 모은다.** ⛔ 이것이 없으면 왼쪽 위로 붙는다.
    private func centerContent() {
        let w = max(0, (bounds.width - contentSize.width) / 2)
        let h = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: h, left: w, bottom: h, right: w)
    }

    /// **꽉 채우는 배율** — 짧은 변이 화면을 덮는 배율(㉯ · 잘린다).
    private var fillScale: CGFloat {
        guard let img = imageView.image, img.size.width > 0, img.size.height > 0 else { return 1 }
        return max(bounds.width / img.size.width, bounds.height / img.size.height)
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        // 이미 키워 놨으면 **전체 보기로 되돌린다** — 되돌릴 길이 없으면 확대가 함정이 된다.
        if zoomScale > minimumZoomScale * 1.01 {
            setZoomScale(minimumZoomScale, animated: true)     // ★ animated — 「퍽!」이 사라진다
            return
        }
        // ★ **두드린 그 지점을 중심으로** 꽉 채운다.
        let target = max(fillScale, minimumZoomScale * 2)
        let point = g.location(in: imageView)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        zoom(to: rect, animated: true)
    }

    // MARK: UIScrollViewDelegate
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }
}
#endif
