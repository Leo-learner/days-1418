# 一千四百一十八天 · 东线档案

原生 macOS / iOS 文字冒险游戏（SwiftUI，无第三方依赖）。1941.6.22—1945.5.9，苏德战争东线，
玩家是一个从排长打到团长的红军军官；框架是 2011 年他的外孙女在白俄罗斯的赤杨林里挖出一枚写着外公名字的纪念章。

> 这是 `ios` 分支：Mac 版 + iPhone / iPad 版，两者共用同一份引擎和剧本。只要 Mac 版请看 [`macos` 分支](https://github.com/Leo-learner/days-1418/tree/macos)。

- 四卷正文 + 尾声：包围圈（1941）→ 伏尔加（斯大林格勒）→ 大河（库尔斯克、第聂伯河、基辅、1944 白俄罗斯）→ 柏林（1945）→ 之后（1946—2012）
- 325 个节点、约 10.7 万字正文、32 个结局（BE/NE/GE/SE/TE）、41 份可解密档案
- 每个结局解密一份档案，揭示"这个结局真正属于谁"；档案会在后续周目里解锁【档案】选项，真结局要靠三份关键档案拼出来
- 属性检定（指挥/战术/胆识）、人性/创伤/嫌疑、兵力弹药、十几个人物的信任与生死，全部带到后面的章节
- 随机数种子随存档保存，读档刷不出运气；另有"铁人"模式（只有自动存档、不能回溯）

## 构建

```bash
./build.sh            # 编译 → 检查剧本（2000 局模拟）→ 渲染图标 → 打包 → 覆盖安装到 ~/Desktop/一千四百一十八天.app
NO_INSTALL=1 ./build.sh   # 只打包到 build/，不动桌面
RUNS=6000 ./build.sh      # 模拟更多局
```

## 剧本工具

```bash
build/Days1418 -check story -runs 3000        # 静态检查 + 带跨周目进度的蒙特卡洛模拟
build/Days1418 -walk tests/true_ending.walk -story story   # 按攻略走到真结局
build/Days1418 -walk tests/good_ending.walk -story story   # 按攻略走到好结局
```

自检截图（本机没有屏幕录制权限时用）：

```bash
"build/一千四百一十八天.app/Contents/MacOS/Days1418" -snapshot /tmp/a.png -screen game -node a1_start -datadir /tmp/d1418 -textMode 2
```

`-screen` 可选 title / game / archive / log / settings / load / newgame；`-unlockAll YES` 解锁全部结局和档案；
`-datadir` 把存档写到别处，不碰真存档（真存档在 `~/Library/Application Support/Days1418/`）。

## iOS 版

`iOS/` 是原生 iPhone / iPad 版（SwiftUI，iOS 17+）。引擎、存档、配色、氛围特效直接引用 `Sources/` 里的
`Expr / Story / Engine / Store / Checker / GameModel / Theme / Effects`，剧本直接打包 `story/`——**改剧本两边同时生效**；
界面层是 iOS 自己的一套（`iOS/Days1418/`）。Xcode 工程由 [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
按 `iOS/project.yml` 生成，不进仓库，也不要手改 `.xcodeproj`。

```bash
iOS/build-ios.sh            # 检查剧本 → 生成工程 → 编译 → 装进模拟器启动（默认 iPhone 17 Pro）
iOS/build-ios.sh device     # 编译 Release 装到数据线连着的 iPhone
iOS/build-ios.sh open       # 生成工程并用 Xcode 打开
SIM="iPad Pro 11-inch (M5)" iOS/build-ios.sh
```

装真机要用你自己的苹果开发者团队 ID：写进 `iOS/.team`（一行，已在 `.gitignore` 里），或者 `DEVELOPMENT_TEAM=… iOS/build-ios.sh device`。
免费的个人团队签出来的 App 7 天后失效，重跑一次 `device` 即可（覆盖安装不丢存档）。

和 Mac 版不同的地方：

- **字体**：宋体（Songti SC）和仿宋（STFangsong）在 iOS 上是系统"按需下载"字体。第一次启动要联网下载（约 55 MB，走 Apple），
  期间先用苹方；以后每次启动都要重新"激活"（一秒内，不用联网）。`Fonts.serifReady` 在激活前把宋体/仿宋换成苹方——
  不能先用 "Songti SC" 去要字，SwiftUI 会把退回苹方的结果按字体描述缓存住，字体到位后也换不回来。
- **下载只走 Wi-Fi**：真机实测蜂窝网络下（包括开了"5G 下允许更多数据"的 5G）系统接了请求却一直卡住。
  `FontLoader` 按网卡类型判断：卡在蜂窝网络时在标题页和"更多"菜单里提示，连上 Wi-Fi 自动重发请求。
  下载过程记在 App 的 `Library/Caches/fonts.log`，真机上用 `xcrun devicectl device copy from … --domain-type appDataContainer` 取回。
- **军人证**：手机上收进底部面板；每次抉择后正文开头挂一排数值变化标签（`Changes.swift`，挑哪几项由 `pickHeadlineChanges` 决定）。
  iPad 横屏/竖屏都保留右侧栏。
- **切到后台**时写一次自动存档并停表，后台时间不算游戏时长（`GameModel.suspend()/resume()`，Mac 版不调用）。
- 存档在设备自己的沙盒里，和 Mac 版不互通。

模拟器自检用启动参数跳界面（只在 Debug 构建里有效），配合 `xcrun simctl io booted screenshot a.png`：

```bash
xcrun simctl launch booted local.leo.days1418 -screen game -node a1_start
xcrun simctl launch booted local.leo.days1418 -screen archive -unlockAll YES -tab 1 -doc d06 -theme 1
```

## 目录

- `Sources/` Swift 源码：`Expr`（表达式）、`Story`（剧本解析）、`Engine`（运行时）、`Checker`（检查器）、各界面
- `iOS/` iOS 版：`project.yml`（工程描述）、`Days1418/`（iOS 界面层）、`tools/render-icon.swift`（铺满式 iOS 图标）
- `story/` 剧本：`00_defs` 声明，`01_frame` 框架，`1x` 第一卷，`2x` 第二卷，`3x` 第三卷与补充场景，`4x` 第四卷、尾声与真结局，`9x` 结局登记与档案
- `docs/BIBLE.md` 剧本圣经：真实历史、人物、变量、结局与档案对照表、剧本语法
- `tests/*.walk` 攻略文件

本作部队番号、人物与村庄均为虚构；历史背景、制度与时间线参照真实事件。
