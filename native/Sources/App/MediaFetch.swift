import Foundation
import SecondBrainCore

/// **자료 하나를 받아오는 동안의 상태** — 설계 `media-icloud-design.md` §6.
///
/// **텍스트와 같은 API(`startDownloadingUbiquitousItem`), 다른 시점이다:**
/// 텍스트는 **앱 시작할 때 `inbox*.md` 전부**(5개·79KB — 다 받아도 싸다),
/// 자료는 **상세를 열 때 그 항목 것 하나만**(131개 — 다 받으면 「실체는 클라우드」가 무너진다).
///
/// ⚠️ **폰에서는 이 화면이 사실상 안 나온다** — 로컬 사본이 남아 있어(§5) 항상 「여기 있다」다.
/// **그 상태를 실제로 만나는 것은 Mac이고, 검증도 거기서 한다**(§10).
@MainActor
final class MediaFetch: ObservableObject {
    @Published private(set) var state: MediaAvailability = .here
    /// 기다렸는데 안 왔다 → 「아직 못 받았어요 · 다시 시도」.
    @Published private(set) var timedOut = false

    private var task: Task<Void, Never>?

    /// ⚠️ **잰 값이 아니다.** 「얼마나 기다려야 안 오는 것으로 보나」는 실기기에서 안 재봤다 —
    /// iCloud 다운로드 시간은 파일 크기·회선에 달렸고 이 기기 조합에서 측정한 적이 없다.
    /// 실측 뒤 조정할 값이다(2026-08-19).
    private static let waitSeconds = 15

    /// 상세가 열릴 때 시작. 이미 있으면 아무 일도 안 하고, 안 받았으면 **받기 시작하고 기다린다.**
    func start(_ kind: MediaKind, id: String) {
        task?.cancel()
        timedOut = false
        task = Task { [weak self] in
            guard let self else { return }
            var s = await Self.availability(kind, id)
            self.state = s
            guard s == .notDownloaded else { return }

            _ = await Task.detached(priority: .userInitiated) {
                MediaCloud.startDownload(kind, id: id)
            }.value

            for _ in 0..<Self.waitSeconds {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                s = await Self.availability(kind, id)
                self.state = s
                if s != .notDownloaded { return }     // 왔다 — 또는 사라졌다
            }
            self.timedOut = true
        }
    }

    /// 「다시 시도」.
    func retry(_ kind: MediaKind, id: String) { start(kind, id: id) }

    /// 판정은 저장소가 한다(로컬 → iCloud). **메인 밖에서** 잰다 — iCloud 쪽은 스코프를 열어야 보인다.
    private static func availability(_ kind: MediaKind, _ id: String) async -> MediaAvailability {
        await Task.detached(priority: .userInitiated) {
            switch kind {
            case .audio: return AudioStore.availability(forId: id)
            case .photo: return PhotoStore.availability(forId: id)
            }
        }.value
    }
}
