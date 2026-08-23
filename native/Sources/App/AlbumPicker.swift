#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// **아이폰 사진 앨범에서 한 장 골라온다** — 자료 추가의 두 번째 길(2026-08-23 사용자 결정 · §3-T-1).
///
/// ## ★ 권한 문구가 필요 없다 (`PHPickerViewController`)
/// 이 선택기는 **앱 밖(별도 프로세스)에서** 돌고 **고른 것만** 앱에 건네준다.
/// 그래서 `NSPhotoLibraryUsageDescription`이 **필요 없고**, 앱은 앨범 전체를 볼 권한을 갖지 않는다.
/// ⛔ **옛 `UIImagePickerController(.photoLibrary)`를 쓰면 권한이 필요하다** — 그래서 그쪽을 안 쓴다.
/// ★ **수집 화면은 여전히 카메라 전용이다**(`photo-capture-design.md` §4 · §3-T-1) —
/// 뒤집힌 것은 **자료 카드의 `+`에서만**이다.
///
/// ## 파일을 그대로 받아온다 — **다시 굽지 않는다**
/// `UIImage`로 받으면 **EXIF(촬영 위치·시각)가 사라지고 다시 인코딩**해야 한다.
/// 그래서 **JPEG 표현을 파일로** 달라고 한다 — 원본이 HEIC면 **시스템이 변환**해 준다.
/// ⚠️ **그 변환의 품질은 못 쟀다**(시스템이 정한다). 우리가 굽는 자리가 아니라 **깎을 값을 못 정한다.**
/// ⚠️ **시스템이 준 임시 파일은 콜백이 끝나면 사라진다** — 그래서 **우리 임시 폴더로 복사**한다.
struct AlbumPicker: UIViewControllerRepresentable {
    /// 고른 사진의 **임시 파일**(JPEG). 호출부가 확정(`finalizeAdded`)하거나 지운다.
    ///
    /// ⚠️ **`@MainActor`로 못 박는다** — 시스템 콜백이 **메인 밖**에서 오고, 거기서 이 콜로저를
    /// 그대로 건네면 **데이터 경합으로 컴파일이 막힌다**(Swift 6). 메인에 묶여 있으면 건네도 안전하다.
    var onPick: @MainActor (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()          // 라이브러리 접근 없음(사진만 건네받는다)
        config.filter = .images
        config.selectionLimit = 1                     // ⏸ 여러 장은 이번 범위가 아니다(사진 추가만)
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: AlbumPicker
        init(_ parent: AlbumPicker) { self.parent = parent }

        @MainActor
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.dismiss(); return
            }
            let finish: @MainActor (URL?) -> Void = { [onPick = parent.onPick,
                                                       dismiss = parent.dismiss] picked in
                if let picked { onPick(picked) }
                dismiss()
            }
            // ⚠️ 콜백은 **메인 밖**에서 온다 — 그래서 「어디로 돌려줄지」를 `Task { @MainActor … }`로 닫는다
            //    (콜로저를 그대로 다른 스레드에 넘기면 데이터 경합으로 컴파일이 막힌다).
            provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, _ in
                // 시스템이 준 임시 파일은 **이 콜백이 끝나면 사라진다** → 우리 임시 폴더로 복사한다.
                var copied: URL?
                if let url {
                    let dest = PhotoStore.newTempURL(sessionId: UUID().uuidString)
                    try? FileManager.default.removeItem(at: dest)
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { copied = dest }
                }
                let picked = copied
                Task { @MainActor in finish(picked) }
            }
        }
    }
}
#endif
