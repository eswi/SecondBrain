// native/tools/track-edge-handle.swift — 화면 녹화(mp4)에서 가장자리 손잡이(화살표 `<`)의 세로 위치를 프레임마다 읽는다(2026-09-21 · 설계 edge-handle-design.md §5-4·§5-12).
// 사용: swift native/tools/track-edge-handle.swift <mp4>  → "t(ms) y1,y2,…"(후보 전부 · 여럿이면 연속성으로 갈라 읽는다) · 못 찾으면 -. 상태를 안 바꾼다.
// 판정 = 밝은 회색 `<`(채도 낮음) + 그 오른쪽 어두운 바탕. ⚠️ 첫 판(회색 띠 높이)은 하단 독을 손잡이로 읽었다. 손잡이 꼴이 바뀌면 문턱도 본다.

// 사용법: swift track.swift <mp4>  → 각 프레임: t(ms) centerY(px) top bottom  (못 찾으면 -1)
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
Task { track = try? await asset.loadTracks(withMediaType: .video).first; sem.signal() }
sem.wait()
guard let track else { print("no video track"); exit(1) }
let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
out.alwaysCopiesSampleData = false
reader.add(out); reader.startReading()
var fps: Float = 0
let sem2 = DispatchSemaphore(value: 0)
Task { fps = (try? await track.load(.nominalFrameRate)) ?? 0; sem2.signal() }; sem2.wait()
print("# fps \(fps)")
while let sb = out.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    // 화살표 판정: x∈[w-54, w-18]에 밝은 회색(lum>170 · 채도<30) 픽셀이 있고, 그 오른쫙 x=w-6·w-12는 어두운 바탕(lum<115)
    func lumsat(_ x: Int, _ y: Int) -> (Int, Int) {
        let p = base + y*bpr + x*4
        let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
        return ((299*r + 587*g + 114*b)/1000, max(r,g,b) - min(r,g,b))
    }
    func isChevronRow(_ y: Int) -> Bool {
        let (l1,_) = lumsat(w-6, y), (l2,_) = lumsat(w-12, y)
        guard l1 < 115, l2 < 115 else { return false }
        var x = w-54
        while x <= w-18 { let (l,sat) = lumsat(x, y); if l > 170 && sat < 30 { return true }; x += 2 }
        return false
    }
    var found: [(Int,Int)] = []
    var y = 0
    while y < h {
        if isChevronRow(y) {
            let y0 = y; var gap = 0; var last = y
            while y < h && gap < 6 { if isChevronRow(y) { last = y; gap = 0 } else { gap += 1 }; y += 1 }
            let len = last - y0 + 1
            if len >= 55 && len <= 110 { found.append((y0, last)) }
        } else { y += 1 }
    }
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    let cs = found.map { String(format: "%.1f", Double($0.0+$0.1)/2) }.joined(separator: ",")
    print(String(format: "%.1f ", t*1000) + (cs.isEmpty ? "-" : cs))
}
