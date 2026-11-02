# Tellomi icons, phase 1

`mapping.csv` is the list of asset-catalog imagesets replaced with MingCute.
`line` reads `MingCute/svg/regular`, `fill` reads `MingCute/svg/filled`.
The app tints the PDF at runtime, so each file is black on a clear page and
keeps the imageset's point size. An empty canvas column fits the glyph into
the original ink box. `WxH` is a new imageset. `match:<asset>` copies that
imageset's box, which is how a selected (fill) icon sits on the same canvas
as its line icon.

Regenerate after editing the csv:

```sh
python3 Tellomi/Icons/generate_icons.py
```

Needs `pdftoppm` (poppler), plus the Python packages `cairosvg`, `pypdf`, and `Pillow`.
Measure the existing art before replacing it. Running the script again measures
the PDFs it just wrote.

The main tab bar uses the line image at rest and the fill image when selected,
and scales from 0.86 to 1. The `Tab*` Lottie files those tabs and the attach
menu used to play are not in the bundle. The attach menu does the same
line/fill swap. Chat-list swipe actions use the static images under
`Chat List/Swipe`.

Settings has no open-source licenses screen, so MingCute is recorded here
(`MingCute/LICENSE`, `MingCute/NOTICE`) rather than as a new settings row.

Login art is not in the mapping. Holiday tab icons, the blend textures
`Item List/Icons/Gradient` and `Backdrop`, and the Gram mark are not either.

Phase 2 and 3 are the imagesets still not listed in `mapping.csv`: the rest of
the context menu (table cells, report kinds, quality badges), message bubbles,
the media editor, camera, stories, wallet, and the Lottie clips that are not
`Tab*` (the composer emoji/sticker/keyboard morphs, and the mic/video morph).
