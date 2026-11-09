load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MomentsUI",
    module_name = "MomentsUI",
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
        "//submodules/Postbox",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/HorizontalTabsComponent",
        "//submodules/ContextUI",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/MediaPickerUI",
        "//submodules/TelegramUI/Components/PeerReportScreen",
        "//submodules/DeviceLocationManager",
        "//submodules/TelegramUI/Components/PeerInfo/PeerInfoPaneNode",
    ],
    visibility = ["//visibility:public"],
)
