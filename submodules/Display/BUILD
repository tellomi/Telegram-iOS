load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "Display",
    module_name = "Display",
    srcs = glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
    	"//submodules/ObjCRuntimeUtils:ObjCRuntimeUtils",
    	"//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/AppBundle:AppBundle",
    	"//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Markdown:Markdown",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "DisplayTestsLib",
    testonly = True,
    srcs = glob(
        ["Tests/**/*.swift"],
        exclude = ["Tests/ListViewTopReorderTests.swift"],
    ),
    deps = [
        ":Display",
    ],
)

swift_library(
    name = "ListViewTopReorderTestsLib",
    testonly = True,
    srcs = ["Tests/ListViewTopReorderTests.swift"],
    deps = [
        ":Display",
    ],
)

# The runner MUST pin a real device/OS: the default runner picks an invalid
# device and the test process exits 15.
ios_test_runner(
    name = "DisplayTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

# xcode-27 PR runners have iPhone 17 on iOS 27.0. The 26.5 runner above is for
# the older Display suite and is not what this target uses.
ios_test_runner(
    name = "ListViewTopReorderTestRunner",
    device_type = "iPhone 17",
    os_version = "27.0",
)

ios_unit_test(
    name = "ListViewTopReorderTests",
    minimum_os_version = "15.0",
    runner = ":ListViewTopReorderTestRunner",
    deps = [
        ":ListViewTopReorderTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)

ios_unit_test(
    name = "DisplayTests",
    minimum_os_version = "15.0",
    runner = ":DisplayTestRunner",
    deps = [
        ":DisplayTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
