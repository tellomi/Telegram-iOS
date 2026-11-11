
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "MtProtoKit",
    enable_modules = True,
    module_name = "MtProtoKit",
    srcs = glob([
        "Sources/**/*.m",
        "Sources/**/*.c",
        "Sources/**/*.h",
    ]),
    copts = [
        "-Werror",
    ],
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    deps = [
        "//submodules/EncryptionProvider:EncryptionProvider",
    ],
    sdk_frameworks = [
        "Foundation",
        "Security",
        "SystemConfiguration",
        "CFNetwork",
    ],
    sdk_dylibs = [
        "libz",
    ],
    visibility = [
        "//visibility:public",
    ],
)

load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# Module-private headers, exposed to the tests only, so a test can
# `#import "MTInternalMessageParser.h"` the way the module's own sources do.
cc_test(
    name = "GCDAsyncSocketStreamCloseTests",
    srcs = [
        "Sources/GCDAsyncSocketStreamClose.c",
        "Sources/GCDAsyncSocketStreamClose.h",
        "Tests/GCDAsyncSocketStreamCloseTests.c",
    ],
    includes = [
        "Sources",
    ],
)

objc_library(
    name = "MtProtoKitPrivateHeaders",
    testonly = True,
    hdrs = glob([
        "Sources/**/*.h",
    ]),
    includes = [
        "Sources",
    ],
    deps = [
        ":MtProtoKit",
    ],
)

objc_library(
    name = "MtProtoKitTestsLib",
    testonly = True,
    srcs = glob(
        [
            "Tests/**/*.m",
            "Tests/**/*.h",
        ],
        exclude = ["Tests/GCDAsyncSocketCloseTests.m"],
    ),
    deps = [
        ":MtProtoKit",
        ":MtProtoKitPrivateHeaders",
    ],
    sdk_frameworks = [
        "XCTest",
    ],
)

ios_test_runner(
    name = "MtProtoKitTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

objc_library(
    name = "GCDAsyncSocketCloseTestsLib",
    testonly = True,
    srcs = ["Tests/GCDAsyncSocketCloseTests.m"],
    deps = [
        ":MtProtoKit",
        ":MtProtoKitPrivateHeaders",
    ],
    sdk_frameworks = [
        "XCTest",
    ],
)

ios_test_runner(
    name = "GCDAsyncSocketCloseTestRunner",
    device_type = "iPhone 17",
    os_version = "27.0",
)

ios_unit_test(
    name = "GCDAsyncSocketCloseTests",
    minimum_os_version = "15.0",
    runner = ":GCDAsyncSocketCloseTestRunner",
    deps = [
        ":GCDAsyncSocketCloseTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)

ios_unit_test(
    name = "MtProtoKitTests",
    minimum_os_version = "15.0",
    runner = ":MtProtoKitTestRunner",
    deps = [
        ":MtProtoKitTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
