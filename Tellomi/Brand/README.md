# Tellomi brand assets used by the iOS app

`https://github.com/tellomi/tellomi` was not readable from this checkout (GitHub API 404), so `docs/brand` (`logo-source-light.png`, `logo-source-dark.png`, the wordmark, and `scripts/brand/trace-logo.py`) could not be copied from there.

`logo.svg` is the traced file from the Android branch `cursor/tellomi-launcher-icon-74d8` at `TMessagesProj/tellomi/brand/logo.svg`, pending owner verification. The path data is unchanged. That file's own comment says it was traced from `logo-source-light.png` by `scripts/brand/trace-logo.py` and should not be hand-edited.

The generator scales that outline so the painted mark stays inside 75–80% of the icon square, including iPad 152×152 and 167×167. It does not edit the path.

The home screen, its dark and tinted appearances, and Settings ▸ Default use `#111113` on white (dark appearance is white on `#111113`) at 78%. The other Appearance slots, still the same bubble:

- Water (`New2`): teal `#0F766E` to cyan `#67E8F9` gradient
- Sunset (`New1`): pink `#F9A8D4` to purple `#6D28D9` gradient
- Classic: blue disc on a light field. Classic X: white ring on `#111113`
- Filled: the same blue to the edge of the square, with the mark at the top of the 75–80% range. Filled X is that structure on `#111113`
- Premium: star field on a night gradient. Turbo: gold gradient plus a star. Black: `#111113` plus a gold star

`AppIcon.xcassets/AppIcon.appiconset` is what the Bazel app icon uses. It is the full size set, including the iPad 76pt @2x (152×152) and 83.5pt @2x (167×167) icons, plus dark and tinted. `AppIcon.icon` is the Icon Composer document for the same glyph (`Assets/Logo.png`, the same scaled white raster of `logo.svg`, colored by the `solid` fills in `icon.json`). It is not compiled into the IPA: this rules_apple pin will not compile an `.appiconset` beside an `.icon`, and the `.icon` compile does not emit those two iPad sizes. `Alternates/` is the Appearance ▸ App Icon grid. Extensions do not have a separate icon target; they use the host app icon. Regenerate the PNGs with `python3 Tellomi/Brand/generate_icons.py` (`rsvg-convert` and Pillow required).
