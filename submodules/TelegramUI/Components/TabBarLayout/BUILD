load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "TabBarLayout",
    module_name = "TabBarLayout",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "TabBarLayoutTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":TabBarLayout",
        "//submodules/Display",
    ],
)

# The runner MUST pin a real device/OS: the default runner picks an invalid
# device and the test process exits 15. The xcode-27 CI image has an iPhone 17
# on iOS 27.0. iOS 27.1 on that image only has iPhone Duo, and creating an
# iPhone 17 there exits 15.
ios_test_runner(
    name = "TabBarLayoutTestRunner",
    device_type = "iPhone 17",
    os_version = "27.0",
)

ios_unit_test(
    name = "TabBarLayoutTests",
    minimum_os_version = "15.0",
    runner = ":TabBarLayoutTestRunner",
    deps = [
        ":TabBarLayoutTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
