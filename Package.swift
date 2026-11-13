// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tendedero",
    platforms: [.macOS(.v14)],
    targets: [
        // Resources holds the translations. scripts/build-app.sh copies them
        // into the app, so SwiftPM leaves them alone.
        // ExceptionCatch.m is compiled into the executable. The header is
        // excluded from the Swift module (MarkupLocal calls it via
        // @_silgen_name) and found by clang through headerSearchPath.
        .executableTarget(
            name: "Tendedero",
            path: "Sources/Tendedero",
            exclude: ["Resources", "ExceptionCatch.h"],
            cSettings: [
                .headerSearchPath(".")
            ]
        )
    ]
)
