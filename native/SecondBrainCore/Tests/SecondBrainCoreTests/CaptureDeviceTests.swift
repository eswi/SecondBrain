import XCTest
@testable import SecondBrainCore

/// 최초 수집 기기 역산 (edit-policy.md §7).
final class CaptureDeviceTests: XCTestCase {

    // 1) 레거시 + 음성 → iPhone 16 Pro
    func testLegacyVoice_iPhone() {
        XCTAssertEqual(
            CaptureDevice.label(source: "voice", createdDeviceId: "legacy"),
            "iPhone 16 Pro")
    }

    // 2) 레거시 + 그 외(web/image/doc…) → MacBook Pro
    func testLegacyNonVoice_MacBook() {
        for s in ["web", "image", "doc", "mail", "chat", "meeting"] {
            XCTAssertEqual(
                CaptureDevice.label(source: s, createdDeviceId: "legacy"),
                "MacBook Pro", "레거시 비음성(\(s))은 MacBook Pro")
        }
    }

    // 3) 레거시 + source nil → MacBook Pro (음성 아님)
    func testLegacyNilSource_MacBook() {
        XCTAssertEqual(
            CaptureDevice.label(source: nil, createdDeviceId: "legacy"),
            "MacBook Pro")
    }

    // 4) 네이티브: create 때 찍은 device(성역) 그대로 — 역산 안 함
    func testNative_usesStoredDevice() {
        XCTAssertEqual(
            CaptureDevice.label(source: "voice", createdDeviceId: "iphone-abc", stored: "iPhone 16 Pro"),
            "iPhone 16 Pro")
    }

    // 5) 저장된 device는 레거시 역산보다 우선
    func testStoredOverridesLegacy() {
        XCTAssertEqual(
            CaptureDevice.label(source: "web", createdDeviceId: "legacy", stored: "iPhone 16 Pro"),
            "iPhone 16 Pro")
    }

    // 6) 저장값 없는 네이티브 → 안전망
    func testNativeNoStored_fallback() {
        XCTAssertEqual(
            CaptureDevice.label(source: "voice", createdDeviceId: "iphone-abc"),
            "이 기기")
    }
}
