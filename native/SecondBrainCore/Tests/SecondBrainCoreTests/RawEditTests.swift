import XCTest
@testable import SecondBrainCore

/// 본문(raw) 수정 = 텍스트 층 편집(edit-policy.md §6). 유일하게 위험한 층 —
/// 조각 파일이 `|` 구분이라 사람이 쓴 긴 글이 직렬화·파싱을 깨뜨릴 수 있다.
/// 여기서 깨지면 기억이 손상되므로 화면 작업보다 먼저 왕복을 고정한다.
final class RawEditTests: XCTestCase {

    /// raw만 담은 edit 이벤트를 직렬화→파싱했을 때 글자 그대로 돌아오는지.
    private func assertRawRoundtrips(_ raw: String, _ msg: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let e = Event.edit(id: "r", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "iphone"),
                           ["raw": raw])
        let back = EventLog.parse(EventWriter.serialize(e))
        XCTAssertEqual(back.count, 1, "이벤트 1개여야: \(msg)", file: file, line: line)
        XCTAssertEqual(back.first?.id, "r", "id 왕복: \(msg)", file: file, line: line)
        XCTAssertEqual(back.first?.hlc, e.hlc, "hlc 왕복: \(msg)", file: file, line: line)
        XCTAssertEqual(back.first?.fields["raw"], raw, "raw 글자 그대로: \(msg)", file: file, line: line)
    }

    // 사용자가 콕 집은 위험 문자 전부. 각각 직렬화→파싱 왕복.
    func testRawRoundtrip_trickyCharacters() {
        assertRawRoundtrips("첫 줄\n둘째 줄", "줄바꿈")
        assertRawRoundtrips("a|b", "파이프(공백 없음) — @ 줄이 |로 쪼개지는 함정")
        assertRawRoundtrips("2026-07-31|09:00|정리", "파이프 여러 개")
        assertRawRoundtrips("그는 \"안녕\"이라 했다", "큰따옴표")
        assertRawRoundtrips("It's a plan", "작은따옴표")
        assertRawRoundtrips("경로 C:\\temp\\a", "백슬래시")
        assertRawRoundtrips("회의 정리 ✅ 굿 🙂", "이모지")
        assertRawRoundtrips(String(repeating: "아주 긴 문장이다. ", count: 200), "아주 긴 문장")
        assertRawRoundtrips("", "빈 문자열")
        assertRawRoundtrips("  앞뒤 공백 있음  ", "앞뒤 공백")
        assertRawRoundtrips("\t탭\t끼임", "탭")
    }

    // 파이프만 있고 공백 없는 값 — 재현 핀. (뒤집기 전에는 set raw=a|b로 새 나가 |b 유실.)
    func testRawRoundtrip_pipeNoSpace_repro() {
        assertRawRoundtrips("a|b", "파이프+공백없음")
    }

    // 전체 경로: create + raw 수정 edit → 병합 시 수정본이 이기고(LWW), 원본은 로그에 남는다.
    func testRawEdit_fullPath_editWins() {
        let c = Event.create(id: "x", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "iphone"),
                             date: "2026-07-16", time: "09:00", source: "voice",
                             raw: "내일까지 조직도 셋업 해야 됩니다")
        let edit = Event.edit(id: "x", hlc: HLC(wallMillis: 2, counter: 0, deviceId: "iphone"),
                              ["raw": "내일까지 조직도 셋업 해야 됩니다 (STT 정정본)"])
        let text = [c, edit].map(EventWriter.serialize).joined(separator: "\n")
        let r = MergeEngine.merge(EventLog.parse(text))
        XCTAssertEqual(r.item("x")?.raw, "내일까지 조직도 셋업 해야 됩니다 (STT 정정본)")  // 높은 HLC 승
    }

    // ★ 성역 불변식: raw 수정 edit 이벤트에는 성역 필드(date·time·source·device·audio·photo)가
    //   절대 담기지 않는다 → 병합에서 그 값들은 create 값 그대로 남는다.
    func testRawEdit_sanctuaryUntouched() {
        let c = Event.create(id: "s", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "iphone"),
                             date: "2026-07-16", time: "09:00", source: "voice", raw: "원본",
                             extra: ["audio": "s.m4a", "device": "iphone-16-pro"])
        let edit = Event.edit(id: "s", hlc: HLC(wallMillis: 2, counter: 0, deviceId: "iphone"),
                              ["raw": "고친 본문 with | pipe"])

        // (1) 직렬화된 edit 줄에 성역 키가 아예 없다.
        let editLine = EventWriter.serialize(edit)
        for k in ["date:", "time:", "source", "device", "audio", "photo"] {
            XCTAssertFalse(editLine.contains(k), "edit 이벤트에 성역 키 '\(k)' 없어야: \(editLine)")
        }

        // (2) 병합 후 성역 값은 create 그대로, raw만 바뀐다.
        let r = MergeEngine.merge(EventLog.parse([c, edit].map(EventWriter.serialize).joined(separator: "\n")))
        let item = r.item("s")
        XCTAssertEqual(item?.raw, "고친 본문 with | pipe")
        XCTAssertEqual(item?.date, "2026-07-16")           // 성역 불변
        XCTAssertEqual(item?.time, "09:00")
        XCTAssertEqual(item?.source, "voice")
        XCTAssertEqual(item?.fields["audio"], "s.m4a")
        XCTAssertEqual(item?.fields["device"], "iphone-16-pro")
    }
}
