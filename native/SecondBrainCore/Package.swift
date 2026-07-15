// swift-tools-version:6.0
import PackageDescription

// 코어 로직(플랫폼 무관): 조각 파일 파싱·데이터 모델·(추후)합치기 엔진.
// UI 없음 → iOS/macOS 앱이 공유하고, `swift test`로 CLI에서 검증 가능(Xcode 프로젝트 불필요).
let package = Package(
    name: "SecondBrainCore",
    products: [
        .library(name: "SecondBrainCore", targets: ["SecondBrainCore"]),
    ],
    targets: [
        .target(name: "SecondBrainCore"),
        .testTarget(name: "SecondBrainCoreTests", dependencies: ["SecondBrainCore"]),
    ]
)
