# JM UI 重写交付说明

把工作区这个 Flutter 漫画应用的**全部界面**按 GitHub 上 [FlClash](https://github.com/chen08209/FlClash) 的界面规范重写。

## FlClash 规范是怎么落地的

克隆了 FlClash 仓库到 `Q:\ref\FlClash`，研读它的两份规范：

- `.agents/surfaces.md` —— 表面层级（page/card/block/inset 四级明度）、种子色方案、状态色、圆角、按压反馈、导航
- `.agents/skills/ui-work/SKILL.md` —— 组件约定、圆角 token、字体 token、交互 checklist

FlClash 的界面由 `prism_ui` 组件库实现（github.com/chen08209/prism_ui，43k 行）。这个库是**替代 Material 的完整设计系统**（自带 Theme / ColorScheme / Card / ListRow / Sheet / Dialog / NavigationDock / Glyph 图标…），已内联到 `packages/prism_ui` 并作为 path 依赖接入。应用根也从 `MaterialApp` 换成了 `PrismApp`，和 FlClash 一致。

## 做了什么

| 层 | 变更 |
|---|---|
| 设计系统 | 内联 `prism_ui` v0.1.3；品牌红种子色 + `vivid` 配色；四级表面层级；iOS Dynamic Type 字号；连续超椭圆圆角 token |
| 应用根 | `MaterialApp` → `PrismApp`；新增中文本地化 delegate、`JmViewScope`、BannerHost 提示系统 |
| 图标 | 从 FlClash 搬运 132 个 glyph + 补 16 个漫画业务 glyph，全部是矢量 glyph（不再用 icon font） |
| 共享套件 | `lib/ui/`：页面骨架 `JmPage`、三态 `JmLoading/JmEmpty/JmError`、专辑卡 `AlbumCard/AlbumListTile`、行 `SettingRow/NavigationRow/ValueRow`、分组 `SectionCard/SectionHeader/TagWrap`、搜索框 `JmSearchField` |
| 状态层解耦 | 新增领域枚举 `JmThemeMode`，`AppState`/持久化层不再依赖任何 UI 库；只在 `main.dart` 映射一次 |
| 导航 | 手机端浮动 `NavigationDock` + 桌面端 `NavigationSidebar` 自适应；保留懒构建与页签状态保活 |
| 12 个页面 | 起始页、首页+搜索三件套、书库、周表、账号三页、分页列表、专辑详情+评论区、阅读器、设置页，全部重写 |
| 转场 | 卡片→详情页的容器变换、JM 号直达的矩形展开，改用 prism 的 `OpenContainer` 与自定义 `PageRouteBuilder` |
| 清理 | 删除旧 Material/M3E 组件、`app_theme.dart`、`m3e_bridge.dart`；移除 `material_3_expressive`、`cupertino_icons` 依赖 |

**保留不变的东西**：网络层、缓存、图片解密管线、`AppState` 数据流、分页参数、搜索历史、登录态、阅读器的 `ui.Image` 引用计数、各种手势与动画锚点。这次只换表现层。

## 验收结果

- `flutter analyze`（全仓）：**No issues found!**
- `flutter test`（全量）：**86 tests passed**
- 生产代码 `lib/` 里 `material_ui` / `material_3_expressive` / `flutter/material.dart` 的 import：**0 处**
- `flutter build apk --debug`：**构建成功**
- 真机（Android 模拟器 SM-A5260 / Android 15）：**安装并运行通过**，逐页验证起始页、主框架、书库、设置、专辑详情、阅读器均无崩溃
- **液态玻璃（ultra）**：全局开启，真机旋转 10 次压力测试无红屏

### 真机排查记录（均已修复）

**1. `No ViewScope found above RootShell`**：`JmViewScope` 曾在 `PrismApp.home` 里，而起始页 `pushReplacement` 进 `RootShell` —— 新路由不在 home 子树下。修法：移到 `PrismApp.builder` 包住整个 Navigator；回归测试 `test/view_scope_regression_test.dart`。

**2. `Invalid image dimensions`（液态玻璃红屏）**：ultra 档带 haze 层，在横竖屏切换的过渡态里，玻璃面板的 `covered` 矩形塌缩到 0，`liquid_glass_capture.dart` 的 `toImageSync(0, h)` 抛异常。这是 prism_ui 自身的边界 bug（standard 档 haze 少未触发）。修法（对内联的 `packages/prism_ui` 打补丁，2026-11 已重新落进源码并验证）：
- `_place`：`covered.isEmpty` 时跳过该面板；
- `_snapshot`：尺寸不足 1px 时改用 `math.max(1, ...)` 调 `toImageSync`（atlas 比之前记录的更简单——直接钳到 1×1，无需「复用上次 atlas」的分支）；
- 顺手补了同类入口的零尺寸短路：`theme_cross_fade.dart` 的 `capture()`（`size.isEmpty` 时返回 null）与 `popup.dart` 的 `_captureSource`（boundary 尺寸为空时放弃快照）。
回归测试 `test/liquid_glass_zero_size_test.dart`（把玻璃面板尺寸压到 0 再恢复，断言不抛异常、atlas 尺寸始终 > 0；另覆盖主题切换的 capture 路径）。

每个页面迁移时还写了临时 widget 测试做程序化验收（浅色/深色 × 320/390 宽、三态、溢出、对比度、圆角 token、层级明度、行为断言），验收完删除。观感类项目（ink 手感、封面裁切、中文行高、沉浸背景色）已通过真机截图逐页确认。

## 文档索引

- `docs/prism_ui_api.md` —— prism_ui API 速查（2630 行，签名逐字抄自源码）
- `docs/jm_ui_kit.md` —— 共享 UI 套件用法
- `docs/jm_ui_inventory.md` —— 改造前页面行为清单
- `docs/jm_ui_migration_rules.md` —— 迁移硬性规约

## 待人工确认 / 已知问题

1. **详情页封面在宽屏（横屏）下过高**：`expandedHeight` 沿用原实现的「屏宽 × 4/3」，在 1920 宽横屏上算出来是 2560px，超过一屏，需要滚动较久才到元数据。这是**原实现既有行为**（本次只换表现层，未改布局参数），若要修，可把封面高度改为「屏宽 × 4/3」与「屏高 × 0.6」取较小值。
2. 封面真实观感（CDN 裁切、低分辨率放大）；
3. 按压 ink / sparkle、ActivityIndicator 的动效手感；
4. 主题切换、明暗过渡的淡入淡出色；
5. 模拟器为横屏 1920×1080，因此自动走了桌面侧栏布局（`ViewScope` 断点 720）；竖屏手机会走底部浮动 dock。两种形态都已实现，但 dock 形态尚未在竖屏真机上截图确认。

## 环境备注（构建相关）

本机 `flutter build apk` 需要显式指定环境变量，否则会因 JDK 版本不匹配失败：

```powershell
$env:ANDROID_HOME = "Q:\AndroidstudioSDK"
$env:ANDROID_SDK_ROOT = "Q:\AndroidstudioSDK"
$env:JAVA_HOME = "Q:\Androidstudio\jbr"    # Java 25；SDK 自带的 JDK 是 Java 27，与 Gradle 9.5 不兼容
```

若之前有失败的构建残留，先 `Get-Process java | Stop-Process -Force` 清掉旧 daemon，否则会复用错误版本的 JVM。
