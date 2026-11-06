#!/usr/bin/env python3
"""Chat-list swipe icons must resolve to the upstream circle, not the iconless pill.

Telegram draws a chat-list swipe action as a 50×50 circle when the row is tall
enough and the action has an icon. The same reveal node draws a 60×32 capsule
when the action has no icon. Tellomi's MingCute swipe images live under
`Chat List/Swipe`. That folder is looked up as `Chat List/Swipe/<Name>`. An
asset folder contributes its name only when Contents.json sets
provides-namespace. The swipe folder was the only imageset folder in the
catalog without that flag, so every lookup was nil, swipeIcon returned .none,
and every action took the capsule.

This does not launch the app. It checks the catalog naming actool uses, the
action icons ChatListItem asks for, and the reveal geometry and gesture
thresholds that are copied from TelegramMessenger/Telegram-iOS 279f89e4.
"""

import json
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
XCASSETS = os.path.join(ROOT, "submodules", "TelegramUI", "Images.xcassets")
CHAT_LIST_ITEM = os.path.join(
    ROOT, "submodules", "ChatListUI", "Sources", "Node", "ChatListItem.swift"
)
REVEAL_NODE = os.path.join(
    ROOT, "submodules", "ItemListUI", "Sources", "ItemListRevealOptionsNode.swift"
)
REVEAL_MOTION = os.path.join(
    ROOT, "submodules", "ItemListUI", "Sources", "ItemListRevealMotion.swift"
)
REVEAL_ITEM = os.path.join(
    ROOT, "submodules", "ItemListUI", "Sources", "Items", "ItemListEditableItem.swift"
)

# ItemListRevealOptionLayoutMetrics.metrics, upstream 279f89e4.
REGULAR_SHAPE = (50.0, 50.0)
COMPACT_SHAPE = (60.0, 32.0)
REGULAR_RADIUS = 25.0
COMPACT_RADIUS = 16.0
TITLE_SPACING = 4.0
# Font.regular(11) ceil(lineHeight). The test does not measure UIFont.
TITLE_LINE_HEIGHT = 14.0

# Actions the chat list must still offer. Icons stay the MingCute images.
ACTION_ICONS = {
    "pin": "Chat List/Swipe/Pin",
    "unpin": "Chat List/Swipe/Unpin",
    "mute": "Chat List/Swipe/Mute",
    "unmute": "Chat List/Swipe/Unmute",
    "delete": "Chat List/Swipe/Delete",
    "archive": "Chat List/Swipe/Archive",
    "unarchive": "Chat List/Swipe/Unarchive",
    "read": "Chat List/Swipe/Read",
    "unread": "Chat List/Swipe/Unread",
    "hide": "Chat List/Swipe/Hide",
    "unhide": "Chat List/Swipe/Unhide",
    "group": "Chat List/Swipe/Group",
    "ungroup": "Chat List/Swipe/Ungroup",
    "start": "Chat List/Swipe/Play",
    "close": "Chat List/Swipe/Pause",
}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def provides_namespace(folder):
    contents = os.path.join(folder, "Contents.json")
    if not os.path.isfile(contents):
        return False
    with open(contents, encoding="utf-8") as handle:
        data = json.load(handle)
    return bool(data.get("properties", {}).get("provides-namespace"))


def compiled_asset_name(imageset_dir):
    """Name actool publishes. Only folders with provides-namespace are prefixes."""
    parts = []
    folder = os.path.dirname(imageset_dir)
    while os.path.abspath(folder) != os.path.abspath(XCASSETS):
        if provides_namespace(folder):
            parts.append(os.path.basename(folder))
        parent = os.path.dirname(folder)
        if parent == folder:
            break
        folder = parent
    parts.reverse()
    name = os.path.basename(imageset_dir)
    if name.endswith(".imageset"):
        name = name[: -len(".imageset")]
    parts.append(name)
    return "/".join(parts)


def reveal_metrics(height, has_visual_icons, title_line_height=TITLE_LINE_HEIGHT):
    """Same branch as ItemListRevealOptionLayoutMetrics.metrics."""
    regular_content_height = REGULAR_SHAPE[1] + TITLE_SPACING + title_line_height
    if height < regular_content_height or not has_visual_icons:
        return COMPACT_SHAPE, COMPACT_RADIUS
    return REGULAR_SHAPE, REGULAR_RADIUS


class ChatListSwipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.item = read(CHAT_LIST_ITEM)
        cls.reveal = read(REVEAL_NODE)
        cls.motion = read(REVEAL_MOTION)
        cls.editable = read(REVEAL_ITEM)

    def test_swipe_folder_is_a_namespace(self):
        folder = os.path.join(XCASSETS, "Chat List", "Swipe")
        self.assertTrue(provides_namespace(folder), folder)
        bare = []
        for dirpath, dirnames, _filenames in os.walk(XCASSETS):
            dirnames[:] = [name for name in dirnames if not name.endswith(".imageset")]
            if any(name.endswith(".imageset") for name in os.listdir(dirpath)):
                if os.path.abspath(dirpath) != os.path.abspath(XCASSETS) and not provides_namespace(dirpath):
                    bare.append(os.path.relpath(dirpath, XCASSETS))
        self.assertEqual(bare, [])

    def test_swipe_lookups_compile_to_the_names_chat_list_uses(self):
        asked = re.findall(r'swipeIcon\("([^"]+)"\)', self.item)
        self.assertCountEqual(asked, list(ACTION_ICONS.values()))
        for asset in asked:
            imageset = os.path.join(XCASSETS, asset + ".imageset")
            self.assertTrue(os.path.isdir(imageset), imageset)
            pdfs = [name for name in os.listdir(imageset) if name.endswith(".pdf")]
            self.assertTrue(pdfs, imageset)
            self.assertEqual(compiled_asset_name(imageset), asset, asset)

    def test_missing_namespace_is_the_pill_and_a_resolved_icon_is_the_circle(self):
        self.assertIn("height < regularContentHeight || !hasVisualIcons", self.reveal)
        self.assertIn("CGSize(width: 50.0, height: 50.0)", self.reveal)
        self.assertIn("CGSize(width: 60.0, height: 32.0)", self.reveal)
        self.assertIn("cornerRadius: 25.0", self.reveal)
        self.assertIn("cornerRadius: 16.0", self.reveal)
        self.assertIn("case .none:", self.reveal)
        self.assertIn("displaysTitleInsidePill = true", self.reveal)

        # A normal chat row is taller than the circle plus its 11pt label.
        self.assertEqual(reveal_metrics(72.0, True), (REGULAR_SHAPE, REGULAR_RADIUS))
        # The bug: imageNamed failed, so hasVisualIcons was false at any height.
        self.assertEqual(reveal_metrics(72.0, False), (COMPACT_SHAPE, COMPACT_RADIUS))
        self.assertEqual(reveal_metrics(80.0, False), (COMPACT_SHAPE, COMPACT_RADIUS))
        # Upstream also uses the capsule when the row itself is shorter than the circle stack.
        regular_content = REGULAR_SHAPE[1] + TITLE_SPACING + TITLE_LINE_HEIGHT
        self.assertEqual(reveal_metrics(regular_content - 0.5, True), (COMPACT_SHAPE, COMPACT_RADIUS))
        self.assertEqual(reveal_metrics(regular_content, True), (REGULAR_SHAPE, REGULAR_RADIUS))

    def test_actions_still_use_those_icons(self):
        for key, asset in (
            ("mute", "muteIcon"),
            ("unmute", "unmuteIcon"),
            ("delete", "deleteIcon"),
            ("archive", "archiveIcon"),
            ("unarchive", "unarchiveIcon"),
            ("pin", "pinIcon"),
            ("unpin", "unpinIcon"),
            ("toggleMarkedUnread", "unreadIcon"),
            ("toggleMarkedUnread", "readIcon"),
        ):
            self.assertIn("RevealOptionKey.{0}".format(key), self.item)
            self.assertRegex(
                self.item,
                r"RevealOptionKey\.{0}\.rawValue, title: [^,\n]+, icon: {1}\b".format(key, asset),
            )

    def test_gesture_thresholds_stay_the_upstream_ones(self):
        for literal in (
            "var buttonWidth: Double = 50",
            "var spacing: Double = 10",
            "var edgeInset: Double = 10",
            "self.width - 29",
            "self.width * 0.525",
            "self.width * 0.75",
            "self.width >= 414 ? 90 : (self.width == 375 ? 75 : 50)",
            "abs(velocity) / 2500",
        ):
            self.assertIn(literal, self.motion)
        self.assertIn(
            "let sideInset = self.revealDirection > 0 ? leftInset : rightInset",
            self.editable,
        )

    def test_open_width_uses_the_circle_when_the_icon_resolves(self):
        shape, _radius = reveal_metrics(72.0, True)
        spacing = 10.0
        edge = 10.0
        # Three trailing actions (mute, delete, archive), no safe-area inset.
        width = edge * 2.0 + shape[0] * 3.0 + spacing * 2.0
        self.assertEqual(width, 190.0)
        missing, _radius = reveal_metrics(72.0, False)
        missing_width = edge * 2.0 + missing[0] * 3.0 + spacing * 2.0
        self.assertEqual(missing_width, 220.0)
        self.assertGreater(missing_width, width)


if __name__ == "__main__":
    unittest.main()
