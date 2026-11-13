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
        "//submodules/TellomiLinks:TellomiLinks",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_test(
    name = "TellomiChatPrivacyTests",
    srcs = [
        "Sources/TellomiChatPrivacy.swift",
        "Tests/TellomiChatPrivacyTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)

# Host test of the tab copy, the post-link kill switch, and the contacts lookup.
# The rest of this module imports UIKit. Run with
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUIPreferences:TellomiTabNavigationDecisionsTests`.
swift_test(
    name = "TellomiTabNavigationDecisionsTests",
    srcs = [
        "Sources/TellomiTabNavigationDecisions.swift",
        "Sources/TellomiSettingsDecisions.swift",
        "Tests/TellomiTabNavigationDecisionsTests.swift",
        "Tests/TellomiSettingsDecisionsTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TellomiLinks:TellomiLinks",
    ],
)
