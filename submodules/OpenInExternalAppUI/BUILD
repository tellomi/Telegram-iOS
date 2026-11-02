load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "OpenInExternalAppUI",
    module_name = "OpenInExternalAppUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/UrlEscaping:UrlEscaping",
        "//submodules/AppBundle:AppBundle",
        "//submodules/Components/BundleIconComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Components/SheetComponent",
        "//submodules/Components/ViewControllerComponent",
        "//submodules/TelegramUI/Components/ButtonComponent",
        "//submodules/TelegramUI/Components/GlassBarButtonComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host test of the map URL builders. The rest of this module needs UIKit.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/OpenInExternalAppUI:TellomiMapOpenInTests`.
swift_test(
    name = "TellomiMapOpenInTests",
    srcs = [
        "Sources/TellomiMapOpenIn.swift",
        "Tests/TellomiMapOpenInTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/UrlEscaping",
    ],
)
