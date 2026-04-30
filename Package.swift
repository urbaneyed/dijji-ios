// swift-tools-version: 5.9
// Dijji iOS SDK — three-module split mirroring the Android repo.
//
// dijji-core   → analytics + lifecycle auto-capture + custom events + crash chain.
//                Pure Foundation + UIKit. Required.
// dijji-push   → APNs token registration, UNUserNotificationCenter delegate
//                forwarder, deep-link routing. Optional (only pull if your
//                app uses push notifications).
// dijji-messages → In-app message renderer (banner / bottom-sheet / modal)
//                  on UIKit. dijji-core calls this via Objective-C runtime
//                  so apps that don't ship in-app messages don't pay the
//                  module's bundle cost. Optional.
//
// Min target: iOS 13. We use Combine + URLSession async features that
// require it. iOS 12 support could be added later by replacing async
// completion handlers — not worth the lift today.
import PackageDescription

let package = Package(
    name: "Dijji",
    // Primary target is iOS 13+. macOS 11+ is declared as a courtesy so
    // `swift build` (which compiles for the host) succeeds on macOS dev
    // machines — gives the build access to UserNotifications + UIKit
    // surrogates. Real consumers integrate via iOS — the macOS slice is
    // dev-only convenience.
    //
    // DijjiLiveActivity needs ActivityKit (iOS 16.1+) so its target
    // declares a higher floor. Apps on older iOS just don't link it.
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "DijjiCore",          targets: ["DijjiCore"]),
        .library(name: "DijjiPush",          targets: ["DijjiPush"]),
        .library(name: "DijjiMessages",      targets: ["DijjiMessages"]),
        .library(name: "DijjiLiveActivity",  targets: ["DijjiLiveActivity"]),
    ],
    targets: [
        .target(name: "DijjiCore",          path: "Sources/DijjiCore"),
        .target(name: "DijjiPush",          dependencies: ["DijjiCore"], path: "Sources/DijjiPush"),
        .target(name: "DijjiMessages",      dependencies: ["DijjiCore"], path: "Sources/DijjiMessages"),
        .target(name: "DijjiLiveActivity",  dependencies: ["DijjiCore"], path: "Sources/DijjiLiveActivity"),
        .testTarget(name: "DijjiCoreTests",     dependencies: ["DijjiCore"],     path: "Tests/DijjiCoreTests"),
        .testTarget(name: "DijjiMessagesTests", dependencies: ["DijjiMessages"], path: "Tests/DijjiMessagesTests"),
    ]
)
