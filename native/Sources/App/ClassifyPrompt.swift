import Foundation

/// §3 분류 프롬프트 — **classify.py의 `SYSTEM_PROMPT`·`SCHEMA`를 그대로 옮긴 것**(살아있는 자산).
/// "어떻게 분류하나"는 웹이든 iPhone이든 동일(사양서 §3·§0-A). 이 문자열을 함부로 바꾸지 말 것.
enum ClassifyPrompt {
    /// 지능 층은 소모품(§0). 필요하면 sonnet/haiku로 교체.
    static let model = "claude-opus-4-8"

    static let system = """
다음은 사용자의 받은함(inbox)의 미가공 수집 줄들이다. 각 줄을 아래 규칙으로 분류하라.

분류(type): event(예정된 일) / promise(부탁·약속) / info-action(이걸로 뭘 해야겠다) / info(행동은 필요 없지만 나중에 참고할 사실·정보) / idea(생각) / discard(버릴 것)

각 항목에 붙일 것:
- type
- due: 날짜가 명시되거나 맥락에서 추론되면 YYYY-MM-DD, 없으면 "none"
- resurface: due가 있으면 그 며칠 전 날짜(YYYY-MM-DD), 없으면 "none"
- status: 항상 "open"
- question: info-action인데 "구체적으로 뭘, 언제 할지"가 불명확하면 그 한 줄 질문. 아니면 빈 문자열.

규칙:
- 짧다는 이유만으로 버리지 마라. 파편이라도 다음이면 info(정보·참고)로 보존하라:
  (1) 장소·위치 정보(예: 주차 위치 "지하 왼쪽 구멍"), (2) 특정 인물에 대한 메모·평가(예: "김형석대표는 책임감으로 산 책 다 읽는다"), (3) 나중에 참고할 사실.
- discard는 테스트/시스템 입력('시험 중', '음성 메모 추가' 등)이나, 받아쓰기 실패로 의미를 알 수 없는 조각에만 한정하라.
- 사람과의 약속(promise)은 절대 놓치지 말고 보수적으로 잡아라.
- 시점(due) 추출을 적극적으로 하라. 상대 표현은 반드시 '오늘 날짜' 기준 구체 날짜(YYYY-MM-DD)로 환산한다:
  "오늘"=오늘, "내일"=오늘+1, "모레"=오늘+2, "이번 주"=이번 주 일요일, "다음 주"=다음 주 일요일,
  "이번 달 말"=이달 마지막 날, "N일까지/N월 N일"=그 날짜. 연도가 없으면 오늘 기준 가장 가까운 미래로 잡는다.
- due가 잡히면 resurface는 그 며칠 전(promise/event는 2~3일 전, 여유가 없으면 due 하루 전)으로 둬라.
  단 resurface는 **마감보다 최소 하루 빨라야 한다(규칙 1)** — 마감 당일이 될 만큼 여유가 없으면 resurface는 "none"으로 둬라.
- 명시적·추론 가능한 시점이 전혀 없으면 due는 "none". 시점은 확정이 아니라 추정이며, 앱이 "~까지"로 표시하고 사람이 확인한다.
- 하루를 시작할 때의 다짐·생활 원칙 같은 반복 인지용 문장은 type을 principle 로 하라(원칙).
- 원문은 절대 바꾸지 마라. 너는 분류 결과(JSON)만 돌려준다. 원문 텍스트는 반환하지 않는다.
- 각 입력 줄에는 index가 붙어 있다. 반드시 그 index로 결과를 대응시키고, 모든 줄을 빠짐없이 분류하라.
"""

    /// classify.py의 SCHEMA와 동형(structured outputs json_schema).
    /// 함수로 두어 매 호출 새 딕셔너리 생성(비-Sendable `[String: Any]`의 전역 공유 회피).
    static func makeSchema() -> [String: Any] { [
        "type": "object",
        "properties": [
            "classifications": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "index": ["type": "integer"],
                        "type": ["type": "string",
                                 "enum": ["event", "promise", "info-action", "info", "idea", "principle", "discard"]],
                        "due": ["type": "string"],
                        "resurface": ["type": "string"],
                        "status": ["type": "string"],
                        "question": ["type": "string"],
                    ],
                    "required": ["index", "type", "due", "resurface", "status", "question"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["classifications"],
        "additionalProperties": false,
    ] }
}
