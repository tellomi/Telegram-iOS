load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TellomiDiscover",
    module_name = "TellomiDiscover",
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

# Host tests. The feed screen's UIKit is not in this target.
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TellomiDiscover:TellomiDiscoverTests`
swift_test(
    name = "TellomiChatLinkPreviewTests",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        "Tests/TellomiChatLinkPreviewTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)

swift_test(
    name = "TellomiDiscoverTests",
    srcs = glob([
        "Sources/**/*.swift",
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
)
