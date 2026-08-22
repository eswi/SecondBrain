# ghostlab — **화면을 눌러 봐야 나오는 것**을 자동으로 재는 장치 (2026-08-20 신설)

> ## ⚠️ 이것은 **앱 코드가 아니다 — 실험용이다**
> `native/tools/ghostlab/`는 **따로 도는 임시 iOS 앱**이고 **`SecondBrain` 빌드에 안 섞인다.**
> 앱 타깃은 `native/project.yml`에서 **`sources: [Sources/App]`만** 컴파일한다 —
> `native/tools/` 아래는 **어느 타깃에도 들어가지 않는다.**
> ⛔ **여기 있는 것을 앱에서 `import`하거나 참조하지 말 것.** 색·글꼴은 앱과 **값만 베껴** 뒀고
> (`Palette`를 안 쓴다) 그래서 **앱 색이 바뀌면 여기는 안 따라온다.** 그것이 의도다 —
> 실험용이 앱을 잡아끌지 않게.

---

## 1. 무엇을 재는 도구인가

**「눌러야만 드러나는 결함」을 사람 손 없이 재현하고 픽셀로 판정한다.**

이 프로젝트의 오래된 약점이 그것이었다 — 지도 핀이 안 찍히는 결함은 **27일** 살아 있었고,
코드는 완벽했고 로그도 안 남았다. **정적 훑기로는 안 나오고, 누르면 나온다.**
`ghostlab`은 그 「누르는 일」을 자동화한다.

| 조각 | 무엇 |
|---|---|
| `project.yml` + `Sources/` | 같은 목록을 **여러 꼴(A~L)로 나란히 그리는 임시 앱.** 한 화면에서 꼴을 바꿔 비교한다 |
| `UITests/DragTests.swift` | `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` — **끌다가 멈춰 있게** 한다 |
| `measure-frames.swift` | 스크린샷에서 **색 띠 자리·줄 간격(pitch)**을 픽셀로 센다 |

### 왜 「멈춰 있게」가 핵심인가
끌기 도중의 상태는 **손을 떼면 사라진다.** `thenHoldForDuration:`으로 **12초 멈춰 두고**
그 사이에 바깥에서 `xcrun simctl io … screenshot`을 연속으로 찍으면 **중간 상태가 파일로 남는다.**

---

## 2. 이번에 이 장치로 무엇을 잡았나 (2026-08-20~21)

### ★ ① 잔상 — **「안 된다」던 결론을 뒤집었다**
사용자가 세 번 지적한 것: *"살짝 이동하면 그 아래에 기존 잔상이 남아 있어.
위 혹은 아래 항목과 자리가 바뀌는 순간 사라져."*
두 번 시도하고 **「이 구조에서는 안 된다」로 닫아** 뒀던 자리다.

**재현 조건을 이 장치로 찾았다: 「첫 교체 전」 구간에만 있다.**
크게 끌면 안 보이고 **22pt만** 끌 때 나온다 — 그전까지 내 시험은 그 구간을 **건너뛰고** 있었다.

### ★ ② 편집모드는 답이 아니다 — **문서에 여러 번 적혀 있던 안이 여기서 죽었다**
같은 조건(22pt 끌고 12초 멈춤)으로 셋을 쟀다:

| 꼴 | 원래 자리 | |
|---|---|---|
| SwiftUI `List` + `.onMove` | 흐린 사본이 남는다 | ⛔ |
| **같은 것 + `editMode = .active`** | **똑같이 남는다** | ⛔ **← 이것을 몰랐다** |
| `UICollectionView` + `beginInteractiveMovementForItem` | **비어 있다** | ✅ |

SwiftUI `List`는 **편집모드에서도** 순서 바꾸기를 드래그앤드롭으로 돌린다 —
**손잡이만 얻고 잔상은 그대로다.** 이 표가 없었으면 **편집 모드 버튼을 만들어 넣고
잔상은 그대로 남는** 길로 갔을 것이다.

### ③ 그 밖에 이 장치로 닫은 것
- **`UIHostingConfiguration`은 Dynamic Type를 안 끊는다** — XXL에서 SwiftUI 직접과 셀 안이
  둘 다 `callout=20.0pt · trait=XXL`로 같았다. 「글자가 작아진 건 셀 탓」이라는 가설을 **버렸다**.
- **`List`가 스스로 주는 세로 여백 = 한쪽 15pt** (줄에 적힌 5pt와 **별개**). 이걸 몰라서
  새 그릇 여백을 6으로 잡았고 **한 줄마다 28pt 좁았다.**
- **좌우 맞춤**: SwiftUI `Text`는 안 된다 · `AttributedString`의 문단 정렬도 **무시된다** ·
  `UILabel(textAlignment: .justified)`는 **된다**(실측).

---

## 3. 쓰는 법

```sh
cd native/tools/ghostlab
xcodegen generate                       # .xcodeproj는 생성물(gitignore)
SIM=<이 기기의 UDID>                     # xcrun simctl list devices available 로 확인

# 시험을 돌리면서 끝날 때까지 계속 찍는다
xcodebuild test -project GhostLab.xcodeproj -scheme GhostLab \
  -destination "id=$SIM" -only-testing:GhostLabUITests/DragTests/testN교체중 > /tmp/t.log 2>&1 &
BG=$!; i=0
while kill -0 $BG 2>/dev/null; do
  i=$((i+1)); xcrun simctl io $SIM screenshot --type=png $(printf "/tmp/shots/%03d.png" $i)
done; wait $BG

# 판정
swiftc -O measure-frames.swift -o /tmp/mf
for f in /tmp/shots/*.png; do /tmp/mf marks "$f"; done
```

### ⚠️ `marks`는 **색 사각형이 있는 꼴만** 잰다
카드 꼴(K·H)은 표식이 **숫자**라서 띠가 0개로 나온다 — **정상이다.**
줄 간격을 잴 때는 사각형을 가진 꼴(**F 복제 · J 여백**)을 쓴다.

### ⛔ 촬영 루프는 **개수로 끊지 말 것**
처음엔 `for i in $(seq 70)`으로 고정 개수를 찍었는데, 모드 전환 탭 때문에 끌기가 2~3초 늦어지자
**루프가 먼저 끝나** 있었다. 그걸 보고 *"끌기가 안 된다"*고 판정했다 — **틀렸다.**
**「시험이 끝날 때까지」**로 도는 위 형태를 쓴다.

### ⛔⛔ **`Test Case … passed`를 「안 죽었다」로 읽지 말 것**
XCUITest는 **마지막 동작 뒤에 앱이 죽어도 통과로 적는다.** 반드시 함께 본다:

```sh
grep -c "unexpected termination" /tmp/t.log        # 0이어야 한다
ls ~/Library/Logs/DiagnosticReports/ | grep -i ghostlab   # 새 .ips가 없어야 한다
```

2026-08-21에 **놓는 순간 앱이 죽는 결함**이 이 줄에 이미 있었는데,
나는 **끌던 중간 프레임만 보고 「된다」고 보고했다.** 사용자가 실기기에서 잡았다.
크래시 원인은 `.ips` 파일 이름이 그대로 말해줬다 —
`BUG_IN_CLIENT_OF_DIFFABLE_DATA_SOURCE__APPLYING_SNAPSHOTS_REENTRANTLY`.

### ⛔ 마우스로 시뮬을 조작하는 길 — **이미 도구가 있다. 새로 만들지 말 것**
**`native/tools/sim-input.swift`(2026-08-14)**가 CGEvent로 탭·드래그를 한다.
좌표 함정(툴바 44pt)까지 적혀 있다.
⚠️ **2026-08-20에 나는 그것을 모르고 같은 것을 새로 만들었다** — 계측 규칙 5가 막으려던 바로 그 일이다.
- 다만 **회사 맥북에서는 그 길이 막혔다**: 시뮬 창이 39×135로 줄어 있고
  `System Events`가 Simulator 창을 **못 본다**(좌표를 못 읽는다). 창을 키우려는 시도도 안 먹었다.
- **XCUITest는 창이 필요 없다** — 그래서 여기서는 이쪽을 쓴다.

---

## 4. 안에 뭐가 있나 (꼴 목록)

| 꼴 | 무엇을 보려고 만들었나 |
|---|---|
| A 기본 | `List` + `.onMove` (맨 처음 기준) |
| B 편집모드 | `editMode = .active` |
| C onDrag | `.onDrag`를 얹은 꼴(테두리 시절) |
| D 실제꼴 | `NavigationStack`+`NavigationLink`+`listRowBackground` |
| E 링크뺌 | D에서 `NavigationLink`만 뺀 것(변수 가르기) |
| **F 복제** | 진짜 화면 정밀 복제(다크 팔레트·여러 줄·머리글) — **잔상이 여기서 재현됐다** |
| **G 복제편집** | F + 편집모드 — **편집모드가 답이 아님을 여기서 확인** |
| **H UIKit** | `UICollectionView` 대화식 이동 — **해법** |
| I 글자 | SwiftUI 직접 vs `UIHostingConfiguration` 셀의 글자 크기·trait |
| J 여백 | 두 그릇의 줄 간격 |
| K 카드 | 새 카드(숫자·색·테두리) 모양 보기 |
| L 맞춤 | 좌우 맞춤 세 가지 |

`UITests/DragTests.swift`에 꼴별 시험이 하나씩 있다.
**끌기 거리를 바꾼 시험이 둘인 것에 주의** — `testI유아이킷살짝`(22pt, 이웃을 **안** 넘는다) ·
`testN교체중`(이웃을 **넘는다**). **둘이 서로 다른 결함을 잡는다.**

---

## 5. 다음에 쓰일 자리

**자료 확장 2단계 — 사진·지도를 성역에서 떼어 새 카드로 옮기는 일**(`HANDOFF.md` §3-A ②).
화면 배치를 다시 만지는 일이고, 그때 **바꾸기 전/후를 같은 자로 재려면 이 장치가 있어야 한다**
(사용자 지시 2026-08-21).

---

## ★ 꼴 다섯을 더했다 — **자료 카드** (2026-08-22 · `media-expansion-design.md` §3-A·§3-B)

| 꼴 | 무엇을 그리나 | 무엇에 답하려고 |
|---|---|---|
| **Q 자료** | 자료 카드 — **종류 1~5개**일 때 각각 · 개수 배지 | 카드가 어떻게 생기나 · **음성이 맨 앞인 것**(②) |
| **T 자료2** | 배지 **두 자리**(12·25) · **「못 만들었다」 문구 후보 넷** · 섞임 · **0개 대조** | 「못 만들었다」와 「자료가 없다」를 갈라 보이나(§3-A-3) · **문구는 사용자가 고른다** |
| **R 크기** | 네모 한 변 **56·62·68·76·88·100** 스윕 | **다섯이 한 화면에 들어가는 크기**(③) · 「우쪽에 더 있음」이 언제 나오나 |
| **S 뷰어** | `QLPreviewController`를 **전체화면으로 제시** | 애플 뷰어가 어떻게 시작하나 → **크롬이 안 보이는 상태로 시작한다**(실측) |
| **U 뷰어2** | 같은 것을 **내비게이션에 얹었다** | **애플이 바에 무엇을 얹나** — 목록(≡) · 파일명 제목 · **마크업** · 공유 |

**쓰는 법** (탭 없이 꼴을 고른다 — `-ghostmode`):

```sh
cd native/tools/ghostlab && xcodegen generate
SIM=<이 기기의 UDID>                       # 맥미니 26.5 = 34A5033B-… (이름으로 쓰지 말 것)
xcodebuild -project GhostLab.xcodeproj -scheme GhostLab -destination "id=$SIM" \
  -derivedDataPath /tmp/gl build > /tmp/gl.log 2>&1; echo "EXIT=$?"; grep -c 'error:' /tmp/gl.log
xcrun simctl install $SIM /tmp/gl/Build/Products/Debug-iphonesimulator/GhostLab.app
xcrun simctl terminate $SIM kr.teri.GhostLab; xcrun simctl launch $SIM kr.teri.GhostLab -ghostmode Q
xcrun simctl io $SIM screenshot /tmp/Q.png
swift ../measure-ui.swift /tmp/Q.png 1100 1120     # 카드 높이 — 열 둘이 일치해야 한다
```

### ⛔ 이 꼴들이 재지 **못하는** 것 하나 — 적어 두지 않으면 다음이 속는다
**Dynamic Type**. 네모 안 글자를 **한 변의 비율**(`side * 0.15` 꼴)로 잡았으므로
**글자 크기를 키워도 안 커진다.** 앱은 접근성을 따를 것이고, 그러면 **62pt 네모가 위험하다**
(XXL 21pt · §3-B-4 ②). **이 랩으로 그 위험을 확인할 수 없다** — 재려면 랩부터 고쳐야 한다.

### ⛔ 실물 파일을 안 쓴다
표본 `82B1044B`는 맥미니에서 **dataless**이고 **받지 않는다**(사용자 2026-08-22).
네모 안의 사진·페이지는 **대역**이고, **정사각형이라 실물 비율이 필요 없다**(§3-A-5).
`S`·`U`가 쓰는 JPEG·PDF는 **그 자리에서 만든다**(`UIGraphicsImageRenderer`·`UIGraphicsPDFRenderer`).

### 꼴 넷을 더 더했다 — 종류 **여섯** · 문구 셋 · 물음 (2026-08-22 저녁)

| 꼴 | 무엇을 그리나 | 답한 것 |
|---|---|---|
| **Q 자료**(고침) | **종류 1·3·5·6** — 여섯째에서 넘친다 · **「더 있음」 표시 세 꼴**(㉮흐림+chevron ㉯흐림만 ㉰아래 점) | 여섯이면 **412pt가 필요하고 폭은 342** → 표시가 실제로 쓰인다 |
| **V 문구** | 문구 후보 셋 × 3 — ①못 만들었다 ②못 받았다 ③지원 안 됨 | ⛔ **글자만으로는 약하다**(62pt에서 9pt 남짓) |
| **X 아이콘** | 같은 셋을 **아이콘으로 갈랐다** — 손가락 · 구름 화살표 · 금지 | ✅ **글자를 안 읽어도 갈린다** · 글자를 아예 빼도 갈린다 |
| **W 물음** | `canPreview` 19가지 × (없는 파일/있는 파일) + `QLThumbnailGenerator` 6가지 | **확장자만 안다** · ⛔ **zip은 `canPreview` true인데 `.icon`** |

**⛔ 이 랩이 답할 수 없는 것 하나 더:** `canPreview`를 **dataless 파일**에 물어본 값.
「없는 파일」과 다르고(이름·크기가 있다) **재면 상태가 바뀔 위험이 있다.** → 설계 §3-D-1.
