import XCTest

final class DragTests: XCTestCase {

    private func dragAndHold(mode: String?) {
        let app = XCUIApplication()
        app.launch()
        if let mode { app.buttons[mode].tap(); sleep(1) }
        let a = app.staticTexts["AAAA 첫째줄"]
        let c = app.staticTexts["CCCC 셋째줄"]
        XCTAssertTrue(a.waitForExistence(timeout: 15), "행이 안 뜬다")
        let from = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to   = c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // 길게 눌러 들고 → 천천히 끌고 → 그 자리에서 12초 멈춘다(그동안 바깥에서 찍는다)
        from.press(forDuration: 1.5, thenDragTo: to, withVelocity: 120, thenHoldForDuration: 12.0)
        sleep(2)
    }

    func testA기본()   { dragAndHold(mode: nil) }
    func testB편집모드() { dragAndHold(mode: "B 편집모드") }
    func testConDrag() { dragAndHold(mode: "C onDrag") }
}

extension DragTests {
    func testD실제꼴() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["D 실제꼴"].tap(); sleep(1)
        let a = app.staticTexts["AAAA 첫째줄"]
        let c = app.staticTexts["CCCC 셋째줄"]
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.5,
                   thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    func testE링크뺌() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["E 링크뺌"].tap(); sleep(1)
        let a = app.staticTexts["AAAA 첫째줄"]
        let c = app.staticTexts["CCCC 셋째줄"]
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.5,
                   thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    func testF복제() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["F 복제"].tap(); sleep(1)
        let a = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'AAAA'")).firstMatch
        let c = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CCCC'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.5,
                   thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 120, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    /// ★ **살짝만** 끈다 — 이웃과 자리가 바뀌기 **전**에서 멈춘다. 사용자가 말한 그 구간.
    func testG살짝() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["F 복제"].tap(); sleep(1)
        let a = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'AAAA'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        let from = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to   = from.withOffset(CGVector(dx: 0, dy: 22))   // 22pt — 한 줄 높이보다 훨씬 작다
        from.press(forDuration: 1.5, thenDragTo: to, withVelocity: 40, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    /// 편집모드(고전 순서 바꾸기)에서 **살짝만** 끈다 — 손잡이(오른쪽 끝)를 잡는다.
    func testH편집살짝() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["G 복제편집"].tap(); sleep(1)
        let a = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'AAAA'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        // 손잡이는 화면 오른쪽 끝(≈384pt). 창 원점 기준 절대 좌표로 잡는다.
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: 384, dy: 304))
        let to   = origin.withOffset(CGVector(dx: 384, dy: 326))   // 22pt 아래
        from.press(forDuration: 1.0, thenDragTo: to, withVelocity: 40, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    /// UIKit 대화식 이동에서 **살짝만** 끈다 — F와 같은 조건.
    func testI유아이킷살짝() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["H UIKit"].tap(); sleep(1)
        let a = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'AAAA'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        let from = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to   = from.withOffset(CGVector(dx: 0, dy: 22))
        from.press(forDuration: 1.5, thenDragTo: to, withVelocity: 40, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    func testJ글자() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["I 글자"].tap()
        sleep(8)
    }
}

extension DragTests {
    func testK여백() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["J 여백"].tap()
        sleep(8)
    }
}

extension DragTests {
    func testL모드보기() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["F 복제"].tap(); sleep(5)
        app.buttons["H UIKit"].tap(); sleep(5)
    }
}

extension DragTests {
    func testM카드() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["K 카드"].tap(); sleep(7)
    }
}

extension DragTests {
    /// 이웃을 **넘어가게** 끌고 그 자리에서 멈춘다 — 놓기 전에 번호·바탕색이 바뀌는지 본다.
    func testN교체중() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["H UIKit"].tap(); sleep(1)
        let a = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'AAAA'")).firstMatch
        let c = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CCCC'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 15))
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.5,
                   thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: 80, thenHoldForDuration: 12.0)
        sleep(2)
    }
}

extension DragTests {
    func testO맞춤() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["L 맞춤"].tap(); sleep(7)
    }
}
