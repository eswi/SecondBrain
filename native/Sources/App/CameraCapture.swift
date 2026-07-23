#if os(iOS)
import SwiftUI
import UIKit

/// 카메라 촬영 래퍼 — 한 장 찍어 `UIImage`를 돌려준다(앨범 선택 없음 — 설계
/// `docs/native/photo-capture-design.md` §4). `.fullScreenCover`로 띄운다.
struct CameraCapture: UIViewControllerRepresentable {
    /// 촬영 성공 시 원본 이미지 콜백(호출부가 리사이즈·압축·임시저장을 담당).
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
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
