// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "CrisperDsp",
    platforms: [.iOS("12.0"), .macOS("10.14")],
    products: [.library(name: "CrisperDsp", targets: ["CrisperDsp"])],
    targets: [
        .target(
            name: "CrisperDsp",
            path: ".",
            exclude: ["tools", "README.md", "CMakeLists.txt", "LICENSE", "wsola/UPSTREAM.md"],
            sources: [
                "crisper_dsp.cpp", "wsola/wsola.cpp",
                "vendor/sonic/sonic.c", "vendor/pffft/pffft.c", "vendor/pffft/fftpack.c",
                "vendor/bungee/src/Assert.cpp", "vendor/bungee/src/Fourier.cpp",
                "vendor/bungee/src/Grain.cpp", "vendor/bungee/src/Grains.cpp",
                "vendor/bungee/src/Input.cpp", "vendor/bungee/src/Instrumentation.cpp",
                "vendor/bungee/src/Output.cpp", "vendor/bungee/src/Partials.cpp",
                "vendor/bungee/src/Stretch.cpp", "vendor/bungee/src/Stretcher.cpp",
                "vendor/bungee/src/Synthesis.cpp", "vendor/bungee/src/Timing.cpp",
                "vendor/bungee/src/Window.cpp", "vendor/bungee/src/version.cpp"
            ],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("vendor/pffft"), .headerSearchPath("vendor/sonic")],
            cxxSettings: [
                .headerSearchPath("."), .headerSearchPath("vendor"),
                .headerSearchPath("vendor/bungee"), .headerSearchPath("vendor/eigen"),
                .headerSearchPath("vendor/pffft"), .headerSearchPath("vendor/sonic"),
                .headerSearchPath("vendor/signalsmith-stretch"),
                .define("EIGEN_MPL2_ONLY", to: "1"), .define("EIGEN_DONT_PARALLELIZE", to: "1"),
                .define("BUNGEE_SELF_TEST", to: "0"), .define("BUNGEE_VISIBILITY", to: ""),
                .define("BUNGEE_VERSION", to: "\"61f52bf34be577d189d388772ddfa3696dee77d8\""),
                .define("eigen_assert", to: "BUNGEE_ASSERT1")
            ],
            linkerSettings: [.linkedLibrary("c++")]
        )
    ],
    cxxLanguageStandard: .cxx20
)
