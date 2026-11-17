load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//build-system/bazel-utils:plist_fragment.bzl", "plist_fragment")

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

objc_library(
    name = "ListViewReorderTestHostLib",
    testonly = True,
    srcs = ["Tests/Host/main.m"],
    sdk_frameworks = ["UIKit"],
)

# rules_apple plisttool sets version_keys_required for ios_application and
# checks CFBundleVersion first, then CFBundleShortVersionString. "1" and "1.0"
# match the validators in tools/plisttool/plisttool.py.
plist_fragment(
    name = "ListViewReorderTestHostInfo",
    extension = "plist",
    template = """
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
    """,
)

# No provisioning profile: PR CI's configuration exports an empty provisioning
# package when profiles are disabled. Simulator signing does not need one.
ios_application(
    name = "ListViewReorderTestHost",
    testonly = True,
    bundle_id = "org.telegram.ListViewReorderTestHost",
    families = ["iphone"],
    minimum_os_version = "15.0",
    infoplists = [":ListViewReorderTestHostInfo"],
    deps = [":ListViewReorderTestHostLib"],
    visibility = ["//visibility:public"],
)

# Application tests install a host. On the PR runner a fresh iPhone 17 / 27.0
# simulator reports booted, then "could not be booted in 60s", then xcodebuild
# sits 150s without starting XCTest. The runner retries 3 times. The default
# moderate timeout (~300s) kills that loop on attempt 1 (Terminated: 15).
ios_unit_test(
    name = "ListViewTopReorderTests",
    minimum_os_version = "15.0",
    runner = ":ListViewTopReorderTestRunner",
    test_host = ":ListViewReorderTestHost",
    timeout = "long",
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
