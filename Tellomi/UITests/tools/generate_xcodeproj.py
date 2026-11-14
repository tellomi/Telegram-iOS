#!/usr/bin/env python3
"""Write Tellomi/UITests/TellomiClientUITests.xcodeproj.

The host target compiles a stub, then a run script replaces that product
with the prebuilt simulator app in TELLOMI_PREBUILT_APP. The UI test
target is the only Swift the shard compiles.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def xid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def main() -> None:
    sources = sorted((ROOT / "Sources").glob("*.swift"))
    if not sources:
        raise SystemExit("no UI test sources")
    host_file = xid("file:Host/main.swift")
    host_plist = xid("file:Host/Info.plist")
    test_files = [(path.name, xid(f"file:Sources/{path.name}")) for path in sources]
    host_target = xid("target:TellomiHost")
    test_target = xid("target:TellomiClientUITests")
    project_id = xid("project")
    host_product = xid("product:Telegram.app")
    test_product = xid("product:TellomiClientUITests.xctest")
    host_sources_phase = xid("phase:host-sources")
    test_sources_phase = xid("phase:test-sources")
    host_script_phase = xid("phase:host-script")
    test_frameworks_phase = xid("phase:test-frameworks")
    xctest = xid("file:XCTest.framework")
    xctest_build = xid("build:XCTest.framework")
    host_config_list = xid("configs:host")
    test_config_list = xid("configs:test")
    project_config_list = xid("configs:project")
    debug_project = xid("config:project:Debug")
    release_project = xid("config:project:Release")
    debug_host = xid("config:host:Debug")
    release_host = xid("config:host:Release")
    debug_test = xid("config:test:Debug")
    release_test = xid("config:test:Release")
    main_group = xid("group:main")
    host_group = xid("group:host")
    sources_group = xid("group:sources")
    products_group = xid("group:products")
    frameworks_group = xid("group:frameworks")

    def file_ref(fid: str, name: str, path: str, kind: str) -> str:
        return (
            f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; "
            f"includeInIndex = 1; lastKnownFileType = {kind}; path = {path}; "
            f"sourceTree = \"<group>\"; }};"
        )

    file_refs = [
        file_ref(host_file, "main.swift", "main.swift", "sourcecode.swift"),
        file_ref(host_plist, "Info.plist", "Info.plist", "text.plist.xml"),
        (
            f"\t\t{xctest} /* XCTest.framework */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = wrapper.framework; name = XCTest.framework; "
            f"path = System/Library/Frameworks/XCTest.framework; sourceTree = SDKROOT; }};"
        ),
    ]
    for name, fid in test_files:
        file_refs.append(file_ref(fid, name, name, "sourcecode.swift"))
    file_refs.append(
        f"\t\t{host_product} /* Telegram.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Telegram.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    file_refs.append(
        f"\t\t{test_product} /* TellomiClientUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TellomiClientUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    build_files = []
    host_build = xid("build:Host/main.swift")
    build_files.append(
        f"\t\t{host_build} /* main.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {host_file} /* main.swift */; }};"
    )
    test_builds = []
    for name, fid in test_files:
        bid = xid(f"build:Sources/{name}")
        test_builds.append(bid)
        build_files.append(
            f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};"
        )
    build_files.append(
        f"\t\t{xctest_build} /* XCTest.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {xctest} /* XCTest.framework */; }};"
    )

    host_build_ids = "\n".join(f"\t\t\t\t{host_build} /* main.swift in Sources */," for _ in [0])
    test_build_ids = "\n".join(f"\t\t\t\t{bid} /* {name} in Sources */," for (name, _), bid in zip(test_files, test_builds))
    source_children = "\n".join(f"\t\t\t\t{fid} /* {name} */," for name, fid in test_files)

    common_settings = """\
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				IPHONEOS_DEPLOYMENT_TARGET = 16.4;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				TARGETED_DEVICE_FAMILY = 1;
				SWIFT_VERSION = 5.0;
"""

    script = r"""
set -euo pipefail
if [[ -z "${TELLOMI_PREBUILT_APP:-}" ]]; then
  echo "TELLOMI_PREBUILT_APP must point at the simulator Telegram.app"
  exit 1
fi
if [[ ! -d "${TELLOMI_PREBUILT_APP}" ]]; then
  echo "TELLOMI_PREBUILT_APP is not a directory"
  exit 1
fi
dest="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
rm -rf "${dest}"
ditto "${TELLOMI_PREBUILT_APP}" "${dest}"
""".strip("\n")
    # PBX shell scripts store newlines as escaped sequences.
    script_escaped = script.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{test_frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{xctest_build} /* XCTest.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{host_group} /* Host */ = {{
			isa = PBXGroup;
			children = (
				{host_file} /* main.swift */,
				{host_plist} /* Info.plist */,
			);
			path = Host;
			sourceTree = "<group>";
		}};
		{sources_group} /* Sources */ = {{
			isa = PBXGroup;
			children = (
{source_children}
			);
			path = Sources;
			sourceTree = "<group>";
		}};
		{frameworks_group} /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
				{xctest} /* XCTest.framework */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		}};
		{products_group} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{host_product} /* Telegram.app */,
				{test_product} /* TellomiClientUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{main_group} = {{
			isa = PBXGroup;
			children = (
				{host_group} /* Host */,
				{sources_group} /* Sources */,
				{frameworks_group} /* Frameworks */,
				{products_group} /* Products */,
			);
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{host_target} /* TellomiHost */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {host_config_list} /* Build configuration list for PBXNativeTarget "TellomiHost" */;
			buildPhases = (
				{host_sources_phase} /* Sources */,
				{host_script_phase} /* Replace with prebuilt app */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TellomiHost;
			productName = Telegram;
			productReference = {host_product} /* Telegram.app */;
			productType = "com.apple.product-type.application";
		}};
		{test_target} /* TellomiClientUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {test_config_list} /* Build configuration list for PBXNativeTarget "TellomiClientUITests" */;
			buildPhases = (
				{test_sources_phase} /* Sources */,
				{test_frameworks_phase} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TellomiClientUITests;
			productName = TellomiClientUITests;
			productReference = {test_product} /* TellomiClientUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{test_target} = {{
						TestTargetID = {host_target};
					}};
				}};
			}};
			buildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "TellomiClientUITests" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {main_group};
			productRefGroup = {products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{host_target} /* TellomiHost */,
				{test_target} /* TellomiClientUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXShellScriptBuildPhase section */
		{host_script_phase} /* Replace with prebuilt app */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
			);
			name = "Replace with prebuilt app";
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "{script_escaped}";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{host_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{host_build_ids}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{test_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{test_build_ids}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{debug_project} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{common_settings}
			}};
			name = Debug;
		}};
		{release_project} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{common_settings}
			}};
			name = Release;
		}};
		{debug_host} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGNING_ALLOWED = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Host/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = app.tellomi.chat;
				PRODUCT_NAME = Telegram;
			}};
			name = Debug;
		}};
		{release_host} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGNING_ALLOWED = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Host/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = app.tellomi.chat;
				PRODUCT_NAME = Telegram;
			}};
			name = Release;
		}};
		{debug_test} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGNING_ALLOWED = NO;
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = app.tellomi.chat.uitests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_TARGET_NAME = TellomiHost;
			}};
			name = Debug;
		}};
		{release_test} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGNING_ALLOWED = NO;
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = app.tellomi.chat.uitests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_TARGET_NAME = TellomiHost;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{project_config_list} /* Build configuration list for PBXProject "TellomiClientUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_project} /* Debug */,
				{release_project} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
		{host_config_list} /* Build configuration list for PBXNativeTarget "TellomiHost" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_host} /* Debug */,
				{release_host} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
		{test_config_list} /* Build configuration list for PBXNativeTarget "TellomiClientUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_test} /* Debug */,
				{release_test} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""
    project = ROOT / "TellomiClientUITests.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text(pbx, encoding="utf-8")
    scheme_dir = project / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{host_target}"
               BuildableName = "Telegram.app"
               BlueprintName = "TellomiHost"
               ReferencedContainer = "container:TellomiClientUITests.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "TellomiClientUITests.xctest"
               BlueprintName = "TellomiClientUITests"
               ReferencedContainer = "container:TellomiClientUITests.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "TellomiClientUITests.xctest"
               BlueprintName = "TellomiClientUITests"
               ReferencedContainer = "container:TellomiClientUITests.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{host_target}"
            BuildableName = "Telegram.app"
            BlueprintName = "TellomiHost"
            ReferencedContainer = "container:TellomiClientUITests.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{host_target}"
            BuildableName = "Telegram.app"
            BlueprintName = "TellomiHost"
            ReferencedContainer = "container:TellomiClientUITests.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (scheme_dir / "TellomiClientUITests.xcscheme").write_text(scheme, encoding="utf-8")
    print(project)


if __name__ == "__main__":
    main()
