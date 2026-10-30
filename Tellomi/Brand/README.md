# Tellomi brand assets used by the iOS app

`https://github.com/tellomi/tellomi` was not readable from this checkout (GitHub API 404), so `docs/brand` (`logo-source-light.png`, `logo-source-dark.png`, the wordmark, and `scripts/brand/trace-logo.py`) could not be copied from there.

`logo.svg` is the traced file from the Android branch `cursor/tellomi-launcher-icon-74d8` at `TMessagesProj/tellomi/brand/logo.svg`, pending owner verification. The path data is unchanged. That file's own comment says it was traced from `logo-source-light.png` by `scripts/brand/trace-logo.py` and should not be hand-edited.

The generator scales that outline so the painted mark is 78% of the icon square (inside 75–80%), centered, on every size including iPad 152×152 and 167×167. It does not edit the path.

Colors applied around that outline, not a new drawing:

- Home screen and Settings ▸ Default: `#111113` on white
- Dark appearance, Default X, Classic X, Filled X, and Black: `#FFFFFF` on `#111113`
- Tinted: black on white, for the iOS 18 tinted appearance
- Classic `#2F80ED`, Filled `#3B5BDB`, Sunset (`New1`) `#F15A24`, Aqua (`New2`) `#0AA1B5`, Premium `#7C3AED`, Turbo `#F5B301` with a `#111113` mark

`AppIcon.xcassets/AppIcon.appiconset` is what the Bazel app icon uses. It is the full size set, including the iPad 76pt @2x (152×152) and 83.5pt @2x (167×167) icons, plus dark and tinted. `AppIcon.icon` is the Icon Composer document for the same glyph (`Assets/Logo.png`, the same scaled white raster of `logo.svg`, colored by the `solid` fills in `icon.json`). It is not compiled into the IPA: this rules_apple pin will not compile an `.appiconset` beside an `.icon`, and the `.icon` compile does not emit those two iPad sizes. `Alternates/` is the Appearance ▸ App Icon grid. Extensions do not have a separate icon target; they use the host app icon. Regenerate the PNGs with `python3 Tellomi/Brand/generate_icons.py` (`rsvg-convert` and Pillow required).
