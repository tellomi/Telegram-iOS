load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "CrashSignalHandler",
    module_name = "CrashSignalHandler",
    enable_modules = True,
    srcs = ["Sources/TellomiCrashSignalHandler.m"],
    hdrs = ["PublicHeaders/CrashSignalHandler/TellomiCrashSignalHandler.h"],
    includes = ["PublicHeaders"],
    copts = ["-Werror"],
    sdk_frameworks = ["Foundation"],
)

swift_library(
    name = "CrashReporting",
    module_name = "CrashReporting",
    srcs = glob(["Sources/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [":CrashSignalHandler"],
    visibility = ["//visibility:public"],
)
