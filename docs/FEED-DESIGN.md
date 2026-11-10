# Moments feed layout

iOS and Android use this file. The list is the Threads layout. Post comments are the Douyin bottom sheet. Colors come from the Telegram theme, including dark mode. There is no card fill.

## List

| Token | Value |
| --- | --- |
| Background | plain theme background |
| Divider | 1 px, theme divider |
| Avatar | 40 pt circle |
| Follow badge | 16 pt circle, “+”, accent fill, bottom-right of the avatar. Hidden once followed. No separate Follow label |
| Header | username, bold, then grey relative time on the same line |
| More | top-right `…` |
| Body | under the name, list font size, primary text |
| Text column inset | 12 pt screen padding, 40 pt avatar, 10 pt gap |
| Media | 12 pt corners. One image or video spans the text column. Several images are a horizontal carousel; each slide is about 78% of the column so the next one peeks |
| Quote / link | rounded embedded card |
| Actions | icon then count: heart, bubble, repost arrows, paper plane. No text labels. Grey. Heart is `#FF3B30` when liked |
| FAB | 56 pt circle, trailing 20 pt, 16 pt above the tab bar, accent fill, white “+” |
| Notifications | heart, top right only |

## Comment sheet

| Token | Value |
| --- | --- |
| Sheet | bottom panel, 16 pt top corners, starts near 32% of the screen, expands to the status bar |
| Scrim | black at 45% |
| Title | centred, “N comments” / “N条评论” |
| Controls | expand and close |
| Avatar | 32 pt |
| Name | 12 pt, secondary |
| Body | 15 pt, primary |
| Meta | time, then Reply. Province is omitted until the engine sends it |
| Author tag | “Author” / “作者” when the commenter is the post author |
| Like | heart and count on the right. Dislike is omitted until the engine sends it |
| Replies | collapsed as “Show N replies” / “展开N条回复”. Expanded rows are indented and may start with “Reply @name” |
| Input | “Say something” / “发条评论，说说你的感受” |

## Icons

| Use | Android | iOS |
| --- | --- | --- |
| Tab | feed tab glyph | `Chat List/Tabs/IconNews` |
| Notifications | `media_like` | `Stories/InputLikeOff` |
| Compose | plus on the FAB | `Chat/Context Menu/Add` |
| Like | `media_like` / `media_like_active` | `Stories/InputLikeOff` / `Stories/InputLikeOn` |
| Comment | `input_reply` | `Chat/Context Menu/Reply` |
| Repost | `msg_forward` | `Chat/Context Menu/Forward` |
| Share | `msg_share` | `Chat/Context Menu/Share` |
| More | `ic_ab_other` | `Chat/Context Menu/More` |

## Strings

iOS keys live in `Localizable.strings` as `Moments.*`. The wording matches Android `Feed*`. If the active language code starts with `zh` and the langpack still has the English source, the Chinese string is used.

## Engine fields still unused

The sheet does not invent these. They are not on the comment model today:

- IP province
- dislike
- a share count on the post
