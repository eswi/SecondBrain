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
///
/// ## ⛔⛔ 2026-09-03에 여기서 깨져 있었다 — **골라도 아무것도 안 붙었다**
/// 사용자: *"앨범까지 가서 골라도 반영이 안 돼! 사진 클릭하면 바로 나오는데 골라지지 않아."*
///
/// **원인은 설정 한 줄과 요청 한 줄이 서로 어긋난 것이다:**
/// `preferredAssetRepresentationMode`가 **`.current`**(=원본 형식 그대로, 변환하지 말라)인데
/// **`public.jpeg`를 달라고** 했다. **아이폰 사진은 HEIC**라서 그 표현이 **등록되어 있지 않고**,
/// `loadFileRepresentation`이 **`nil`을 준다** → 붙는 것 없이 **선택기만 닫힌다.**
/// ⛔ **위 문단의 *"원본이 HEIC면 시스템이 변환해 준다"*는 `.compatible`에서만 참이었다** —
/// **문장은 맞았고 설정이 달랐다.** 그래서 주석을 읽어도 안 보였다.
/// ✅ **고친 것 둘:** ① **`.compatible`**로 바꿨다(시스템이 JPEG로 변환해 준다 · EXIF는 살아 온다)
/// ② **JPEG가 없으면 아무 이미지로 받아 우리가 JPEG로 옮긴다**(`PhotoStore.transcodeToJPEG`).
/// ⚠️ **②는 그물이다** — ①로 충분해야 하지만, **빈손으로 조용히 닫히는 것이 이 결함의 모습**이었으므로
/// **한 겹 더 둔다.** ⛔ **오류를 삼키지 말 것** — 옛 코드는 `loadFileRepresentation`의 error를
/// **`_`로 버려** 무엇이 왜 안 됐는지 남지 않았다.
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
        // ★★ **`.compatible`이어야 JPEG로 받아올 수 있다** (2026-09-03에 고쳤다 — 머리주석 참조).
        //   ⛔ **옛 값(깨져 있었다): `.current`** — *"원본 형식 그대로, 변환하지 말라"*는 뜻이라
        //   **HEIC 사진에 `public.jpeg` 표현이 없었다.**
        //   ⚠️ **`.compatible`은 변환을 시스템에 맡긴다** — **우리가 굽는 것이 아니다**(EXIF가 살아 온다).
        //   ⚠️ **그 변환의 품질은 못 쟀다**(시스템이 정한다 · 위 머리주석과 같은 이야기).
        config.preferredAssetRepresentationMode = .compatible
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
            provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, err in
                if let url, let picked = Self.keepAsJPEG(url) {
                    Task { @MainActor in finish(picked) }
                    return
                }
                // ★ **그물** — JPEG 표현이 없었다. **아무 이미지로 받아 우리가 JPEG로 옮긴다.**
                //   ⛔ 여기까지 왔다는 것은 `.compatible`이 기대대로 안 돈 것이다 — 그래서 남긴다.
                NSLog("[AlbumPicker] jpeg 표현 실패(\(err?.localizedDescription ?? "url=nil")) → 이미지로 다시 청한다")
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { any, err2 in
                    let picked = any.flatMap { Self.keepAsJPEG($0) }
                    if picked == nil {
                        NSLog("[AlbumPicker] 이미지 표현도 실패(\(err2?.localizedDescription ?? "url=nil")) — 붙일 것이 없다")
                    }
                    Task { @MainActor in finish(picked) }
                }
            }
        }

        /// **시스템이 준 임시 파일을 우리 임시 폴더의 `.jpg`로 옮긴다.**
        /// ⚠️ **시스템 임시 파일은 콜백이 끝나면 사라진다** — 그래서 **콜백 안에서** 불러야 한다.
        /// **JPEG면 그대로 복사**(다시 굽지 않는다) · **아니면 JPEG로 옮긴다**(EXIF는 함께 간다).
        nonisolated static func keepAsJPEG(_ src: URL) -> URL? {
            let dest = PhotoStore.newTempURL(sessionId: UUID().uuidString)
            try? FileManager.default.removeItem(at: dest)
            if src.pathExtension.lowercased() == "jpg" || src.pathExtension.lowercased() == "jpeg" {
                return (try? FileManager.default.copyItem(at: src, to: dest)) != nil ? dest : nil
            }
            return PhotoStore.transcodeToJPEG(from: src, to: dest) ? dest : nil
        }
    }
}
#endif
