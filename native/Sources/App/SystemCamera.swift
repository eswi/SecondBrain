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
    /// 취소하면 콜백이 오지 않는다.
    static func present(onImage: @escaping (UIImage) -> Void) {
        guard isAvailable, let top = topMost() else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // ⚠️ delegate는 **weak**다 — 붙잡지 않으면 바로 사라져 콜백이 안 온다.
        let delegate = Delegate(onImage: onImage)
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
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            finish(picker)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(picker)
        }

        private func finish(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            SystemCamera.retained = nil
        }
    }
}
#endif
