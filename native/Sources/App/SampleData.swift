#if DEBUG
import Foundation

/// 시뮬레이터 전용 샘플 데이터(렌더 확인용). 릴리스 빌드·실기기엔 포함/사용되지 않는다.
/// 레거시 v0 형식 블록이라 파싱 시 `legacy:` id를 받는다(실데이터와 같은 경로).
enum SampleData {
    /// 시뮬레이터에서 폴더 미선택일 때만 시드로 쓴다.
    static var useInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static let text = """
    # 받은함 (샘플)
    - 2026-07-13 19:00 | voice | 아이 학원 등록 마감
      type: promise
      due: 2026-07-14
    - 2026-07-12 10:00 | meeting | 팀 회의 자료 준비
      type: event
      due: 2026-07-17
    - 2026-07-10 09:00 | voice | 치과 예약 확인 전화하기
      type: info-action
      due: 2026-07-20
    - 2026-07-17 08:00 | voice | 엄마 생신 선물 사기
      type: promise
      resurface: 2026-07-24
    - 2026-07-16 14:30 | web | 오프라인 우선 노트 앱 아이디어
      type: idea
    - 2026-07-16 11:00 | mail | 세금 관련 서류 훑어보기
      type: info
    - 2026-07-17 07:30 | voice | 자전거 바람 넣기
    - 2026-07-15 22:00 | voice | 매일 아침 감사한 것 세 가지 떠올리기
      type: principle
    - 2026-07-11 06:30 | voice | 급할수록 천천히, 하나씩
      type: principle
    - 2026-07-09 12:00 | doc | 완료한 예시 항목
      type: info-action
      status: done
    - 2026-07-08 15:00 | web | 스팸성 뉴스레터 링크
      type: discard
    """
}
#endif
