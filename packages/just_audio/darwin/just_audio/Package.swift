// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "just_audio",
    platforms: [
        .iOS("12.0"),
        .macOS("10.14")
    ],
    products: [
        .library(name: "just-audio", targets: ["just_audio"])
    ],
    dependencies: [.package(path: "../../native/crisper_dsp")],
    targets: [
        .target(
            name: "just_audio",
            dependencies: [.product(name: "CrisperDsp", package: "crisper_dsp")],
            // CocoaPods compiles the wrappers; SwiftPM compiles the same
            // shared sources once through the local CrisperDsp dependency.
            exclude: ["portable_dsp"],
            cSettings: [
                .headerSearchPath("include/just_audio")
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
