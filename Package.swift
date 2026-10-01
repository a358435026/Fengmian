// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConversationTranslatorCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "ConversationTranslator", targets: ["ConversationTranslator"])],
    targets: [
        .target(name: "ConversationTranslator", path: "App",
            exclude: ["Design.swift", "APISettingsView.swift", "ArchiveView.swift", "Assets.xcassets", "ConversationModel.swift",
                      "ConversationTranslatorApp.swift", "ConversationView.swift", "KeyStore.swift", "SpeechService.swift"],
            sources: ["Types.swift", "DeepSeekClient.swift", "RecognitionPolicy.swift", "LocalArchive.swift"]),
        .testTarget(name: "ConversationTranslatorTests", dependencies: ["ConversationTranslator"], path: "Tests")
    ]
)
