# Tellomi 品牌资产与图标流水线

一张矢量母图 + 一条命令生成三端全部尺寸。**换 logo 只换母图再跑一次**，不要手工改任何一张产物。

## 母图

| 文件 | 是什么 |
| --- | --- |
| `logo-source-light.png` / `logo-source-dark.png` | owner 给的**原图**（浅底深字 / 深底白字），入库存档 |
| `logo.svg` | **标的母图**：由浅底那张用 `scripts/brand/trace-logo.py` **描摹**出来的 fill 路径，颜色是 `currentColor` |
| `wordmark-source-{light,dark}.png` | owner 给的**字标原图**（`Tell@mi`） |
| `wordmark.svg` | **字标母图（第二版，owner 2026-09-27）**：`scripts/brand/wordmark.py` 生成，`currentColor`；设计见下面「英文字标」 |
| `wordmark-v1-traced.svg` | 第一版字标（`wordmark-source-*.png` 描摹出来的 Tell@mi），**已停用**，只留档 |

```bash
brew install potrace
~/.nexi/brand-venv/bin/python3 scripts/brand/trace-logo.py docs/brand/logo-source-light.png
~/.nexi/brand-venv/bin/python3 scripts/brand/trace-logo.py docs/brand/wordmark-source-light.png --out wordmark.svg --keep-aspect
```

**不要手画这个 SVG。** 2026-09-21 我按看到的样子手画过一版，比例跑偏（@ 偏小、线重和气泡不一致、偏左），
owner 一眼看出来不是同一个标。描摹出来的才是原图本身。

亮 / 暗两版**不是两个文件**，是同一个 `logo.svg` 换颜色：
浅色界面用墨色 `#111113`，深色界面用白色 `#FFFFFF`，App 图标底色 `#17171A`。
产物里的 `mark-on-light` / `mark-on-dark` 按**用在哪种界面**命名，不是按图自身颜色。
Desktop 里两处给标上色的 CSS（启动 / 锁屏 `.module-splash-screen__logo`、配对页 `InstallScreenSignalLogo`）用 `$color-tellomi-ink` = `#111113`（亮）/ `#ffffff`（暗），不再是上游 `$color-ultramarine-logo`（#884，fork `c36eae9`）。

品牌名、域名、Bundle ID 等其它品牌事实在 `docs/product/BRAND.md`，本文件只管视觉资产。

## 生成

```bash
brew install librsvg                                   # rsvg-convert，一次性
python3 -m venv ~/.nexi/brand-venv && ~/.nexi/brand-venv/bin/pip install -q pillow numpy
~/.nexi/brand-venv/bin/python3 scripts/brand/make-icons.py             # → build/brand-icons/
~/.nexi/brand-venv/bin/python3 scripts/brand/make-icons.py --install android
python3 scripts/brand/android_splash.py                # 只要安卓开屏图：纯 Python，不要 rsvg / Pillow
```

产物（2026-09-21 本机实跑，51 个文件全部通过校验）：

| 端 | 产物 | 装到哪（**只有该 fork 的主人提交**） |
| --- | --- | --- |
| Android | `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` + `ic_launcher_round.png`；`drawable-*dpi/ic_launcher_{background,foreground,monochrome}.png` | `clients/android/app/src/main/res/`（Pro） |
| Android 开屏（12+） | `android-brand/drawable/ic_splash{,_light,_dark}.xml`、`android-brand/drawable-night/ic_splash.xml`（2026-10-13 起，`android_splash.py`） | `clients/android/app/src/main/res/` |
| iOS | `ios/AppIcon.icon/`（Icon Composer 包：`icon.json` + `Assets/logo.svg` + `preview-1024.png`） | `clients/ios/Signal/AppIcons/`（Pro） |
| Desktop | `desktop/png/{16…1024}.png`、`desktop/win/icon.ico`、`desktop/mac/AppIcon.icon`、`desktop/mac/icon.icns` | `clients/desktop/build/icons/`（taishi） |
| 官网 | `website/{favicon,apple-touch-icon,icon-192,icon-512,og}.png` | `website/public/`（Pro） |
| App 内 / 官网 | `marks/mark-on-{light,dark}.{png,svg}` | 各端按需 |
| 字标 / 组合 | `wordmark/wordmark-on-{light,dark}.svg`、`wordmark/lockup-on-{light,dark}.svg`（标 + 字标横向组合） | 官网页眉、收据、商店素材 |

`build/` 是产物目录，不入库——母图与脚本入库就够了。

## 必须知道的实现细节

1. **母图的画面不居中于 viewBox**（气泡偏右上、尾巴伸向左下）。按 viewBox 居中会让图标看着偏上，
   所以脚本先渲染、裁掉透明边、再按裁剪后的外接框居中。
2. **Android 自适应图标的前景层会被系统再套 16% inset**：脚本给前景 / 单色层的可见区是 108dp 里的中间 72dp，
   背景层才是满幅 108dp（纯色 `#17171A`）。直接把满幅图当前景会被裁掉一圈。
3. **iOS 26 / macOS 的 `.icon` 是 Icon Composer 包，不是 `.appiconset`**。上游 Signal 就是「一张 SVG 图层 + `icon.json`」，
   我们照同一形状写——母图本来就是矢量，这一端是**无损**的。
4. **描摹前不要放大位图**：先放大再 potrace，会把抗锯齿的锯齿一并描出来——同一张图路径数据从 1.8 KB 涨到 68 KB。
   正确做法是原生分辨率 + 轻度高斯模糊后再二值化。
5. **iOS 改完资源要删掉编译产物再构建**：Xcode 的增量构建会跳过资源目录，出现「构建成功但图没换」。
   判据是 `xcrun --sdk iphonesimulator assetutil --info <Assets.car>` 里那张图的 `SizeOnDisk` 变了；
   保险做法是先删掉 DerivedData 里所有 `Assets.car` 再构建。
6. **模拟器会缓存开屏快照，`simctl uninstall` 清不掉**：换了开屏图以后在旧模拟器上看还是旧的。
   要验开屏，`simctl create` 一台全新的装上去看——这一条我用红色、绿色两次对照实验才确认（2026-09-21）。
7. **校验不能只看尺寸**：rsvg 渲染失败时会给一张纯底色图，尺寸照样是对的。
   所以校验还要求位图里至少有三种像素值（自适应图标的背景层除外，它本来就是纯色）。
8. **字形大小要和主屏上的邻居一样大**（owner 2026-09-27）：`GLYPH_SCALE` 原来是 0.66，真机主屏上 Tellomi 明显小一圈。
   同一张 iOS 26 主屏截图量「图形最长边 / 图标边长」：WhatsApp 0.71 · Signal 0.745 · Messenger 0.775 · Tellomi 0.657（iOS 26 的实际渲染 = 脚本里的比例）。
   现在 iOS / macOS / Desktop / 官网 **0.76**（单线描边比实心气泡轻，取偏上）；安卓自适应图标单独 `ANDROID_GLYPH_SCALE = 0.70`——
   尾巴离中心最远（外接框最长边的 0.661 倍），0.70 时正好在 66dp 安全区边上，再大圆形遮罩就会裁到尾巴（owner 2026-09-25 要四周留边）。
   以后换母图先量这个比例；iOS 26 以前的系统用 actool 另渲染的位图，不能拿它量。
9. **安卓 12+ 的冷启动开屏图是另一套文件**（`ic_splash*`，`values-v31` / `values-night-v31` 的 `windowSplashScreenAnimatedIcon`），
   换 launcher 图标时不会跟着换——上游 Signal 的蓝色虚线气泡在这里留到了 2026-10-13 才发现。
   系统把它画进 288dp 的方块、只保证中间直径 192dp 的圆不被裁；`android_splash.py` 让外接框最长边占画面 0.46
   （上游 Signal 那张是 0.43），最远的墨点（尾巴尖）离中心 0.304 < 0.333，超了脚本直接报错。
   浅色主题墨色 `#111113`，深色（`drawable-night/`、手动深色主题的 `ic_splash_dark`）白色；背景沿用上游主题。
   要验：安卓 12+ 模拟器 `adb shell am force-stop` 后冷启动，浅 / 深各看一次（`adb shell cmd uimode night no|yes`）。
   2026-10-13 的样子：`preview/android-splash-{light,dark}.png`（模拟器 Android 16，1080×2400 缩到一半）。

## 英文字标（owner 2026-09-27 重新设计）

**为什么重做**：第一版 Tell@mi（owner 给的原图描摹）字体粗而圆、@ 又大又往下坠，放在开屏插画下面很突兀（owner 原话「有点突兀」）。

**定稿（owner 选 W1）**：`Tell@mi`，纯黑白（浅色界面墨 `#111113`、深色界面白），不用青色。

- **字母**：Inter（SIL OFL 1.1，允许做标志；字形已转成轮廓，产物不依赖字体），字重 540（@ 缩到 o 的大小后笔画变细，字母跟着减细才匀称；600 偏重），字距 −0.02 em，走 HarfBuzz 排版（带字偶距）。
- **@**：**直接用 App 图标 `logo.svg` 里那个 @**（第二条 path），不另画。字标和图标因此是同一个 @。
  **和原来的 o 一样大**（owner：「@ 应该保持和 o 一样的大小」）：高度 = o 的包围盒高度（含上下过冲），顶端对齐 o；左右留 o 的字边距。
- 选型时看过、没选的：i 点 / o 用青色（owner：logo 是黑白的，字标也要黑白）；o 做成带尾巴的气泡（owner：用 @ 更生动，和 logo 一致）；全小写 tell@mi（owner 选了首字母大写）；@ 放大到 1.3 个 x 高度（owner：明显偏大）。

**重新生成**（改字重、字距、@ 大小都在这里改，**不要手改 SVG**）：

```bash
~/.nexi/brand-venv/bin/python3 scripts/brand/wordmark.py --text Tellomi --weight 540 --tracking -0.02 --at \
  --font clients/ios/SignalUI/Fonts/Inter-Variable.ttf --out docs/brand/wordmark/tellomi-wordmark
sed 's/#111113/currentColor/g' docs/brand/wordmark/tellomi-wordmark-light.svg > docs/brand/wordmark.svg
```

依赖装在 `~/.nexi/brand-venv`：`fonttools`、`uharfbuzz`。产物：`wordmark/tellomi-wordmark-{light,dark}.svg`（两端直接用）、`wordmark.svg`（`currentColor` 母图，`make-icons.py` 读它）、`wordmark/preview/`。

**在哪用**：iOS / 安卓开屏（插画下面只放字标，BRAND.md「开屏」）。Desktop 的配对页、独立注册页和官网用的还是第一版，下次跑 `make-icons.py` 重生成时跟着换。

## 插画（owner 2026-09-27：Open Doodles / Open Peeps，纯黑白）

**来源只用两套，同一位作者（Pablo Stanley）、同一种手绘风格，许可都是 CC0（公有领域）**：

- [Open Doodles](https://www.opendoodles.com/)：现成的生活场景（荡秋千、自拍、阅读、跳舞……），开屏轮播用它。
- [Open Peeps](https://www.openpeeps.com/)：可拼装的人物（发型、表情、姿势、服装），以后「动态」「AI」这类要专门画的场景用它拼，风格和 Open Doodles 一致。

为什么是 CC0：三端客户端仓库是公开的 AGPL 仓库，原图文件就放在里面。unDraw、DrawKit 的许可都禁止把图单独再分发，放进公开仓库有风险；CC0 没有这个问题，也不用署名。
（2026-09-27 当天先定过 unDraw 的「Casual Chat」，owner 看过觉得不合适，同日改成本节；unDraw 的文件已从仓库删掉。）

**颜色：纯黑白**（owner 2026-09-27，和黑白的图标、字标一致）。由 `scripts/brand/doodle.py` 生成，**不要手改颜色**：

- 原图的彩色（Open Doodles 默认粉）→ 透明，白的地方就是背景色；
- 黑线 → 浅色版墨 `#111113`，深色版浅灰 `#F4F4F5`（深色界面上反成浅线条）。

**流程**：

1. 在 opendoodles.com / openpeeps.com 挑图，给 owner 看候选。
2. 下载 SVG，原样放 `docs/brand/illustrations/opendoodles-original/<名字>.svg`（Open Peeps 放 `openpeeps-original/`）。
3. `python3 scripts/brand/doodle.py docs/brand/illustrations/opendoodles-original/<名字>.svg --preview`
   → `docs/brand/illustrations/<名字>-{light,dark}.svg` + `preview/`。
4. 看预览，登记到下表，再按平台转格式：iOS 放 asset catalog（SVG，Preserve Vector Data，浅 / 深两个外观）；Android 转 VectorDrawable（`drawable/` + `drawable-night/`）；Desktop 直接用 SVG。
5. 客户端里放插画的地方带一份 `ILLUSTRATIONS-LICENSE.md`：写明来自 Open Doodles / Open Peeps、CC0。

**不要**：混用别的图库或风格；给插画上色（除非 owner 另定）；在插画上加品牌标。

| 名字 | 原图 | 下载日期 | 用在哪 |
| --- | --- | --- | --- |
| `swinging` | Open Doodles「A person on a giant swing」 | 2026-09-27 | 开屏轮播第 1 张 |
| `selfie` | Open Doodles「A person taking a selfie」 | 2026-09-27 | 开屏轮播第 2 张 |
| `loving` | Open Doodles「A person holding a heart」 | 2026-09-27 | 开屏轮播第 3 张 |
| `float` | Open Doodles「A person floating in mid air」 | 2026-09-27 | 开屏轮播第 4 张 |

### 开屏轮播（owner 2026-09-27）

- 上面四张按顺序轮播：荡秋千 → 自拍 → 捧心 → 悬浮（生活、分享、连接、想象——对应聊天、以后的动态和 AI，不画 App 内部界面）。
- **每张停 3 秒**自动切到下一张（owner 提 1 秒或由我定；1 秒看不清一张图，3 秒是常见节奏），循环；支持左右滑，手指按住时暂停，松手 3 秒后继续。
- 插画下面一排小圆点指示第几张；再下面是字标 Tell@mi（「英文字标」一节），不放句子。
- 系统开了「减弱动态效果」时不自动播，只能手动滑。
- 插画是装饰，读屏跳过；轮播整体读作「Tellomi」。

## 许可证

母图与全部产物是 **Tellomi 自有资产**，与 Signal / Telegram 无关。
反过来同样是红线：Signal 的名称、Signal 蓝、Signal 的图标资产**不得**留在 Tellomi 的产物里；
品牌替换批次要把三端里残留的 `AppIcon-*.icon` / `ic_launcher_alt_signal_*` 这类上游品牌资产一并清掉（ADR-0061「法律影响」）。
