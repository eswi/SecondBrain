#if os(iOS)
import SwiftUI
import UIKit

/// **카메라를 세로로 못 박는다** — 2026-08-24 사용자 결정.
///
/// ## 무엇이 문제였나 (2026-08-23 실기기 · 사용자 스크린샷 둘)
/// 폰을 **가로로 돌려 찍으면 화면이 깨진다** — 앱 창은 가로로 도는데 **카메라 화면은 세로 배치 그대로**
/// 그려져서, 미리보기가 띠로 눌리고 줌 라벨(.5/1/2/5)이 **세로로 쌓인다.**
/// **원인:** `project.yml`에 방향 키가 **아예 없어** iOS 기본값(세로+가로)이 적용된다.
///
/// ✅ **찍힌 사진은 정상이었다** — 쟀다: 가로로 찍은 것이 **4032×3024**, 세로는 3024×4032
/// (`normalized`가 방향을 픽셀로 굽는다). **깨지는 것은 찍는 동안의 화면뿐이다.**
///
/// ⛔ **앱 전체를 세로로 묶지 않는다**(사용자 결정) — 카메라만이다. 사진 뷰어를 가로로 보는 길은 남는다.
///
/// ⚠️ **이 오버라이드가 실제로 먹는지는 실기기에서 봐야 한다** — SwiftUI `fullScreenCover`가 띄우는 것은
/// **호스팅 컨트롤러**이고 이 picker는 그 **자식**이라, iOS가 자식에게 방향을 묻지 않을 수 있다.
/// 안 먹으면 다음 수단은 **앱 델리게이트에서 방향을 잠그는 것**(카메라가 열려 있는 동안만)이다.
final class PortraitImagePicker: UIImagePickerController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
}

/// 카메라 촬영 래퍼 — 한 장 찍어 `UIImage`를 돌려준다(앨범 선택 없음 — 설계
/// `docs/native/photo-capture-design.md` §4). `.fullScreenCover`로 띄운다.
struct CameraCapture: UIViewControllerRepresentable {
    /// 촬영 성공 시 원본 이미지 콜백(호출부가 리사이즈·압축·임시저장을 담당).
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = PortraitImagePicker()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onCapture(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
