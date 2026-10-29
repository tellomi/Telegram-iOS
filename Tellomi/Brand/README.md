# Tellomi brand assets used by the iOS app

`https://github.com/tellomi/tellomi` is not readable from this checkout (GitHub API 404), so `docs/brand` itself cannot be copied. The Android client documents `TMessagesProj/tellomi/brand/logo.svg` as that file (`docs/brand/logo.svg`, traced by `scripts/brand/trace-logo.py`). `Tellomi/Brand/logo.svg` is a byte-for-byte copy of it. Do not hand-edit the path data.

Colors applied around that outline, not a new drawing:

- Light: `#111113` on white
- Dark: `#FFFFFF` on `#111113`
- Tinted: black on white, for the iOS 18 tinted appearance

`AppIcon.icon` is what the Bazel app icon uses. Its layer is `Assets/Logo.png`, a white raster of `logo.svg`; `icon.json` paints it with `solid` fills (`#111113` on white, white on `#111113`). `AppIcon.appiconset` and `Alternates/` are every other size, also rendered from `logo.svg`. Regenerating them with `generate_icons.py` produced no pixel change, so those files were already this mark. Extensions do not have a separate icon target; they use the host app icon. Regenerate the PNGs with `python3 Tellomi/Brand/generate_icons.py` (`rsvg-convert` required).
