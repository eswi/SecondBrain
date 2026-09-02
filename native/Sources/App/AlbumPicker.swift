#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// **아이폰 사진 앨범에서 골라온다 — 여러 장** (2026-09-03 사용자 결정).
/// 자료 추가의 두 번째 길(2026-08-23 · §3-T-1).
///
/// ## ★★ 한 장 → 여러 장 (2026-09-03)
/// 사용자: *"고를 때 복수로 선택하게 하고 [완료] 같은 버튼 누르면 선택한 것 모두 저장되게 할 수 없을까?"*
/// ✅ **선택기가 이미 그 화면을 갖고 있다** — `selectionLimit = 0`이면 **여러 장을 고르고
/// 시스템의 [추가] 단추로 끝낸다.** ⛔ **우리가 화면을 만들지 않았다**(새 문구도 없다).
/// ⛔ **옛 값: `selectionLimit = 1`** — *"⏸ 여러 장은 이번 범위가 아니다"*라 적어 뒀던 자리다.
///
/// ## ⛔ 그리고 그 값이 결함의 원인이었다 — **빠르게 누르면 여러 장이 들어왔다**
/// 사용자: *"사진을 빨리 선택하면 복수로 선택되어 골라져. 즉, 실제로 2장 빠르면 3장이 선택되어
/// 기억으로 들어와."*
/// **한 장 모드는 「누르는 순간」 끝난다** — 닫히는 동안 손가락이 더 닿으면 **콜백이 여러 번** 온다.
/// ✅ **여러 장 모드에서는 누르는 것이 「고르기」일 뿐이라 그 경합이 사라진다.**
/// ✅ **그래도 문을 하나 달았다** — `finished`로 **콜백을 한 번만** 받는다(같은 형태를 다시 안 밟게).
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
    /// 고른 사진들의 **임시 파일**(JPEG) — **고른 순서 그대로.**
    /// ⚠️ **여럿이다**(2026-09-03) — 옛 꼴은 한 장(`(URL) -> Void`)이었다.
    /// 호출부가 확정(`finalizeAdded`)하거나 지운다.
    ///
    /// ⚠️ **`@MainActor`로 못 박는다** — 시스템 콜백이 **메인 밖**에서 오고, 거기서 이 콜로저를
    /// 그대로 건네면 **데이터 경합으로 컴파일이 막힌다**(Swift 6). 메인에 묶여 있으면 건네도 안전하다.
    var onPick: @MainActor ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()          // 라이브러리 접근 없음(사진만 건네받는다)
        config.filter = .images
        // ★★ **0 = 무제한** (2026-09-03 사용자 결정) — 시스템이 **고르기 + [추가]** 화면을 준다.
        //   ⛔ **옛 값 `1`**: *"⏸ 여러 장은 이번 범위가 아니다"* — 그리고 **빠른 탭 결함의 원인**이었다.
        config.selectionLimit = 0
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

        /// **콜백을 한 번만 받는다** — 빠른 탭이 델리게이트를 여러 번 태우던 자리(위 ⛔ 블록).
        private var finished = false

        @MainActor
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            finished = true
            guard !results.isEmpty else { parent.dismiss(); return }   // [취소]로 닫았다
            let providers = results.map(\.itemProvider)
            // ⚠️ **고른 순서를 지킨다** — **하나씩 차례로** 받는다(동시에 받으면 먼저 끝난 것이 앞으로 온다).
            //    ★ **첫째가 카드 네모의 얼굴이 되므로 순서에 뜻이 있다**(`CaptureMediaCard`).
            //    ⛔ **`async`로 묶으려다 되돌렸다** — `NSItemProvider`가 `Sendable`이 아니라
            //    메인 밖으로 넘기는 순간 컴파일이 막힌다(*"sending 'p' risks causing data races"*).
            //    ✅ **콜백 사슬은 이 값을 메인 안에 둔 채로 돈다** — 옛 꼴이 하던 그대로다.
            // ⚠️ **`DismissAction`을 그대로 못 넘긴다** — 함수 타입이 아니다. **감싸서 넘긴다.**
            let dismiss = parent.dismiss
            pickNext(providers, 0, [], onPick: parent.onPick, dismiss: { dismiss() })
        }

        /// **i번째부터 차례로 받아 쌓는다** — 다 받으면 한 번에 넘기고 선택기를 닫는다.
        /// ⚠️ **못 받은 장은 그냥 빠진다**(그물이 둘 다 실패한 경우) — 나머지는 살린다.
        @MainActor
        private func pickNext(_ providers: [NSItemProvider], _ i: Int, _ acc: [URL],
                              onPick: @escaping @MainActor ([URL]) -> Void,
                              dismiss: @escaping @MainActor () -> Void) {
            guard i < providers.count else {
                if !acc.isEmpty { onPick(acc) }
                dismiss()
                return
            }
            let p = providers[i]
            let next: @MainActor (URL?) -> Void = { [weak self] picked in
                self?.pickNext(providers, i + 1, picked.map { acc + [$0] } ?? acc,
                               onPick: onPick, dismiss: dismiss)
            }
            // ⚠️ 콜백은 **메인 밖**에서 온다 — 그래서 「어디로 돌려줄지」를 `Task { @MainActor … }`로 닫는다.
            p.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, err in
                if let url, let kept = Self.keepAsJPEG(url) {
                    Task { @MainActor in next(kept) }
                    return
                }
                // ★ **그물** — JPEG 표현이 없었다. ⛔ 여기까지 왔다는 것은 `.compatible`이
                //   기대대로 안 돈 것이다 — 그래서 남긴다.
                NSLog("[AlbumPicker] jpeg 표현 실패(\(err?.localizedDescription ?? "url=nil")) → 이미지로 다시 청한다")
                p.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { any, err2 in
                    let kept = any.flatMap { Self.keepAsJPEG($0) }
                    if kept == nil {
                        NSLog("[AlbumPicker] 이미지 표현도 실패(\(err2?.localizedDescription ?? "url=nil")) — 붙일 것이 없다")
                    }
                    Task { @MainActor in next(kept) }
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
