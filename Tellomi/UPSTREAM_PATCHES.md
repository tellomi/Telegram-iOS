# Upstream patches for the Tellomi fork

Edits under `Telegram/` and `BUILD.bazel` that exist so Tellomi assets can ship. The artwork itself stays in `Tellomi/Brand/`.

| File | Change |
| --- | --- |
| `BUILD.bazel` | Exports `Tellomi/version`. Adds `//:TellomiAppIcon` and `//:TellomiAlternate_*` filegroups over `Tellomi/Brand`. |
| `Telegram/BUILD` | `app_icons` is `//:TellomiAppIcon` instead of `Telegram-iOS/TellomiPlaceholder.icon`. `alternate_icons` read `Tellomi/Brand/Alternates` instead of `Telegram-iOS/*.alticon`. |
| `Telegram/BUILD` `VersionInfoPlist` | `CFBundleShortVersionString` is read from `Tellomi/version`, not `versions.json`. |
| `versions.json` | `app` matches `Tellomi/version` (`13.1.2`) so the watch patch script and the plist agree. |

`Telegram-iOS/*.alticon`, `AppIcons.xcassets`, `DefaultAppIcon.xcassets`, and `TellomiPlaceholder.icon` are still in the tree and are not the icons the Bazel app packages.
