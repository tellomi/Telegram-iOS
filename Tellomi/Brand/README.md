# Tellomi brand assets used by the iOS app

`https://github.com/tellomi/tellomi` was not readable from this checkout (GitHub API 404), so `docs/brand` (`logo-source-light.png`, `logo-source-dark.png`, the wordmark, and `scripts/brand/trace-logo.py`) could not be copied from there.

`logo.svg` is the traced file from the Android branch `cursor/tellomi-launcher-icon-74d8` at `TMessagesProj/tellomi/brand/logo.svg`, pending owner verification. The path data is unchanged. That file's own comment says it was traced from `logo-source-light.png` by `scripts/brand/trace-logo.py` and should not be hand-edited.

Colors applied around that outline, not a new drawing:

- Light: `#111113` on white
- Dark: `#FFFFFF` on `#111113`
- Tinted: black on white, for the iOS 18 tinted appearance

`AppIcon.icon` is what the Bazel app icon uses. `AppIcon.appiconset` is the full size set, including dark and tinted. `Alternates/` fills the existing Settings icon slots with the same logo. Extensions do not have a separate icon target; they use the host app icon. Regenerate the PNGs with `python3 Tellomi/Brand/generate_icons.py` (`rsvg-convert` required).
