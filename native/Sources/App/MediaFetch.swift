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

    /// **「안 온 것으로 본다」 문턱.** ✅ **쟀다 (2026-08-20 · 맥미니 · 표본 16개):**
    /// 다운로드 실측 **526~924ms**(중앙 604 · 평균 654) — 이 문턱의 **6%**밖에 안 쓰인다.
    ///
    /// **그래도 15초를 유지한다**(사용자 결정 2026-08-20): 이건 「아직 못 받았어요」를 띄우는 **문턱**이라
    /// 넉넉함이 비용이 아니다(틀린 상태를 조금 더 보여주는 것뿐). 그리고 **줄일 근거가 없다** —
    /// **안 잰 조건이 셋이다: 셀룰러 · 느린 Wi-Fi · 1MB보다 큰 파일**(표본 최대 1,083,603B).
    /// 회선은 유선 2500Base-T · 다운 850.7Mbps 하나만 쟀다. 전말: `docs/worklog/2026-08-20-macmini.md` §2.
    private static let waitSeconds: Double = 15

    /// ### ★ 실측이 드러낸 것 — **진짜 문제는 이 값이었다**
    ///
    /// 「15초가 맞나」를 재려고 표본을 받았는데, **15초는 6%만 쓰이고 있었고 체감 지연은 여기서 나왔다.**
    /// 옛 값은 **1초**였다 — 다운로드가 **0.53~0.92초**에 끝나는데 **화면은 1.0초(첫 폴링)에야 안다.**
    /// 빠르면 **0.5초를 그냥 기다리는** 셈이었다.
    ///
    /// **0.2초로 줄였다**(사용자 결정 2026-08-20). 실측 최소값(526ms)보다 촘촘해서
    /// **가장 빠른 경우도 폴링이 가려지지 않는다.**
    ///
    /// ⚠️ **자료 확장 ②(PDF·동영상) 때 둘 다 다시 잰다** — 지금 지배하는 것은 **크기가 아니라 왕복**이다
    /// (피어슨 r=−0.364 · `118218B=526ms` vs `118227B=924ms`). 그 관계가 큰 파일에서도 같을 보장이 없다.
    private static let pollSeconds: Double = 0.2

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

            for _ in 0..<Int((Self.waitSeconds / Self.pollSeconds).rounded()) {
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
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
    ///
    /// ## ★ 들여오기가 여기서 일어난다 (§2-A C안 · 2026-08-20)
    ///
    /// **판정 전에 `adoptFromCloudIfNeeded`를 부른다** — iCloud에 바이트가 있으면 **로컬로 옮긴다.**
    /// 그래서 화면이 `url(forId:)`를 부를 때는 **이미 로컬 파일이 있고, 스코프 밖에서 읽는 일이 없다.**
    ///
    /// **왜 화면이 아니라 여기인가:** `url(forId:)`는 **뷰 본문에서** 불린다(`DetailView.audioRow`).
    /// 거기서 복사하면 **메인 스레드에서 파일 I/O**를 하는 것이고, 뷰 본문은 여러 번 재평가된다.
    /// 여기는 이미 `Task.detached`라 **메인 밖**이고, 상태를 발행하기 **전**이라 순서도 맞다.
    ///
    /// **폰에서는 비용이 0이다** — 로컬에 이미 있으면 `adoptFromCloudIfNeeded`가 iCloud를 아예 안 본다(§5).
    private static func availability(_ kind: MediaKind, _ id: String) async -> MediaAvailability {
        await Task.detached(priority: .userInitiated) {
            switch kind {
            case .audio:
                AudioStore.adoptFromCloudIfNeeded(forId: id)
                return AudioStore.availability(forId: id)
            case .photo:
                PhotoStore.adoptFromCloudIfNeeded(forId: id)
                return PhotoStore.availability(forId: id)
            }
        }.value
    }
}
