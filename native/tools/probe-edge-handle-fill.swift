// native/tools/probe-edge-handle-fill.swift — 화면 녹화에서 손잡이가 지나간 자리마다 「탭 안 바탕색」과 「같은 자리의 첫 프레임 배경색」을 찍는다(비치는 재질인가 판정 · 2026-09-21 설계 §5-14).
// 사용: swift native/tools/probe-edge-handle-fill.swift <mp4> <track.txt(track-edge-handle 출력)>  → "t y fill=r,g,b bg0=r,g,b". 상관이 0이면 불투명. 상태를 안 바꾼다.
import Foundation
import AVFoundation
import CoreVideo
// swift fillprobe.swift <mp4> <track.txt>  — 트랙의 (t, y)마다 탭 안 바탕 패치 색과, 같은 자리의 「탭이 없을 때」 배경색(첫 프레임)을 찍는다
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
var track: [(Double, Double)] = []
for l in try! String(contentsOfFile: a[2], encoding: .utf8).split(separator: "\n") where !l.hasPrefix("#") {
    let p = l.split(separator: " "); if p.count >= 2, let t = Double(p[0]), let y = Double(p[1].split(separator: ",")[0]) { track.append((t, y)) }
}
let sem = DispatchSemaphore(value: 0); var vt: AVAssetTrack?
Task { vt = try? await asset.loadTracks(withMediaType: .video).first; sem.signal() }; sem.wait()
let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: vt!, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out); reader.startReading()
var first: [UInt8]? = nil; var W = 0, H = 0, BPR = 0
func patch(_ base: UnsafePointer<UInt8>, _ bpr: Int, _ w: Int, _ cy: Int) -> (Int, Int, Int) {
    var r = 0, g = 0, b = 0, n = 0
    for y in (cy - 34)...(cy - 24) { for x in (w - 14)...(w - 4) { let p = base + y*bpr + x*4; b += Int(p[0]); g += Int(p[1]); r += Int(p[2]); n += 1 } }
    return (r/n, g/n, b/n)
}
var i = 0
while let sb = out.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds * 1000
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    if first == nil { first = Array(UnsafeBufferPointer(start: base, count: bpr*h)); W = w; H = h; BPR = bpr }
    while i < track.count && track[i].0 < t - 1 { i += 1 }
    if i < track.count, abs(track[i].0 - t) < 1 {
        let cy = Int(track[i].1)
        if cy > 60 && cy < h - 60 {
            let f = patch(base, bpr, w, cy)
            let bg = first!.withUnsafeBufferPointer { patch($0.baseAddress!, BPR, W, cy) }
            print(String(format: "%.0f %d fill=%d,%d,%d bg0=%d,%d,%d", t, cy, f.0, f.1, f.2, bg.0, bg.1, bg.2))
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
}
