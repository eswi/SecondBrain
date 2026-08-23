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
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// 재생/정지 토글. 재생 중이면 멈추고, 아니면 url을 처음부터 재생.
    func toggle(url: URL) {
        if isPlaying { stop(); return }
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
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let p = self.player, p.duration > 0 else { return }
                    self.progress = p.currentTime / p.duration
                }
            }
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
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
