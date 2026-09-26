# 一千四百一十八天 · 东线档案

原生 macOS 文字冒险游戏（SwiftUI，无第三方依赖）。1941.6.22—1945.5.9，苏德战争东线，
玩家是一个从排长打到团长的红军军官；框架是 2011 年他的外孙女在白俄罗斯的赤杨林里挖出一枚写着外公名字的纪念章。

> 这是 `macos` 分支：只有 Mac 版。iPhone / iPad 版在 [`ios` 分支](https://github.com/Leo-learner/days-1418/tree/ios)，和 Mac 版共用同一份引擎和剧本。

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

## 目录

- `Sources/` Swift 源码：`Expr`（表达式）、`Story`（剧本解析）、`Engine`（运行时）、`Checker`（检查器）、各界面
- `story/` 剧本：`00_defs` 声明，`01_frame` 框架，`1x` 第一卷，`2x` 第二卷，`3x` 第三卷与补充场景，`4x` 第四卷、尾声与真结局，`9x` 结局登记与档案
- `docs/BIBLE.md` 剧本圣经：真实历史、人物、变量、结局与档案对照表、剧本语法
- `tests/*.walk` 攻略文件

本作部队番号、人物与村庄均为虚构；历史背景、制度与时间线参照真实事件。
