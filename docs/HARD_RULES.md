# Tellomi 硬规则（iOS / Telegram-iOS）

给后续 AI / 机器人 / 新同学看的固定规则。改规则开 PR，不要只改聊天记忆。同套规则也在 `tellomi/teamgram-server` 与 `tellomi/Telegram` 的 `docs/HARD_RULES.md`。

## 项目是什么

1. Tellomi 是面向中国大陆的陌生人交友 App；本仓是 Telegram-iOS 改牌客户端。
2. 服务器：`tellomi/teamgram-server`；Android：`tellomi/Telegram`。

## 协作与发版

3. 合 PR、修 bug、构建：团队自行决定直接做，不用请示。
4. 完成一个阶段/PR 在「所有权限管理、cms goco」群推短讯（改动 + PR 链接）。
5. 不要完善一点就出 TestFlight；攒批再测再发；双端齐再出正式测包（如 14.0.3）。闪退等可临时单验 TF。
6. 密钥向「所有权限管理」索取；GitHub 连接 @3mmmbulus。

## 客户端改动

7. 改动最小化，对照上游；改动记入 `Tellomi/UPSTREAM_PATCHES.md`。
8. 别自写一套登录/设置布局；对照上游双端。
9. 登录默认区号 +86。
10. 登录改牌后勿留死引用（例：`phoneInputNode` 重命名后主题刷新仍引用；`public extension` 里多余 `public`）。合入前全局搜。
11. 安装包保持瘦：贴纸/主题/大图 CDN 按需；别塞无用素材；对照上游。
12. 手机 OTP 登录后须写入账号 peer，再进主界面，否则闪退（见 #21）。

## 服务器地址

13. DC 用 IP：`8.137.39.82:10443`（生产/dev）。预发端口 11443 / `staging-api.tellomi.cn`。不要用主机名当 DC。
14. 出包前确认连的是 Tellomi 后端，不是官方 Telegram。

## 与服务器 API

15. 服务器补 API 对照官方 MTProto；客户端覆盖只跟官方四端实际调用。
16. 「已实现」≠ 与 Telegram 公网一比一。
