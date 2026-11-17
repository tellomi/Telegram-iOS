load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TelegramUIPreferences",
    module_name = "TelegramUIPreferences",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host test of the tab-bar rules. No UIKit.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUIPreferences:TellomiTabBarPreferencesTests`.
swift_test(
    name = "TellomiTabBarPreferencesTests",
    srcs = [
        "Sources/TellomiTabBarPreferences.swift",
        "Tests/TellomiTabBarPreferencesTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
