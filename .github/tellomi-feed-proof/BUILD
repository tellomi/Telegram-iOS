load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# Exists only so a proof compile can build FeedScreen through an ios_unit_test.
# A bare swift_library is compiled with the Mac host SDK (Tests/ComposerHarness/CLAUDE.md).
swift_library(
    name = "TellomiFeedProofTestsLib",
    testonly = True,
    srcs = ["Proof.swift"],
    copts = [
        "-suppress-warnings",
    ],
    deps = [
        "//submodules/TelegramUI/Components/Tellomi/FeedScreen:FeedScreen",
    ],
)

ios_test_runner(
    name = "TellomiFeedProofRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "TellomiFeedProofTests",
    minimum_os_version = "15.0",
    runner = ":TellomiFeedProofRunner",
    tags = ["manual"],
    deps = [
        ":TellomiFeedProofTestsLib",
    ],
)
