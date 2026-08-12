#if DEBUG
import Foundation

/// 시뮬레이터 전용 샘플 데이터(렌더 확인용). 릴리스 빌드·실기기엔 포함/사용되지 않는다.
/// 레거시 v0 형식 블록이라 파싱 시 `legacy:` id를 받는다(실데이터와 같은 경로).
///
/// **2026-08-11 추가 — 「주차 위치」(`parking`).** 2차 압축의 분류 세로 배치를 시뮬레이터에서 검증하려면
/// **가장 긴 분류 이름**이 필요하다(계측 최악값 = 주차 위치 63.2pt). 없으면 두 번째로 긴 「아이디어」까지만
/// 보여서 **정작 넘칠 후보를 못 본다.** 이 파일의 목적("렌더 확인용")에 그대로 해당한다.
///
/// **2026-08-12 추가 — 「B2 구역 기둥 옆」에 `audio:`·`photo:` 포인터.**
/// 확인 목록 **3번(종류 아이콘 개수)** 을 시뮬레이터로 옮기기 위한 것.
/// `DetailView`는 아이콘을 **필드 유무만 보고** 그린다(`if item.fields["photo"] != nil`) —
/// **파일이 없어도 아이콘은 뜬다.** 그래서 포인터 두 줄로 **최대 3개**(방식 1 + 음성 + 사진)를 볼 수 있다.
/// 필드 값(`sample-parking.*`)은 **표시용일 뿐 조회에 안 쓰인다** — `PhotoStore.url(forId:)`가
/// 파일명을 `"<항목 id>.jpg"`로 **직접 만든다.** 실제 파일을 심으려면 그 id로 이름을 지어야 한다.
/// 파일이 없는 동안은 「이 기기엔 없음」 안내 줄이 그려진다(`audioRow`/`photoMissingRow`).
///
/// **아직 못 채운 것 — 시뮬레이터로는 볼 수 없어 실기기 확인 목록으로 넘긴 것들:**
/// - **「되풀이」** — 반복 설정 카드·배너 다섯의 렌더.
/// - **음성·사진 있는 항목** — `audio:`/`photo:` 포인터만 넣어도 **파일이 없으면 "이 기기엔 없음" 안내 줄**이
///   그려진다(`audioRow`/`photoMissingRow`). 즉 **사진 260pt·지도 150pt가 붙은 성역(최대 617pt)은 재현 불가**다.
///   그걸 보려면 시뮬레이터 컨테이너에 실제 파일을 심어야 한다.
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
      confirmed: true
    - 2026-07-14 20:00 | voice | 아이와 주말에 별 보러 가기
      type: idea
      confirmed: true
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
    - 2026-07-18 18:20 | voice | B2 구역 기둥 옆
      type: parking
      confirmed: true
      audio: sample-parking.m4a
      photo: sample-parking.jpg
    - 2026-07-08 15:00 | web | 스팸성 뉴스레터 링크
      type: discard
    """
}
#endif
