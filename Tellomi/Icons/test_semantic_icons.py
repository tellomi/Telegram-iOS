#!/usr/bin/env python3
"""Pins the sticker and GIF glyphs, and the checks that are already correct.

The mapped MingCute sticker is a blank note. The mapped GIF is a film strip.
The composer, menus, and settings badges use the semantic imagesets instead.
Those imagesets are not rows in mapping.csv, so generate_icons.py does not
rewrite them.

The round video button stays the camcorder. Chat-list checks are drawn, one
stroke for sent and a second stroke only for read. The send arrow is white
on the accent disc, and the media-picker disc is #111111 with a white arrow.
"""

import os
import re
import unittest
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SEMANTIC = os.path.join(ROOT, "Tellomi", "Icons", "semantic")
XCASSETS = os.path.join(ROOT, "submodules", "TelegramUI", "Images.xcassets")

STICKER_CALLS = [
    "submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChat.swift",
    "submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift",
    "submodules/AttachmentUI/Sources/AttachmentPanel.swift",
    "submodules/PremiumUI/Sources/PremiumIntroScreen.swift",
    "submodules/StickerPackPreviewUI/Sources/StickerPackScreen.swift",
    "submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift",
    "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift",
    "submodules/TelegramUI/Sources/HorizontalListContextResultsChatInputContextPanelNode.swift",
    "submodules/TelegramUI/Sources/HorizontalStickersChatContextPanelNode.swift",
    "submodules/TelegramUI/Sources/InlineReactionSearchPanel.swift",
    "submodules/TelegramUI/Sources/Chat/ChatControllerOpenPollOptionMedia.swift",
    "submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift",
    "submodules/FeaturedStickersScreen/Sources/FeaturedStickersScreen.swift",
    "submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift",
]

RETIRED = [
    "Chat/Input/Text/AccessoryIconStickers",
    "Chat/Attach Menu/Sticker",
    "Chat/Context Menu/Sticker",
    "Item List/Icons/Sticker",
    "Item List/Icons/Gif",
]


def read(rel):
    return read_abs(os.path.join(ROOT, rel))


def read_abs(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def swift_sources():
    found = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "submodules")):
        dirnames[:] = [name for name in dirnames if name not in (".build", "bazel-out")]
        for name in filenames:
            if name.endswith(".swift"):
                found.append(os.path.join(dirpath, name))
    return found


def pdf_media_box(data):
    boxes = []
    for match in re.finditer(rb"stream\r?\n(.*?)\r?\nendstream", data, re.S):
        try:
            text = zlib.decompress(match.group(1))
        except zlib.error:
            continue
        boxes.extend(re.findall(rb"/MediaBox\s*\[\s*0\s+0\s+([0-9.]+)\s+([0-9.]+)\s*\]", text))
    return boxes


class SemanticIconTests(unittest.TestCase):
    def test_sticker_svg_has_a_face_inside_the_note(self):
        text = read_abs(os.path.join(SEMANTIC, "sticker.svg"))
        self.assertEqual(len(re.findall(r"<circle\b", text)), 2)
        self.assertIn('stroke-linecap="round"', text)
        blank = read("Tellomi/Icons/MingCute/svg/regular/sticker.svg")
        self.assertNotIn("<circle", blank)
        self.assertGreater(text.count("<"), blank.count("<"))

    def test_gif_svg_spells_gif_and_is_not_the_film_strip(self):
        text = read_abs(os.path.join(SEMANTIC, "gif.svg"))
        film = read("Tellomi/Icons/MingCute/svg/regular/film.svg")
        self.assertIn("<rect", text)
        # G, the I stem, and the F crossbar are three strokes.
        self.assertGreaterEqual(len(re.findall(r"<path\b", text)), 3)
        self.assertIn("M12.998 9.5V14.5", text)
        self.assertNotIn("M22 19.057", text)
        self.assertNotEqual(text, film)

    def test_imagesets_are_outside_the_generator_mapping(self):
        mapping = read("Tellomi/Icons/mapping.csv")
        self.assertNotIn("TellomiSticker", mapping)
        self.assertNotIn("TellomiGif", mapping)
        self.assertIn("Chat/Input/Text/IconVideo,video-camera,line", mapping)
        pages = {
            "Chat/Input/Text/TellomiSticker": "24",
            "Chat/Attach Menu/TellomiSticker": "30",
            "Item List/Icons/TellomiSticker": "30",
            "Item List/Icons/TellomiGif": "30",
        }
        for asset, page in pages.items():
            pdf = os.path.join(XCASSETS, asset + ".imageset", "icon.pdf")
            self.assertTrue(os.path.isfile(pdf), pdf)
            with open(pdf, "rb") as handle:
                boxes = pdf_media_box(handle.read())
            self.assertIn((page.encode(), page.encode()), boxes)

    def test_call_sites_use_the_face_and_the_gif_wordmark(self):
        joined = "\n".join(read(path) for path in STICKER_CALLS)
        self.assertIn("Chat/Input/Text/TellomiSticker", joined)
        self.assertIn("Chat/Attach Menu/TellomiSticker", joined)
        self.assertIn("Item List/Icons/TellomiSticker", joined)
        self.assertIn("Item List/Icons/TellomiGif", joined)
        for path in swift_sources():
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            for retired in RETIRED:
                self.assertNotIn(
                    f'"{retired}"',
                    text,
                    f"{os.path.relpath(path, ROOT)} still names {retired}",
                )

    def test_round_video_button_is_the_camera_not_the_play_glyph(self):
        chat = read("submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChat.swift")
        self.assertIn(
            'UIImage(bundleImageName: "Chat/Input/Text/IconVideo")',
            chat,
        )
        video_fn = chat.split("func chatInputPanelVideoButtonImage", 1)[1].split("public static func", 1)[0]
        self.assertIn("IconVideo", video_fn)
        self.assertNotIn("Attach Menu/Video", video_fn)
        mapping = read("Tellomi/Icons/mapping.csv")
        for line in mapping.splitlines():
            if line.startswith("Chat/Input/Text/IconVideo,"):
                self.assertEqual(line.split(",")[1], "video-camera")

    def test_chat_list_checks_are_drawn_not_a_double_glyph_for_sent(self):
        source = read("submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift")
        fn = source.split("func generateStatusCheckImage", 1)[1].split("private func generateBadgeBackgroundImage", 1)[0]
        self.assertIn("if !single", fn)
        second = fn.split("if !single", 1)[1]
        self.assertIn("M7.33333333,8 L14.8333333,0", second)
        before = fn.split("if !single", 1)[0]
        self.assertNotIn("M7.33333333,8 L14.8333333,0", before)

    def test_send_arrow_is_not_the_same_color_as_its_disc(self):
        day = read("submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift")
        panel = day.split("let inputPanel = PresentationThemeChatInputPanel(", 1)[1].split("let inputMediaPanel", 1)[0]
        self.assertIn("actionControlFillColor: defaultDayAccentColor", panel)
        self.assertIn("actionControlForegroundColor: UIColor(rgb: 0xffffff)", panel)
        accents = read("submodules/TellomiWallpapers/Sources/TellomiWallpapers.swift")
        self.assertIn("public static var defaultColor: UInt32", accents)
        self.assertNotIn("0x111111", accents)
        picker = read("submodules/MediaPickerUI/Sources/MediaPickerPhotoToolbarView.swift")
        send = picker.split("case TGPhotoEditorDoneButtonSend:", 1)[1].split("self?.donePressed", 1)[0]
        self.assertIn("UIColor(rgb: 0x111111)", send)
        self.assertIn("name: doneIconName", send)
        self.assertIn("tintColor: .white", send)


if __name__ == "__main__":
    unittest.main()
