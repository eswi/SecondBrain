import Foundation
import AVFoundation

/// 원본 음성 "다시 듣기" 재생 — 상세화면 성역 카드에서 씀. 작은 단일 파일 플레이어.
/// STT의 진실 기준(원본 음성)을 확인하고, 나중 원문 편집에서 "들으며 고치기"의 토대(설계 §4).
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    /// ★ **2026-08-23 추가 — 뷰어의 진행 막대**(설계 §0 23번의 「음성 재생기」).
    /// 카드의 네모는 **길이만** 보이고(§0 11번), **진행은 뷰어의 것**이다.
    @Published private(set) var progress: Double = 0      // 0…1
    @Published private(set) var duration: TimeInterval = 0
    /// ★ **2026-08-23 — 경과 시간**(실기기에서 사용자가 잡았다: *"진행 시간은 변동이 없네"*).
    /// 옛 꼴은 **길이만** 보였다 — 막대는 움직이는데 숫자가 안 변해서 **멈춘 것처럼 보였다.**
    @Published private(set) var currentTime: TimeInterval = 0
    /// **멈춰 있지만 자리를 지키고 있나** — `stop()`과 다르다(아래 `pause()` 주석).
    @Published private(set) var isPaused = false
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// **재생 / 일시정지 / 이어듣기** (2026-08-23 · 실기기 판정에서 바뀌었다).
    ///
    /// ⛔ **옛 꼴은 「정지」였다** — 누르면 `stop()`이라 **자리가 0으로 돌아갔다.**
    /// 사용자: *"정지는 완전 Stop이야. **Pause 형태가 되었으면** 좋겠어."*
    /// → **재생 중이면 멈추고 자리를 지킨다. 다시 누르면 그 자리에서 이어 듣는다.**
    func toggle(url: URL) {
        if isPlaying { pause(); return }
        if isPaused, let p = player { p.play(); isPlaying = true; isPaused = false; startTicker(); return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            guard p.play() else { return }
            player = p
            duration = p.duration
            progress = 0
            isPlaying = true
            // 0.2초마다 진행을 올린다 — 폴링 값은 `MediaFetch.pollSeconds`와 같은 결(§6).
            isPaused = false
            startTicker()
        } catch {
            isPlaying = false
        }
    }

    /// 0.2초마다 진행·경과를 올린다.
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.currentTime = p.currentTime
                self.progress = p.currentTime / p.duration
            }
        }
    }

    /// **일시정지** — 자리를 지킨다. ⛔ `stop()`과 다르다: 저쪽은 **플레이어를 버리고 0으로 되돌린다.**
    func pause() {
        ticker?.invalidate(); ticker = nil
        player?.pause()
        isPlaying = false
        isPaused = true
    }

    /// **자리 옮기기** — 막대를 끌어 그 지점부터 듣는다(0…1).
    /// ⚠️ **멈춰 있을 때도 옮길 수 있다** — 옮기고 나서 재생을 누르면 그 자리에서 시작한다.
    func seek(toFraction f: Double) {
        guard let p = player, p.duration > 0 else { return }
        let t = min(max(f, 0), 1) * p.duration
        p.currentTime = t
        currentTime = t
        progress = t / p.duration
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        isPaused = false
        progress = 0
        currentTime = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
