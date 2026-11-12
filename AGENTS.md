## 必读（按顺序）

1. 本文件「永久开发规范」（Telegram Native-First）—— **仓库内权威版本**；改规范开 PR
2. `docs/TELLOMI_RULES.md` —— 铁律（四仓同文，改规则开 PR；已同步收录本规范摘要）
3. 模块边界：https://github.com/tellomi/tellomi/blob/main/docs/MODULE_BOUNDARIES.md
4. 本仓：`CLAUDE.md`（构建、模拟器、子系统不变量）；改动记入 `Tellomi/UPSTREAM_PATCHES.md`

## 永久开发规范（Telegram Native-First）

本规范对所有为 Tellomi 写代码的人与 AI **永久生效**。仓库内的权威版本是**本仓根目录 `AGENTS.md` 的「永久开发规范」章节**。`docs/TELLOMI_RULES.md`（如有）同步收录原则与检查清单。改本规范必须开 PR，不要只改聊天记忆。

Telegram 客户端已经发展十多年，交互、缓存、媒体和体积控制都经过长期打磨。Tellomi 是在这套代码上做品牌与功能扩展，不是另写一套 App。增加功能或修复问题，必须先服从下面的顺序。

## 原则

### 1. 先读原版，再动手

增加任何功能之前，必须先查看、阅读并理解 Telegram 原有代码的标准、结构和设计规范。相关平台要对照着看（移动端至少看 iOS 和 Android，不能只看一端）。没有完成阅读，不得开始写新代码。

### 2. 原版已有的能力，必须优先复用

先确认原代码有没有同一类功能。有，就先使用原有功能代码，不要再实现一套平行逻辑。

典型例子：我们在「动态」（Moments）里查看图片。Telegram 已经有完整的图片/视频查看器、手势、保存和共享媒体列表。必须先走原有查看器，而不是为动态新写一套看图页。

资料页标签也是同样的规则：Telegram 原生是「有数据才出现对应标签」。动态、快拍等扩展必须先读这段原生实现，再按同样规则接入，不要自创「标签永远显示」，也不要把快拍与动态合并。资料页最多同时出现一个「快拍」和一个「动态」；中文里 Stories 必须叫「快拍」。

### 3. 只有原版不够用时才扩展，扩展仍须遵循原版规范

只有在确认原实现覆盖不了产品需求时，才允许新增扩展代码。扩展必须遵循 Telegram 的代码结构、命名、线程模型、导航和生命周期习惯，并尽量从原有类型上长出来，而不是另起一套架构。

### 4. 瘦安装、肥运行；接入原有缓存与下发机制

Telegram 的设计是：安装包保持精简，贴纸、主题、文案、配置和媒体等大多由服务端下发，本地文件和缓存会自动清理。新功能必须沿用这一理念：

- 不要把大资源（视频、大量图片、字体、主题包、未使用的原生库或二进制）打进安装包。
- 配置、文案、资源能走服务端下发或原有 langpack / 远程配置的，不要写死在客户端包里。
- 必须接入 Telegram 原有的缓存与存储管理体系，让新文件同样被统计、过期和清理。禁止自建不受该体系管理的本地目录或「影子缓存」。

### 5. 能不修改 Telegram 原有源码，就不修改

大多数线上问题应先从服务端查起（协议实现、API 覆盖、数据、权限、媒体、限流）。Telegram 客户端代码已经非常成熟，不要先入为主地改客户端。

不得不改原版文件时：

- 只做最小改动（最小 diff），优先在扩展目录或既有挂钩里完成；
- 按本仓既有做法登记到对应的 `UPSTREAM_PATCHES` 文件（见下方本仓路径）；
- 在 PR 里写清改了哪些原版文件、为什么不能只改扩展或服务端。

### 6. 修复必须有真实测试；禁止桩代码和假成功响应

每个修复、每个行为变更都要有真实测试（单元测试、协议测试或可复现的集成验证）。禁止用空实现、假 200、伪造成功返回来「先过关」。测试失败时，不能靠放宽断言混过去。

## 开工前检查清单（必须书面回答，并写入 PR 描述）

在写第一行功能代码之前，以及在打开 PR 时，必须明确回答下列问题：

1. **原版有没有类似功能？** 有或没有。若有，写明模块、文件路径和准备复用的类型或函数。
2. **若有，为什么原版不够用？** 若够用，写明如何复用，以及本次是否没有新写平行实现。
3. **服务端能不能解决？** 若能，为什么还要改客户端；若不能，服务端缺的是哪一段协议或数据。
4. **本次改了哪些 Telegram 原版文件？** 列出路径。若未改原版，写「未改原版」。
5. **新文件或缓存是否接入了原有存储与自动清理？** 有没有把大资源打进安装包？
6. **测试是什么？** 指出测试文件或验证步骤。确认不是桩代码，也不是假 200。

没有这六条答案的 PR，不得进入复审，更不得合入。


## 本仓（iOS）对照入口

下列路径已在本仓树中核实，不要编造新的模块名。增加功能时从这里读起：

- 查看图片和视频：`submodules/GalleryUI`（如 `Sources/GalleryController.swift`、`Sources/Items/ChatImageGalleryItem.swift`）。动态里看图应复用这套 Gallery，而不是另写查看器。
- 资料页与媒体标签：`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift`（`peerInfoAvailableMediaPanes`），以及同目录的 `PeerInfoScreen.swift`、`Panes/`。原生规则是有数据才出现对应标签。
- 快拍入口：`.../PeerInfoScreen/Sources/PeerInfoScreenOpenStories.swift`。中文必须叫「快拍」，不要与「动态」合并。
- 媒体缓存与自动清理：`submodules/Postbox/Sources/MediaBox.swift`（及相关 `MediaBoxFile*.swift`）。新下载必须走 MediaBox，禁止自建不受管目录。
- 动态扩展代码在 `submodules/TelegramUI/Components/Moments/`。注意：这条目录在 `release/ios` 发布线上；当前 `master` 可能没有 Moments 源码，改资料页动态不要只在缺该目录的 `master` 上开工。
- 原版改动登记：`Tellomi/UPSTREAM_PATCHES.md`。
- 合入 `release/ios` 会触发 TestFlight，必须攒批、独立复审 PASS、CI 绿后再合，并立刻汇报构建号。本规范的文档 PR 只打到 `master`，不要打到 `release/ios`。


# AGENTS.md

Guidance for coding agents working in this repository. The project guide is [`CLAUDE.md`](CLAUDE.md): how to build,
which simulators to use, how to drive them (XcodeBuildMCP) and the invariants of each subsystem. Read it first.

## Visual features and animations: judge them from recorded frames

A green build and passing unit tests say nothing about how a change looks or moves. For any visual change, and always
for one that animates, record the simulator while it happens, turn the recording into images of its frames labelled
with their index and time, and evaluate the animation from those before calling the work done. Unit tests pin the
model (a choreography's values, a layout's frames); only the frames show what is drawn: what is clipped, what pops in,
what moves together and what lags, where it overshoots and whether it settles.

### 1. Know what correct looks like first

Write down, before recording, what the frames should show: which elements move, which move together, the direction,
roughly how long, whether a spring should overshoot and how many times, what must never be visible (a gap, a clipped
edge, an element standing still while its neighbours move). The evaluation is a comparison against this; without it
the frames only get described.

### 2. Record

Recording is passive: it does not touch the installed app or its state. Installing or replacing the app is not; follow
`CLAUDE.md` and the user's standing instructions on which simulator an agent may install on, and otherwise ask the user
to install the build and then record what they or you trigger.

```sh
U=<simulator udid>                       # xcrun simctl list devices booted
OUT=<scratch directory>                  # not the repo
xcrun simctl io "$U" recordVideo --codec=h264 --force "$OUT/anim.mp4" > "$OUT/rec.log" 2>&1 &
REC=$!
until grep -q "Recording started" "$OUT/rec.log"; do sleep 0.1; done
# … trigger the animation: XcodeBuildMCP taps/swipes, a deep link (xcrun simctl openurl), or ask the user …
sleep 1                                  # let it settle on camera
kill -INT $REC; wait $REC                # SIGINT finalizes the file
```

- Use `simctl io recordVideo`, not XcodeBuildMCP's `record_sim_video`: the latter resamples to a fixed rate (30 fps by
  default), which hides exactly the frame-level detail being looked for.
- The recording is **variable-rate**. The simulator writes a frame only when the screen changes, stamped with its own
  time (1/600 s units), at the display's rate while something moves (16.7 ms median on an iPhone 17 / iOS 26.5
  simulator, 10 ms on the iPhone 18 Pro / iOS 27 one; the script prints it). A still screen produces no frames, so a
  stall appears as one long interval, and time must always come from a frame's timestamp, never from its index. It
  also writes the odd near-copy a few ms after a frame.
- **Take the timestamps from `ffprobe`, never from `ffmpeg`.** The file can carry a duplicated timestamp, after which
  `ffmpeg` (its `showinfo`, its `select` on `t`) falls back to each frame's decode time, seconds behind (measured:
  11.66 s, then 8.07 s for the next frame); the frames themselves still come out in order. The script handles this;
  anything hand-rolled must too.
- Frames are the device's pixels (3x: a 402 × 874 pt screen records at 1206 × 2622).
- A tap at a point, where XcodeBuildMCP offers only element taps: `axe touch -x X -y Y --down --up --delay 0.08
  --udid "$U"` (points). Issue it in the same shell command as the recording, so the tap lands a known time into it.
- Record the whole gesture with a little still time on both sides, once per path the change touches (open and close,
  each entry point, light and dark, with and without the optional content), and in slow motion only in addition to
  real speed, never instead: timing is part of what is being judged.

### 3. Turn it into frames

```sh
python3 tools/animation_sheet.py "$OUT/anim.mp4" "$OUT/sheet" --start 0.4 --end 1.6 \
  [--crop X,Y,W,H] [--track NAME=X,Y,W,H ...] [--tile-width 200] [--columns 8] [--rows 4]
```

All geometry is in points (the recording's pixels over `--scale`, 3 by default): `--crop`, `--track` and every number
it prints.

It writes, into the output directory:

- `sheet-NN.png`: every frame in the range, tiled in time order, each labelled `#index  t=seconds  +ms since the
  previous frame`, with flagged frames framed in red. Open them with the image-reading tool.
- `motion.png`: per frame, how much the picture changed since the previous frame (bars), the interval since the
  previous frame (dots, dashes at the median) and how far the picture still is from the last frame (green line).
- `tracks.png` (with `--track`): each tracked region's offset from its resting place per frame, one line each.
- `frames.tsv`: the same numbers per frame, with the region that changed and each track's offset and match error.
- `frames/NNNNN.png`: the frames themselves, numbered as on the sheets.

and prints a summary: when the motion starts and stops, when it comes within 2% of its resting state for good, every
time it passes its rest and comes back out (a spring's overshoot, an oscillation), every flagged frame, each track's
path and how far apart the tracks ever are:

- `gap`: an interval over 1.5x the median while the picture changes by at least 5% of the clip's largest change: a
  frame drawn late, or a stall (a spinner or caret drawing at its own lower rate is not counted).
- `jump`: a frame that changed over 3x as much as the frames around it: a snap, a teleport, something appearing or
  vanishing at once in the middle of smooth motion.

**Tracks are the precise instrument.** `--track NAME=X,Y,W,H` names a region of the LAST frame (the rest; for
something leaving, a close, pass `--track-reference first` and name it in the first frame); in every frame the script finds where that content stands, shifted vertically, and reports the offset in points: negative
above its rest, positive below, 0 at rest. One track gives an element's real path (where it starts, how far past its
rest it goes, when it is within 1 pt); several give "these move together" as a number: in every frame where all are
found their offsets must agree. Pick each region inside one element, with texture (text, icons, edges), clear of
anything that moves differently, and get its coordinates from the last frame (`frames/` holds it at points scale).
Matches are only as good as the template: text that is still changing size or colour, or that lies over content
changing behind it (a photo, a pattern fading in), reads as not found (`-`) or, worse, as a confident wrong offset in a
handful of frames; rows that look alike (list rows) can match one another. Trust a stretch where several tracks
agree, and check a disagreement on the sheet before reporting it.

Use `--start`/`--end` to keep only the motion (the summary's times are the recording's own clock) and `--crop` to look
at one part of the screen: the distance-from-rest curve and the change bars measure whatever is in the picture. Mind
the scale: a 200 px tile of a 402 pt screen is half a pixel per point, so a 9 pt overshoot moves 4–5 px on the sheet;
crop and raise `--tile-width` until the motion being judged is visible.

### 4. Evaluate

- **Shape.** The green line is the motion's shape: an ease-out falls to 0 and stays; a spring falls, touches its rest
  and rises again by its overshoot before settling, once per oscillation; a step in it is a hitch. Compare the summary's
  duration, settle time and passes with what was intended. The pass percentages are of the picture's difference, not
  of the travel distance: use them to tell whether it overshoots and how many times, and read the amount off the
  frames.
- **Togetherness.** For "these move together", track each element: elements that move as one stand at the same
  offset in every frame, overshoot included, which the summary's pairwise "apart by at most" states. An element that
  rests while its neighbours move, arrives a frame late or overshoots alone is the defect class this catches. Elements
  on one spring but with different travel overshoot in proportion to their travel: same phase, different amplitude.
- **Every flagged frame.** Open the tiles around it and say what it is. A `jump` can be legitimate (an element meant
  to appear at once); a `gap` on the simulator can be the Mac's. A gap that recurs at the same point across several
  recordings is the app's; frame pacing itself is confirmed on a device, not the simulator.
- **The frames, not just the numbers.** Read the sheets end to end for what no metric sees: clipping, a wrong z-order
  for a frame, a colour flash, text re-wrapping mid-flight, an element drawn twice during a hand-over.

Report findings with their evidence, by frame: "#23–#31 (t=0.512–0.645): the list stays at rest while the buttons
overshoot 9 pt" names something another agent or the user can open and check. A claim about an animation without frame
references has not been verified.
