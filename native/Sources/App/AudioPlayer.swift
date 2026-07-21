import Foundation
import AVFoundation

/// 원본 음성 "다시 듣기" 재생 — 상세화면 성역 카드에서 씀. 작은 단일 파일 플레이어.
/// STT의 진실 기준(원본 음성)을 확인하고, 나중 원문 편집에서 "들으며 고치기"의 토대(설계 §4).
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

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
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
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
