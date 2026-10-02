// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaRuntime",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LlamaRuntime", targets: ["llama"])],
    targets: [.binaryTarget(
        name: "llama",
        path: "Frameworks/llama.xcframework"
    )]
)
