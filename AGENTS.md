# AGENTS.md

Guidance for coding agents working in this repository. The project guide is [`CLAUDE.md`](CLAUDE.md): how to build,
which simulators to use, how to drive them (XcodeBuildMCP) and the invariants of each subsystem. Read it first.

## Owner rule: the UI stays Telegram's

UI must stay Telegram original (upstream Telegram-iOS); only data within 动态 may be custom. Any PR touching UI (assets, theme, tab bar, login, settings, chat list, profile) requires the owner's explicit approval after seeing screenshots. Never replace release/ios with master (no `git push origin master:release/ios`, no whole-tree syncs). Agents must never merge their own PRs; merges require owner approval.

动态 is `submodules/TelegramUI/Components/Moments`. A release is a pull request into `release/ios` that the owner merges. That merge starts TestFlight. The same rule is in `.cursor/rules/telegram-native-first.mdc`.

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

## 谷歌表格台账规则（强制）

每个修复都要把共享谷歌表格台账写完整。这张表是唯一台账，不要另建平行清单。

表格 ID：`19aChHJdxQeSRMIoc5cQxtaM6lFsylSo7WTpVy3H-dog`  
地址：https://docs.google.com/spreadsheets/d/19aChHJdxQeSRMIoc5cQxtaM6lFsylSo7WTpVy3H-dog

页签：

- **问题清单**：bug 台账。
- **测试日志**：每条测试记录。
- **AI交接**：交接记录。状态词的含义见第 45–46 行，修复 AI 的义务见第 47 行。
- **修复跟踪说明**：状态词的权威页。当前最新一条是第 29–33 行「2026-11-15 更新（以此为准）」。

「修复跟踪说明」页、「AI交接」页和本仓库文档三处不一致时，以「修复跟踪说明」页最新一条为准。

### 问题清单表头（逐字）

定位列时，列字母和表头必须一起核对。表头必须与下面整段文字完整精确匹配：少字、多字、或只取其中几个字，都不算这一列。

- A 编号
- B 关联用例
- C 严重级别
- D 模块
- E 平台
- F 标题
- G 复现步骤
- H 期望
- I 实际
- J 证据路径
- K 发现日期(北京)
- L 状态（禁改）
- M 修复PR
- N 最近测试时间
- O 结果
- P 修复状态
- Q 回归轮次
- R 涉及Telegram原版代码（禁改）
- S 备注/证据
- T 修复跟踪状态
- U 修复负责(cloud agent 链接)
- V PR 链接
- W PR head SHA
- X 审查状态
- Y 合并SHA/部署
- Z 更新时间(北京时间)
- AA 修复说明
- AB 涉及文件/接口
- AC 回归测试日志行
- AD 回归结论
- AE 备注

「状态」只完整匹配 L 列，而 L 列禁改。要写的修复跟踪状态是 T 修复跟踪状态。P 的表头是「修复状态」，不是跟踪状态，不要把跟踪状态写进 P。AE 备注不是 S 备注/证据。

### 新 bug

先在「问题清单」查重。确认是新问题后，只用 append 追加新行。改已有行必须先按 A 编号定位。写之前重新读取该行（多个 AI 会同时改表）。绝不修改 L 状态和 R 涉及Telegram原版代码。

### 修复 PR

每个修复 PR 的标题或正文必须写明所修问题 ID（A 编号的单元格值）。一个 PR 修多条时，逐条列出。

### 回写列

做修复的 AI 只回写下列列。每一列都要同时对上列字母和逐字表头：

- T 修复跟踪状态
- U 修复负责(cloud agent 链接)
- V PR 链接（多个用「 ; 」分隔）
- W PR head SHA
- X 审查状态
- Y 合并SHA/部署
- Z 更新时间(北京时间)
- AA 修复说明（根因 + 怎么修，1–3 句）
- AB 涉及文件/接口（核心非测试文件；有接口或 RPC 时写名称）
- AC 回归测试日志行（测试日志的行号，逗号分隔）
- AD 回归结论（通过/部分/失败 + 时间 + 日志行）
- AE 备注（补录、冲突、改了别人哪个旧值及原因；历史补登写「补登」）

### 状态取值

新写入的 T 修复跟踪状态只用「AI交接」第 45–46 行的词。主路径是：待修复 → 修复中 → 待审查 → 待合并 → 已合并待部署 → 已部署待回归 → 已修复(回归通过)。另外三个：回归失败、不修复(负责人决定)、重复。

含义：

- 待修复：已确认、无 PR。旧值「未开始(待批准)」与此相同，但已写上的旧值不必改写成新词。
- 修复中：有 PR，但 CI 未绿，或审查未过需要返修。
- 待审查：CI 已绿，等独立审查；或审查之后 head 已经变了。
- 待合并：审查 PASS，且 head 等于审查 SHA，CI 全绿。
- 已合并待部署：已进 master，未上生产。
- 已部署待回归：已上生产，等回归。
- 已修复(回归通过)：回归测试日志里有通过行。
- 回归失败：回归不通过。AD 回归结论写原因，AE 备注写后续 PR。
- 不修复(负责人决定)：用户或产品决定不修。
- 重复：与另一行是同一个问题。AE 备注写主行号。

旧值保留，不改写。下次更新该行时，换成下面的新值。对照来自「修复跟踪说明」第 32 行：

| 旧值 | 新值 |
| --- | --- |
| 未开始(待批准) | 待修复 |
| 修复中(已批准 HH:MM)、修复中-已暂停(WIP分支) | 修复中 |
| PR已提交-待批准审查、PR已提交-审查中 | 待审查 |
| 审查未通过-待批准修改 | 修复中 |
| 审查通过-待批准合并 | 待合并 |
| 已合并-待部署 | 已合并待部署 |
| 已部署-待回归 | 已部署待回归 |
| 回归通过、回归通过（服务端）、已验证通过 | 已修复(回归通过) |
| 不修(产品决定) | 不修复(负责人决定) |

### 开工、合并、发版

已确认的 bug 直接开修，不再逐条等批准。合并仍须独立审查 PASS、CI 全绿，且 head 等于审查 SHA。客户端发版仍须负责人批准。

### 修复 AI 的义务

与「AI交接」第 47 行相同：

1. 开 PR 时按 A 编号找到行，填写 T 修复跟踪状态 = 修复中、U 修复负责(cloud agent 链接)、V PR 链接、W PR head SHA、AA 修复说明、AB 涉及文件/接口。
2. 每次推新 head，更新 W PR head SHA 和 X 审查状态。
3. 合并后填写 Y 合并SHA/部署（merge SHA + 北京时间），T 修复跟踪状态 = 已合并待部署。
4. 部署后在 Y 合并SHA/部署 追加部署记录，T 修复跟踪状态 = 已部署待回归。
5. 回归后先在「测试日志」追加一行，再填 AC 回归测试日志行、AD 回归结论，并按结果改 T 修复跟踪状态。
6. 一个 PR 修多行时，每一行都要填。
7. 写前按 A 编号重新读该行。只改自己负责的格子。非空格子只有确认过时才改，并在 AE 备注说明。

发现历史修复没有登记的，顺手补齐，并在 AE 备注注明「补登」。

写入表格的内容不得包含任何密钥或生产聊天内容。
