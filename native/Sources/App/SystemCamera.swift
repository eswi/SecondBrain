#if os(iOS)
import SwiftUI
import UIKit

/// **시스템 카메라를 모달로 띄운다** — 두 입구(수집 화면 · 자료 추가)가 이 하나를 쓴다.
///
/// ## ⛔ 왜 `UIViewControllerRepresentable` + `fullScreenCover`를 버렸나 (2026-08-24)
/// 옛 코드(`CameraCapture`)는 picker를 **SwiftUI 커버의 뿌리로 넣었다 = 임베드**다.
/// **카메라 picker는 모달로 띄워야 하는 것**이고, 임베드하면 **자기 레이아웃을 못 잡는다.**
///
/// **증상(2026-08-23 실기기 · 사용자 스크린샷 둘):** 폰을 **가로로 돌리면 미리보기가 띠로 눌려**
/// 사용자 판정 — *"카메라로 보이는 부분이 너무 축소되어서 **촬영 자체가 불가능**해."*
/// 줌 라벨(.5/1/2/5)이 **세로로 쌓여** 있었다 = 컨트롤은 세로 배치인데 창만 가로.
///
/// ⚠️ **처음엔 「카메라만 세로 고정」으로 갔다가 되돌렸다**(2026-08-24) —
/// **그것은 증상을 덮는 쪽이었고, 원인은 「띄우는 방식」이었다.** 사용자 지시: *"가로모드에서도 잘 되도록 고치자."*
/// ⛔ **`PortraitImagePicker`(세로 고정 서브클래스)도 함께 지웠다** — 원인을 고치면 필요 없다.
///
/// ✅ **찍히는 사진은 처음부터 정상이었다 — 쟀다:** 가로 **4032×3024** / 세로 3024×4032
/// (`PhotoStore.normalized`가 방향을 픽셀로 굽는다). **깨진 것은 찍는 동안의 화면뿐이었다.**
@MainActor
enum SystemCamera {

    /// 이 기기에 카메라가 있나(시뮬레이터에는 없다).
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// 카메라를 띄운다. 찍으면 **원본 `UIImage`**를 넘긴다(리사이즈·압축·임시저장은 부르는 쪽이 한다).
    /// 찍지 않고 취소하면 `onImage`는 **오지 않는다.**
    ///
    /// ## ⛔⛔ 연달아 찍기 — **만들었다가 되돌렸다** (2026-09-03 · 지우지 않고 적어 둔다)
    /// **사용자가 제안했다:** *"사진을 찍을 때에도 여러개 찍은 후 한꺼번에 저장 어떨까?"*
    /// **그리고 같은 날 사용자가 되돌렸다:** *"사진찍기는 연속으로 하지 말자. 생소하다.
    /// 여러장 고르는 것은 앨범에서만 하고 사진찍기는 원래처럼 한장만 찍기."*
    /// ⛔ **되살리지 말 것 — 이유가 「안 됐다」가 아니라 「생소하다」다.** 고쳐서 될 종류가 아니다.
    ///
    /// **밟은 길 둘(둘 다 실패):** ① **안 닫고 버티기** — 안 닫아도 화면은 닫혔다(우리가 아닌 쪽이 닫았다) ·
    /// ② **닫힘이 끝난 뒤 다시 띄우기** — 동작은 했지만 **장 사이에 닫힘·열림이 한 번씩 보였다.**
    ///
    /// ✅ **남은 것 하나 — 「여럿」은 앨범이 맡는다**(`AlbumPicker` · `selectionLimit = 0`).
    /// ⛔ **「한꺼번에 저장」은 원래 되고 있었다** — 찍은 것이 카드에 쌓이고
    /// **[저장 후 편집하기]가 한 번에 붙인다**(`CaptureSheet.save`). **그쪽은 아무것도 안 바꿨다.**
    ///
    /// ## ⛔ 그래도 **셔터를 두 번 받지 않는다** (`done` · 2026-09-03에 남겼다)
    /// **연달아 찍기와 무관한 결함이었다** — 콜백이 두 번 오면 `present`/`dismiss`가 겹쳐
    /// **보이지 않는 화면이 얹힌 채로** 남는다. 사용자: *"빠르게 촬영 버튼 두번 눌렀더니
    /// 앱이 멈춰버려. 뭘 눌러도 반응이 없게 돼."*
    /// ★ **앨범의 「빠른 탭」과 같은 형태다**(`AlbumPicker.finished`) — **같은 날 두 자리에서 났다.**
    /// ⛔ **연달아 찍기를 되돌릴 때 이 문을 함께 걷어내지 말 것.**
    ///
    /// - Parameter onFinish: **찍든 취소하든 · 아예 못 띄우든 반드시 한 번** 불린다.
    ///   ★ **왜 있나 (2026-08-30):** 이 picker는 **`.fullScreen` 모달**이라, 뜨는 순간 밑에 있는
    ///   SwiftUI 시트의 **`onDisappear`가 불리고** 닫힐 때 **`onAppear`가 다시 불린다.**
    ///   부르는 쪽이 그 둘을 「시트가 끝났다」로 읽으면 **수집 내용을 지운다**(실제로 그랬다 —
    ///   `CaptureSheet`의 ⛔ 블록). 그래서 **「카메라가 덮고 있다」를 부르는 쪽이 알아야** 하고,
    ///   이 콜백이 그 구간의 **끝**을 알린다.
    ///   ⛔ **못 띄운 경우(카메라 없음·최상위 VC 없음)에도 부른다** — 안 부르면 부르는 쪽 표시가
    ///   `true`로 남아 정리가 영영 안 돈다(임시 파일이 샌다).
    static func present(onImage: @escaping (UIImage) -> Void,
                        onFinish: (() -> Void)? = nil) {
        guard isAvailable, let top = topMost() else { onFinish?(); return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // ⚠️ delegate는 **weak**다 — 붙잡지 않으면 바로 사라져 콜백이 안 온다.
        let delegate = Delegate(onImage: onImage, onFinish: onFinish)
        retained = delegate
        picker.delegate = delegate
        top.present(picker, animated: true)
    }

    /// 살아 있게 붙잡아 두는 자리(위 ⚠️). 끝나면 놓는다.
    private static var retained: Delegate?

    private static func topMost() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard var vc = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else {
            return nil
        }
        while let presented = vc.presentedViewController { vc = presented }
        return vc
    }

    private final class Delegate: NSObject, UIImagePickerControllerDelegate,
                                  UINavigationControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let onFinish: (() -> Void)?
        init(onImage: @escaping (UIImage) -> Void, onFinish: (() -> Void)?) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        /// **콜백을 한 번만 받는다** — 셔터를 두 번 누르면 `present`/`dismiss`가 겹쳐
        /// **앱이 멈춘 것처럼 된다**(2026-09-03 폰에서 났다 · 머리주석 ⛔ 블록).
        private var done = false

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !done else { return }         // ★ 셔터를 두 번 받지 않는다(머리주석 ⛔ 블록)
            done = true
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            finish(picker)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !done else { return }
            done = true
            finish(picker)
        }

        private func finish(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            SystemCamera.retained = nil
            // ⚠️ **닫기 애니메이션이 끝나기 전에 부른다** — 그래야 뒤이어 오는 시트의 `onAppear`보다
            //    먼저 도착해 「카메라가 덮고 있다」 표시가 내려간다(순서가 뒤바뀌면 정리가 헛돈다).
            onFinish?()
        }
    }
}
#endif
