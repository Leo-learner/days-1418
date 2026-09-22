// swift-tools-version: 6.0
// 只是为了让 Xcode / 编辑器认得这个工程；真正的打包请用 ./build.sh
import PackageDescription

let package = Package(
    name: "Days1418",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Days1418", path: "Sources")
    ],
    swiftLanguageModes: [.v5]
)
