load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TellomiWallpapers",
    module_name = "TellomiWallpapers",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host test. The catalog is Foundation only.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TellomiWallpapers:TellomiWallpapersTests`.
swift_test(
    name = "TellomiWallpapersTests",
    srcs = [
        "Tests/TellomiWallpapersTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":TellomiWallpapers",
    ],
)
