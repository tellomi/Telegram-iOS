load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "ChatMessageInteractiveInstantVideoNode",
    module_name = "ChatMessageInteractiveInstantVideoNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        #"-Xfrontend", "-debug-time-function-bodies"
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/RadialStatusNode",
        "//submodules/SemanticStatusNode",
        "//submodules/PhotoResources",
        "//submodules/TelegramUniversalVideoContent",
        "//submodules/FileMediaResourceStatus",
        "//submodules/Components/HierarchyTrackingLayer",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/AudioTranscriptionButtonComponent",
        "//submodules/UndoUI",
        "//submodules/TelegramNotices",
        "//submodules/Markdown",
        "//submodules/TextFormat",
        "//submodules/InvisibleInkDustNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageForwardInfoNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode",
        "//submodules/TelegramUI/Components/Chat/InstantVideoRadialStatusNode",
        "//submodules/TelegramUI/Components/Chat/ChatInstantVideoMessageDurationNode",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host test of the round-video transcript decision. It does not link the node.
swift_test(
    name = "RoundVideoTranscriptionDecisionTests",
    srcs = [
        "Sources/RoundVideoTranscriptionDecision.swift",
        "Tests/RoundVideoTranscriptionDecisionTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
