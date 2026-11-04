load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "FeedScreen",
    module_name = "TellomiFeedScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/AppBundle",
        "//submodules/ContextUI",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUIPreferences",
        "//submodules/TellomiDiscover:TellomiDiscover",
        "//submodules/Geocoding",
        "//submodules/TelegramUI/Components/ShareWithPeersScreen",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
        "//submodules/TelegramUI/Components/PeerReportScreen",
        "//submodules/UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
