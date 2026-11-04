# Wallpaper pattern licenses

The chat wallpaper tiles are bundled in the app. They are not WhatsApp or Telegram artwork.

- **Tabler Icons** — MIT License. Copyright (c) 2020-2026 Paweł Kuna. https://github.com/tabler/tabler-icons
- **Lucide** — ISC License. Copyright (c) Lucide Contributors. Portions of the icons come from Feather (MIT). https://github.com/lucide-icons/lucide
- **Hero Patterns** — CC BY 4.0. Copyright Steve Schoger. https://heropatterns.com
  - `waves` (`tm_waves`) is Hero Patterns "Topography", repeated.
  - `dots` (`tm_dots`) is Hero Patterns "Polka Dots", repeated.

`Tellomi/Wallpapers/generate_patterns.py` downloads those sources and writes `doodle.svg`, `dots.svg`, `waves.svg`, and the gzipped `.tgv` files under `submodules/TelegramUI/Resources/`. Settings shows the same notice.
