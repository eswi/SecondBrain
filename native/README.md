# SecondBrain — 네이티브 v1 (Swift + SwiftUI)

Mac + iPhone 앱. 설계 정본은 저장소 루트 `second-brain-v0-spec.md` §0-A.

- `SecondBrainCore/` — 플랫폼 무관 코어(모델·조각파일 파서·추후 합치기 엔진). `swift test`로 검증.
- `Sources/App/` — SwiftUI 앱 셸(iOS·macOS 공유).
- `project.yml` — XcodeGen 정의. **`.xcodeproj`는 여기서 생성되며 git에 커밋하지 않는다.**

## 준비 (각 Mac 1회)
- Xcode (최신)
- XcodeGen: `brew install xcodegen`

## 프로젝트 생성 · 빌드 · 실행
```bash
cd native
xcodegen generate                 # project.yml → SecondBrain.xcodeproj (git 미추적)

# 시뮬레이터 빌드 (서명 불필요)
xcodebuild -project SecondBrain.xcodeproj -scheme SecondBrainApp-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 코어 테스트
cd SecondBrainCore && swift test
```
Xcode에서 열려면: `open SecondBrain.xcodeproj`.

## 두 Mac 번갈아 개발 시 주의
- `git pull` 먼저 → `xcodegen generate`(프로젝트 재생성) → 작업.
- `SecondBrain.xcodeproj` / `DerivedData/` / `.build/` 는 커밋 안 함(.gitignore).
- **실기기(iPhone) 설치**는 서명 필요: Xcode에서 타깃 → Signing & Capabilities → Team=본인 Apple ID, 자동 서명 ON (각 Mac 1회). 시뮬레이터는 서명 불필요.
