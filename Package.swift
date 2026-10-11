// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "ImagePro",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ImagePro", targets: ["ImagePro"])],
    targets: [
        .systemLibrary(name: "CZlib"),
        .target(name: "CInpaintingTools", publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-I\(root)/ThirdParty/ONNXRuntime/include"])]),
        .executableTarget(name: "ImagePro", dependencies: ["CZlib", "CInpaintingTools"], exclude: ["Resources"], resources: [.process("Localization"), .copy("Legal"), .copy("InpaintingModels")]),
        .testTarget(name: "ImageProTests", dependencies: ["ImagePro"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
