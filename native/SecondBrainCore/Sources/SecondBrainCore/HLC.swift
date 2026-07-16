import Foundation

/// Hybrid Logical Clock. 이벤트 전순서 기준(설계 §2).
/// 키 = (wallMillis, counter, deviceId) 사전식 → 무승부 없는 완전한 전순서.
public struct HLC: Comparable, Hashable, Sendable {
    public var wallMillis: Int64
    public var counter: Int
    public var deviceId: String

    public init(wallMillis: Int64, counter: Int, deviceId: String) {
        self.wallMillis = wallMillis
        self.counter = counter
        self.deviceId = deviceId
    }

    public static func < (a: HLC, b: HLC) -> Bool {
        if a.wallMillis != b.wallMillis { return a.wallMillis < b.wallMillis }
        if a.counter != b.counter { return a.counter < b.counter }
        return a.deviceId < b.deviceId
    }

    /// 파일 직렬화용: "<wall>.<counter>.<deviceId>"
    public var serialized: String { "\(wallMillis).\(counter).\(deviceId)" }

    public init?(serialized s: String) {
        // deviceId에 '.'이 있을 수 있으니 앞 두 조각만 split
        let parts = s.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let w = Int64(parts[0]), let c = Int(parts[1]) else { return nil }
        self.init(wallMillis: w, counter: c, deviceId: String(parts[2]))
    }
}

/// HLC 발급기(쓰기·동기화 경로). 한 기기당 하나. 값 타입.
public struct HLCClock: Sendable {
    public let deviceId: String
    public private(set) var last: HLC

    public init(deviceId: String, last: HLC? = nil) {
        self.deviceId = deviceId
        self.last = last ?? HLC(wallMillis: 0, counter: 0, deviceId: deviceId)
    }

    /// 새 이벤트에 찍을 HLC 발급.
    public mutating func send(now: Int64) -> HLC {
        let w = max(last.wallMillis, now)
        let c = (w == last.wallMillis) ? last.counter + 1 : 0
        last = HLC(wallMillis: w, counter: c, deviceId: deviceId)
        return last
    }

    /// 원격 이벤트를 관찰하며 로컬 시계를 끌어올림(인과성). 표준 HLC receive.
    public mutating func receive(_ remote: HLC, now: Int64) {
        let w = max(max(last.wallMillis, remote.wallMillis), now)
        let c: Int
        if w == last.wallMillis && w == remote.wallMillis {
            c = max(last.counter, remote.counter) + 1
        } else if w == last.wallMillis {
            c = last.counter + 1
        } else if w == remote.wallMillis {
            c = remote.counter + 1
        } else {
            c = 0
        }
        last = HLC(wallMillis: w, counter: c, deviceId: deviceId)
    }
}
