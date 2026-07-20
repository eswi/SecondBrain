// swift-tools-version:6.0
import PackageDescription

// 일회성 마이그레이션 CLI. 앱 Xcode 프로젝트와 분리된 별도 패키지 → 앱 빌드에 영향 0.
// 해시·병합·검증을 앱과 '동일한' SecondBrainCore 코드로 수행(재구현 divergence 방지).
let package = Package(
    name: "sb-migrate",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../SecondBrainCore")],
    targets: [
        .executableTarget(
            name: "sb-migrate",
            dependencies: [.product(name: "SecondBrainCore", package: "SecondBrainCore")]
        )
    ]
)
