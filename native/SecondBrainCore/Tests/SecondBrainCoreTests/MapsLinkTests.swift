import XCTest
@testable import SecondBrainCore

/// **지도 앱 링크** (2026-08-20 · 사용자가 실기기에서 결함을 발견해 생긴 시험).
///
/// 이 시험이 막는 것 둘 — **둘 다 오류도 로그도 안 남는다:**
/// 1. `q`(이름)가 빠지면 **지도는 열리는데 핀이 없다** ← 2026-07-19~08-20 실제로 그랬다
/// 2. 한글 이름을 인코딩 안 하면 **URL이 nil** → 버튼이 아무 일도 안 한다
final class MapsLinkTests: XCTestCase {

    private let lat = 37.49614666666667
    private let lon = 127.0405805

    /// ⛔ **URL이 만들어져야 한다.** 기본 이름이 한글(공백 포함)이라 문자열 조립이면 여기서 nil이 난다.
    func testURL이_nil이_아니다_한글_이름이어도() {
        XCTAssertNotNil(MapsLink.pin(latitude: lat, longitude: lon))
    }

    /// ⛔ **이 시험이 옛 결함을 막는다.** `q`가 없으면 핀이 안 놓인다.
    func testQ가_있다_없으면_핀이_안_찍힌다() {
        let u = MapsLink.pin(latitude: lat, longitude: lon)!
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "q" && ($0.value?.isEmpty == false) },
                      "q(핀 이름)가 없다 — 지도는 열리는데 핀이 안 찍힌다: \(u.absoluteString)")
    }

    func testLL이_좌표를_그대로_담는다() {
        let u = MapsLink.pin(latitude: lat, longitude: lon)!
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "ll" }?.value, "\(lat),\(lon)")
    }

    /// 한글 이름이 **퍼센트 인코딩되어** 실제 URL 문자열에 들어간다(생 한글이 아니다).
    func testQ가_퍼센트_인코딩된다() {
        let u = MapsLink.pin(latitude: lat, longitude: lon)!
        XCTAssertFalse(u.absoluteString.contains("촬영"), "생 한글이 URL에 들어갔다: \(u.absoluteString)")
        XCTAssertTrue(u.absoluteString.contains("%"), "인코딩된 흔적이 없다: \(u.absoluteString)")
        // 되읽으면 원래 말이 나온다 — 인코딩이 맞다는 대조.
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, MediaMigrationText.photoPinName)
    }

    func testHTTPS다() {
        XCTAssertEqual(MapsLink.pin(latitude: lat, longitude: lon)?.scheme, "https")
    }

    /// 핀 이름은 **앱 안 지도의 마커와 같은 값**이어야 한다 — 사용자가 그 이유로 골랐다.
    /// 두 군데 문자열로 두면 한쪽만 고쳐져 말이 갈린다.
    func test핀_이름은_사용자가_고른_한_값이다() {
        XCTAssertEqual(MediaMigrationText.photoPinName, "촬영 위치")
    }

    /// 음수 좌표(남반구·서반구)도 그대로 담긴다 — 부호를 잃으면 **지구 반대편**이 된다.
    func test음수_좌표도_그대로() {
        let u = MapsLink.pin(latitude: -33.8688, longitude: -151.2093)!
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "ll" }?.value, "-33.8688,-151.2093")
    }
}
