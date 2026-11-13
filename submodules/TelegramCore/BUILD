load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TellomiDiscover:TellomiDiscover",
        "//submodules/TellomiWallpapers:TellomiWallpapers",
        "//submodules/TellomiLinks:TellomiLinks",
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/MediaPreuploadRegistry:MediaPreuploadRegistry",
        "//submodules/WebProxyTransport:WebProxyTransport",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
        "//submodules/MurMurHash32",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "TelegramCoreTestsLib",
    testonly = True,
    srcs = glob(
        ["Tests/**/*.swift"],
        exclude = [
            "Tests/TellomiSignUpAvatarTests.swift",
            "Tests/TellomiFeatureGateTests.swift",
        ],
    ),
    deps = [
        ":TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/Postbox:Postbox",
        "//submodules/WebProxyTransport:WebProxyTransport",
        # InstantPageButtonLinkStyleTests round-trips through the flatc-generated TelegramCore_* types.
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
    ],
)

ios_test_runner(
    name = "TelegramCoreTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

# Host test. The decision does not touch the session.
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramCore:TellomiSignUpAvatarTests`
swift_test(
    name = "EphemeralMediaLifecycleTests",
    srcs = [
        "Sources/Tellomi/EphemeralMediaLifecycle.swift",
        "Tests/EphemeralMediaLifecycleTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)

swift_test(
    name = "TellomiNativeBatchTests",
    srcs = [
        "Sources/Tellomi/TellomiNativeBatch.swift",
        "Tests/TellomiNativeBatchTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)

# Host test. Compiles the gate with the SyncCore types it names.
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramCore:TellomiFeatureGateTests`
swift_test(
    name = "TellomiFeatureGateTests",
    srcs = [
        "Sources/TellomiFeatureGate.swift",
        "Sources/SyncCore/SyncCore_AppConfiguration.swift",
        "Sources/SyncCore/SyncCore_JSON.swift",
        "Sources/SyncCore/SyncCore_Namespaces.swift",
        "Sources/TelegramEngine/Utils/StringCodingKey.swift",
        "Tests/TellomiFeatureGateTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Postbox:Postbox",
    ],
)

swift_test(
    name = "TellomiSignUpAvatarTests",
    srcs = [
        "Sources/Tellomi/TellomiSignUpAvatar.swift",
        "Tests/TellomiSignUpAvatarTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)

ios_unit_test(
    name = "TelegramCoreTests",
    minimum_os_version = "15.0",
    runner = ":TelegramCoreTestRunner",
    deps = [
        ":TelegramCoreTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
