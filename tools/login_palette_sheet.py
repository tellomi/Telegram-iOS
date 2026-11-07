#!/usr/bin/env python3
"""Draw before/after login chrome swatches. Geometry is the authorization metrics."""

import os
import struct
import sys
import zlib


def lin(channel):
    c = channel / 255.0
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    hi, lo = max(lum(a), lum(b)), min(lum(a), lum(b))
    return (hi + 0.05) / (lo + 0.05)


def mix(a, b, t):
    t = min(1.0, max(0.0, t))

    def channel(shift):
        start = (a >> shift) & 255
        end = (b >> shift) & 255
        return int(min(255, max(0, round(start * (1.0 - t) + end * t))))

    return (channel(16) << 16) | (channel(8) << 8) | channel(0)


def ink(color, background, minimum):
    if contrast(color, background) >= minimum:
        return color
    toward = 0x000000 if lum(background) > 0.4 else 0xFFFFFF
    best = toward
    low, high = 1, 100
    while low <= high:
        mid = (low + high) // 2
        mixed = mix(color, toward, mid / 100.0)
        if contrast(mixed, background) >= minimum:
            best = mixed
            high = mid - 1
        else:
            low = mid + 1
    return best


def button_pair(background, foreground):
    if contrast(foreground, background) >= 4.5:
        return background, foreground
    opposite = 0x000000 if lum(background) > 0.4 else 0xFFFFFF
    if opposite != foreground and contrast(opposite, background) >= 4.5:
        return background, opposite
    toward = 0x000000 if lum(foreground) > 0.5 else 0xFFFFFF
    best = toward
    low, high = 1, 100
    while low <= high:
        mid = (low + high) // 2
        mixed = mix(background, toward, mid / 100.0)
        if contrast(foreground, mixed) >= 4.5:
            best = mixed
            high = mid - 1
        else:
            low = mid + 1
    return best, foreground


def png(width, height, rgb):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rgb[y * width * 3:(y + 1) * width * 3])
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def fill(buf, w, x, y, bw, bh, color):
    r, g, b = (color >> 16) & 255, (color >> 8) & 255, color & 255
    height = len(buf) // (w * 3)
    for yy in range(max(0, y), min(height, y + bh)):
        row = yy * w * 3
        for xx in range(max(0, x), min(w, x + bw)):
            i = row + xx * 3
            buf[i] = r
            buf[i + 1] = g
            buf[i + 2] = b


def stroke_rect(buf, w, x, y, bw, bh, color, t=2):
    fill(buf, w, x, y, bw, t, color)
    fill(buf, w, x, y + bh - t, bw, t, color)
    fill(buf, w, x, y, t, bh, color)
    fill(buf, w, x + bw - t, y, t, bh, color)


def circle(buf, w, cx, cy, radius, fill_color, stroke_color=None, stroke=2):
    height = len(buf) // (w * 3)
    r2 = radius * radius
    inner = max(0, radius - stroke)
    i2 = inner * inner
    for yy in range(max(0, cy - radius), min(height, cy + radius + 1)):
        for xx in range(max(0, cx - radius), min(w, cx + radius + 1)):
            d = (xx - cx) ** 2 + (yy - cy) ** 2
            color = None
            if stroke_color is not None and i2 <= d <= r2:
                color = stroke_color
            elif fill_color is not None and d <= (i2 if stroke_color is not None else r2):
                color = fill_color
            if color is None:
                continue
            i = (yy * w + xx) * 3
            buf[i] = (color >> 16) & 255
            buf[i + 1] = (color >> 8) & 255
            buf[i + 2] = color & 255


def sheet(path, title, page, samples):
    w, h = 880, 64 + len(samples) * 72
    buf = bytearray([255, 255, 255] * (w * h))
    fill(buf, w, 0, 0, w, h, 0xF4F4F6)
    fill(buf, w, 16, 16, w - 32, h - 32, page)
    y = 36
    for name, fg, bg, kind in samples:
        fill(buf, w, 36, y, 280, 52, bg)
        if kind == "box":
            stroke_rect(buf, w, 36, y, 280, 52, fg, 2)
        elif kind == "check":
            circle(buf, w, 62, y + 26, 16, None, fg, 3)
        elif kind == "checked":
            circle(buf, w, 62, y + 26, 16, bg, None, 0)
            circle(buf, w, 62, y + 26, 16, fg, None, 0)
        else:
            fill(buf, w, 48, y + 14, 200, 24, fg)
        y += 72
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png(w, h, buf))
    print(title, path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "login-palette"
    os.makedirs(out, exist_ok=True)
    # Before: the hardcoded chrome.
    before_light = [
        ("field", 0x111111, 0xF2F3F5, "fill"),
        ("placeholder", 0xB0B0B6, 0xF2F3F5, "text"),
        ("button", 0xFFFFFF, 0x111111, "text"),
        ("disabled", 0x8E8E93, 0xE5E5E5, "text"),
        ("code border", 0xE5E5E5, 0xF2F3F5, "box"),
        ("checkbox", 0xC7C7CC, 0xFFFFFF, "check"),
    ]
    before_dark = [
        ("field", 0xFFFFFF, 0x2C2C2E, "text"),
        ("placeholder theme", 0x4D4D4D, 0x2C2C2E, "text"),
        ("button", 0x111111, 0xFFFFFF, "text"),
        ("disabled", 0x8E8E93, 0x3A3A3C, "text"),
        ("code border", 0xE5E5E5, 0x2C2C2E, "box"),
        ("checkbox", 0xC7C7CC, 0x000000, "check"),
    ]
    light_page = 0xFFFFFF
    light_fill = 0xF2F2F7
    light_ph = ink(0xB6B6BB, light_fill, 4.5)
    light_link = ink(0x3390EC, light_page, 4.5)
    light_border = ink(0xC8C7CC, light_page, 3.0)
    light_code = ink(0xC8C7CC, light_fill, 3.0)
    light_stroke = ink(0xC7C7CC, light_page, 3.0)
    light_secondary = ink(0x8E8E93, light_page, 4.5)
    light_error = ink(0xFF3B30, light_page, 4.5)
    check_bg, check_fg = button_pair(0x3390EC, 0xFFFFFF)
    dis_bg = mix(0xFFFFFF, 0x8E8E93, 0.38)
    dis_fg = ink(0x8E8E93, dis_bg, 4.5)
    after_light = [
        ("field text", 0x000000, light_fill, "text"),
        ("placeholder", light_ph, light_fill, "text"),
        ("button", 0xFFFFFF, 0x000000, "text"),
        ("disabled", dis_fg, dis_bg, "text"),
        ("field border", light_border, light_page, "box"),
        ("code border", light_code, light_fill, "box"),
        ("focus", light_link, light_fill, "box"),
        ("checkbox", light_stroke, light_page, "check"),
        ("checked", check_fg, check_bg, "checked"),
        ("secondary", light_secondary, light_page, "text"),
        ("error", light_error, light_page, "text"),
    ]
    night_fill = 0x2C2C2E
    night_ph = ink(0x8F8F8F, night_fill, 4.5)
    night_border = ink(0x545458, 0x000000, 3.0)
    night_code = ink(0x545458, night_fill, 3.0)
    night_stroke = ink(0x8E8E93, 0x000000, 3.0)
    night_dis_bg = mix(0x000000, 0x8F8F8F, 0.38)
    night_dis_fg = ink(0x8F8F8F, night_dis_bg, 4.5)
    night_error = ink(0xEB5545, 0x000000, 4.5)
    after_dark = [
        ("field text", 0xFFFFFF, night_fill, "text"),
        ("placeholder", night_ph, night_fill, "text"),
        ("button", 0x111111, 0xFFFFFF, "text"),
        ("disabled", night_dis_fg, night_dis_bg, "text"),
        ("field border", night_border, 0x000000, "box"),
        ("code border", night_code, night_fill, "box"),
        ("focus", 0xFFFFFF, night_fill, "box"),
        ("checkbox", night_stroke, 0x000000, "check"),
        ("checked", 0x000000, 0xFFFFFF, "checked"),
        ("secondary", 0x98989E, 0x000000, "text"),
        ("error", night_error, 0x000000, "text"),
    ]
    sheet(os.path.join(out, "before-light.png"), "before light", 0xFFFFFF, before_light)
    sheet(os.path.join(out, "before-dark.png"), "before dark", 0x000000, before_dark)
    sheet(os.path.join(out, "after-light.png"), "after light", 0xFFFFFF, after_light)
    sheet(os.path.join(out, "after-dark.png"), "after dark", 0x000000, after_dark)
    print("light placeholder", hex(light_ph), f"{contrast(light_ph, light_fill):.2f}")
    print("light link", hex(light_link), f"{contrast(light_link, light_page):.2f}")
    print("light disabled", hex(dis_fg), hex(dis_bg), f"{contrast(dis_fg, dis_bg):.2f}")
    print("light stroke", hex(light_stroke), f"{contrast(light_stroke, light_page):.2f}")
    print("night placeholder", hex(night_ph), f"{contrast(night_ph, night_fill):.2f}")


if __name__ == "__main__":
    main()
