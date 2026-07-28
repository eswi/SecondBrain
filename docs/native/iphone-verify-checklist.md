# 아이폰 실기기 검증 체크리스트 — iCloud 배선 (네이티브 v1)

> 목적: **데모가 아니라 진짜 내 데이터(inbox.md 68개)** 가 아이폰에 뜨고, 거기서 누른
> 미루기·삭제가 조각 파일에 실제로 append되며 **inbox.md는 안 건드려지는 것**, 그리고
> 아이폰↔맥 동기화를 실기기로 확인한다.
> 관련 커밋 `615340a`. macOS에서 실데이터로 로직은 이미 검증됨(읽기 68·쓰기·불변).

## A. 아이폰에 올리기 (자동 서명)
1. 아이폰이 연결된 Mac에서: `cd native && xcodegen generate` (`.xcodeproj`는 gitignore 생성물 — 매번 재생성).
2. `native/SecondBrain.xcodeproj`를 Xcode로 열기.
3. 아이폰 케이블 연결 → 폰에서 "이 컴퓨터를 신뢰" 탭.
4. 스킴 **SecondBrainApp-iOS**, 대상(destination) = 내 실제 아이폰 선택.
5. 서명: `project.yml`에 팀(`4W2HHUZTYT`)·자동 서명 이미 설정됨. Xcode가 불평하면
   Settings > Accounts에 Apple ID 로그인 확인, 번들 id `kr.teri.secondbrain`.
6. **⌘R (Build & Run).** 첫 실행 후 아이폰에서:
   설정 > 일반 > VPN 및 기기 관리 > 개발자 앱 **신뢰**. (서명 만료·갱신은 **F절** 참조 — 현재 유료 등록이라 ~1년.)

## B. 폴더 선택 → 실데이터 확인
- [ ] 앱 첫 화면 = **"받은함 폴더를 선택하세요"** 안내가 뜬다.
- [ ] **폴더 선택** 탭 → Files 피커에서 **iCloud Drive > SecondBrain** 폴더로 이동 → 열기.
      (iCloud Drive가 안 보이면 설정에서 iCloud Drive 켜기.)
- [ ] 잠시 후 **약 68개 항목**이 뜬다(내 실제 voice 메모들 — "주차 위치…", "김광석…" 등).
      *0개면* iCloud가 아직 파일을 안 내려온 것 → 몇 초 뒤 툴바 📁로 폴더 재선택 또는 앱 재시작.
- [ ] 헤더에 **`기기 iphone-xxxx · inbox.md`** 표시.

## C. 행동이 조각 파일에 실제로 append되나
- [ ] 아무 항목 **왼쪽→ 스와이프 → 미루기(주황)**. 캡션에 **`↻2026-xx-xx`**(오늘+7일) 뜬다.
- [ ] 아무 항목 **오른쪽→ 스와이프 → 삭제(빨강)**. 목록에서 사라지고 헤더에 **`· N 삭제`** 증가.
- [ ] (선택) **완료(초록)** 도 동작 — 목록에서 빠지고 헤더 `· N 완료`.
- [ ] **Files 앱**으로 iCloud Drive/SecondBrain 열기 → **`inbox-iphone-xxxx.md`** 새로 생겼는지,
      열어 보면 `@ <hlc> | legacy:<hash> | set resurface=…` / `… | delete` 줄이 들어 있다.
- [ ] **`inbox.md` 는 그대로** — 크기·수정시각 안 변함(웹앱 https://eswi.github.io/SecondBrain/ 에서 열어 항목 수 그대로인지 교차 확인).

## D. 아이폰 ↔ 맥 동기화
- [ ] Mac에서 **SecondBrainApp-macOS** 빌드·실행(⌘R) → 같은 **SecondBrain** 폴더 선택.
- [ ] 아이폰에서 만든 **미루기·삭제가 Mac 앱에도** 반영된다(같은 항목이 미뤄지고/사라짐).
      iCloud 동기화 지연 수 초~수 분 감안. Mac 툴바 📁 재선택하면 재읽기.
- [ ] Mac에서 다른 항목을 행동 → **아이폰에도** 반영(양방향). 각 기기가 자기 조각에만 쓰므로 충돌 없음.

## E. 알아둘 것 / 이번 범위 밖
- **알림은 아직 안 울린다.** `NotificationPlanner`(순수 계산)만 있고 `UNUserNotificationCenter` 배선 전 — 다음 단계(Phase 3 배달).
- 서명 만료·갱신 → **F절** 참조. (현재 유료 등록: ~1년. 무료 개인 팀이면 7일.)
- 공존 원칙: **분류는 웹, 행동은 네이티브.** 원문 텍스트는 손으로 고치지 않기(레거시 id는 원문 해시라 원문 바꾸면 행동 사슬이 끊김).

## F. 서명 만료 (재서명으로 갱신)
- **현재 만료: 2027-02-08** — Apple Development 서명 인증서(`notAfter`) 기준. 프로필 만료(2027-07-17)보다 **이른 쪽이 실제 한도**라 이 날짜가 앱 실행 한계다.
- **약 1년 = 유료 Apple Developer Program 등록 상태.** 팀 `4W2HHUZTYT`는 유료 등록됨. (무료 개인 팀이면 프로필이 **7일**로 강제된다 — 우리는 해당 없음. 상시 제약은 아래.)
- **만료일 확인** — 마지막으로 빌드된 `.app`의 embedded provision을 읽는다:
  ```sh
  APP=native/build/Build/Products/Debug-iphoneos/SecondBrain.app
  security cms -D -i "$APP/embedded.mobileprovision" -o /tmp/p.plist
  /usr/libexec/PlistBuddy -c "Print :ExpirationDate" /tmp/p.plist          # 프로필 만료
  # 서명 인증서(둘 중 이른 것 = 실제 한도):
  python3 -c "import plistlib;open('/tmp/c.der','wb').write(plistlib.load(open('/tmp/p.plist','rb'))['DeveloperCertificates'][0])"
  openssl x509 -inform DER -in /tmp/c.der -noout -enddate
  ```
- **갱신:** 만료가 다가오면 **Xcode에서 앱을 다시 실행(⌘R)** 하면 자동 재서명·재설치되어 갱신된다. 별도 절차 불필요.
- **알림 검증 전 남은 일수부터 확인.** 알림은 **오전 9시 발화**라 검증에 하루가 걸린다(`notify-verify-checklist.md`) — 만료가 임박하면 그 사이 서명이 죽을 수 있으니 검증 시작 전에 위 명령으로 남은 일수를 먼저 본다.

## G. 상시 주의 — 앱을 삭제하지 말 것 (만료와 무관)
재서명 갱신은 **재설치가 아니라 Xcode 재실행(⌘R)** 으로 한다. **앱을 지웠다 새로 깔면** 아래 로컬 상태를 잃는다(만료 문제와 별개, 상시):
- **기기 식별값** — `DeviceStore.deviceId`가 UserDefaults에 있어 삭제 시 사라진다. 다음 실행에 **새 id 발급 → 조각 파일이 새로 갈라짐**(`inbox-iphone-<새4자리>.md`가 하나 더 생겨 기존 조각의 행동 이력과 분리). HLC 시계도 함께 리셋.
- **키체인의 Claude API 키** — 자동 분류용 키가 사라져 설정에서 다시 입력해야 함.
- **알림 권한** — 재요청·재허용 필요.

데이터(iCloud 평문 조각·`inbox.md`) 자체는 안 지워지지만, 위 3개는 앱 삭제로 날아간다. → **갱신은 항상 재설치 말고 ⌘R.**

## 문제 생기면 메모할 것
- 68개 대신 0개/일부만 → 얼마 뒤·재선택으로 해결됐는지.
- 조각 파일이 Files에 안 보이거나 동기화가 한 방향만 → 어느 방향인지.
- 서명·신뢰·설치에서 막힌 지점.
→ 이 내용 알려주면 다음 세션에서 바로 조치.
