load("@build_bazel_rules_apple//apple:ios.bzl", "ios_ui_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# The workflow does not run this target. It builds //Telegram once with
# Make.py and compiles this package's Sources with xcodebuild, because
# `bazel test` would rebuild the app on every shard. The target stays in
# the graph so the UI tests are a normal ios_ui_test against the app.
ios_test_runner(
    name = "TellomiUITestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

swift_library(
    name = "TellomiClientUITestsLib",
    testonly = True,
    srcs = glob(["Sources/**/*.swift"]),
)

ios_ui_test(
    name = "TellomiClientUITests",
    bundle_id = "app.tellomi.chat.uitests",
    minimum_os_version = "16.4",
    runner = ":TellomiUITestRunner",
    tags = ["manual"],
    test_host = "//Telegram:Telegram",
    deps = [":TellomiClientUITestsLib"],
)
