# 一千四百一十八天 · 东线档案（网页版）

文字冒险游戏，纯 HTML / CSS / JavaScript，无第三方依赖、无构建框架。1941.6.22—1945.5.9，苏德战争东线，
玩家是一个从排长打到团长的红军军官；框架是 2011 年他的外孙女在白俄罗斯的赤杨林里挖出一枚写着外公名字的纪念章。

> 这个分支只有网页版。Mac 版在 [`macos` 分支](https://github.com/Leo-learner/days-1418/tree/macos)，
> iPhone / iPad 版在 [`ios` 分支](https://github.com/Leo-learner/days-1418/tree/ios)。三个版本共用同一份剧本（`story/`），
> 网页版的引擎是 Mac 版 Swift 引擎的逐行移植：同一个随机数种子、同样的选择，得到完全一样的结果。

- 四卷正文 + 尾声：包围圈（1941）→ 伏尔加（斯大林格勒）→ 大河（库尔斯克、第聂伯河、基辅、1944 白俄罗斯）→ 柏林（1945）→ 之后（1946—2012）
- 325 个节点、约 10.7 万字正文、32 个结局（BE/NE/GE/SE/TE）、41 份可解密档案
- 每个结局解密一份档案，揭示"这个结局真正属于谁"；档案会在后续周目里解锁【档案】选项，真结局要靠三份关键档案拼出来
- 属性检定（指挥/战术/胆识）、人性/创伤/嫌疑、兵力弹药、十几个人物的信任与生死，全部带到后面的章节
- 随机数种子随存档保存，读档刷不出运气；另有"铁人"模式（只有自动存档、不能回溯）

## 网页版有什么

- 和 Mac 版一样的界面：标题、正文（逐段浮现 / 打字机 / 立即显示）、右侧"军人证"、结局与档案解密、档案馆、8 个存档位 + 自动存档、战斗日志、回溯
- 夜 / 纸两套配色，雪、灰烬、火星、雨、花瓣等场景氛围（可关）
- 手机宽度可玩：军人证收进右侧抽屉，每一屏正文开头用小标签提示上一个抉择改变了什么（和 iOS 版一样）
- 键盘：空格/回车 继续 · 1–9 选择 · Z 回溯 · L 日志 · A 档案馆 · S 存档 · O 读档 · M 军人证 · Esc 返回
- 存档：
  - 单独打开网页时存在浏览器 localStorage 里
  - 放在 [Game Hub](https://games.dkz12345.com/)（`/play/<slug>/<版本>/`）里时自动接入网站的云存档：登录后自动存档、8 个存档位和跨周目进度都存到云端（共 10 个云槽）；游客按网站约定不落盘，进度只留在当前页面
  - 一局完整存档的 JSON 约 700 KB，统一 gzip 后再存，约 100 KB，远低于 Game Hub 单槽 1 MiB 的上限

## 试玩与打包

需要 Node.js 20 以上。

```bash
npm run serve          # http://localhost:8418/  直接用 web/ 源码，改完剧本刷新即可
npm run build          # → build/web/（静态网站）和 build/days-1418-web.zip（Game Hub 上传包）
```

`build/web/` 可以放到任何静态托管上。`?seed=11` 让新的卷宗使用固定的随机数种子（和攻略文件里的 `@seed` 对应），调试用。

## 发布到 games.dkz12345.com

`build/days-1418-web.zip` 的根目录就是 Game Hub 要求的格式：`index.html` + `game.json`（10 个存档槽）+ `cover.svg`（16:9 封面）。
在装好 game-hub MCP 的机器上：

```bash
# game_site 仓库里，已 source 过含 GAME_HUB_MCP_TOKEN 的私有 env
node scripts/mcp-upload.mjs days-1418 /绝对路径/days-1418/build/days-1418-web.zip
```

或者直接让 Codex / Claude Code 通过 game-hub MCP：`create_game`（slug `days-1418`，标题"一千四百一十八天"）→
`prepare_game_upload` → PUT 上传 ZIP → `get_game` 检查版本 → `publish_game`。

## 剧本工具

```bash
npm test                                             # 回归测试：解析、表达式、随机数、两条攻略、300 局模拟
npm run check                                        # 静态检查 + 2000 局带跨周目进度的蒙特卡洛模拟
node tools/check.mjs story -runs 6000 -seed 7        # 模拟更多局
node tools/walk.mjs tests/true_ending.walk -expect e30   # 按攻略走到真结局
node tools/walk.mjs tests/good_ending.walk -expect e26   # 按攻略走到好结局
```

## 目录

- `web/` 网页版：`index.html`、`style.css`、`src/`（`expr` 表达式、`story` 剧本解析、`engine` 运行时、`store` 存档后端、`atmosphere` 场景氛围、`app` 界面）、`game.json` / `cover.svg`（Game Hub 清单与封面）
- `story/` 剧本：`00_defs` 声明，`01_frame` 框架，`1x` 第一卷，`2x` 第二卷，`3x` 第三卷与补充场景，`4x` 第四卷、尾声与真结局，`9x` 结局登记与档案
- `tools/` 打包、本地服务器、剧本检查器与按攻略走查的工具（Swift 版 Checker 的移植）
- `docs/BIBLE.md` 剧本圣经：真实历史、人物、变量、结局与档案对照表、剧本语法
- `tests/` 回归测试和 `*.walk` 攻略文件

本作部队番号、人物与村庄均为虚构；历史背景、制度与时间线参照真实事件。
