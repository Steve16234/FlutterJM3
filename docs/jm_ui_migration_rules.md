# JM 界面迁移规约（prism_ui / FlClash 规范）

这份文档是**重写页面时的硬性规约**。任何一条违反都会导致界面和其余页面不一致，
或者在有动画/手势的页面上引入崩溃。改页面前先通读一遍。

配套文档：

- `docs/prism_ui_api.md` —— 组件签名与 API（2630 行，字典，按需查）
- `docs/jm_ui_kit.md` —— 共享 UI 套件（页面骨架 / 三态 / 专辑卡 / 行 / 分组 / 搜索框）
- `docs/jm_ui_inventory.md` —— 改造前各页面的行为清单（**行为以它为准**）
- 规范原文：`Q:\ref\FlClash\.agents\surfaces.md`、`...\skills\ui-work\SKILL.md`

---

## 1. import 规则

```dart
import 'package:flutter/widgets.dart';   // Text / Column / ListView / GestureDetector 等仍在 widgets 层
import 'package:prism_ui/prism_ui.dart'; // 全部 prism 组件

import '../ui/icons/icons.dart';         // 图标：AppGlyphs.xxx
import '../ui/page.dart';                // 页面骨架
```

- **禁止** `package:flutter/material.dart`、`package:flutter/cupertino.dart`、
  `package:material_ui/material_ui.dart`、`package:material_3_expressive/...`。
- 一个文件迁移完成后，必须把上面这些 import 全部删掉；`flutter analyze` 不接受残留。
- `dart:ui` 只用来取 `Color` / `Size` / `Image` 之类，不要 import `dart:ui` 里的 `TextStyle` 来绕。

## 2. 颜色、圆角、字号一律不许写死

| 不许写 | 改成 |
|---|---|
| `Color(0xFF...)` 字面色 | `context.colorScheme.primary / onSurface / onSurfaceVariant / destructive / success / warning` |
| 「卡片色」「页面色」 | `context.raisedSurfaceLevel.colorOf(context.colorScheme)` 或 `SurfaceScope` 下传 |
| `BorderRadius.circular(12)` | `AppShape.lg / AppShape.xl / AppShape.of(AppRadius.xxl)`（按**最短边**取 token） |
| `BorderRadius.circular(1000)` / `StadiumBorder` | `AppShape.full` |
| `fontSize: 14` | `AppTextStyle.footnote.of(context)`（13/18）；不许出现裸 `fontSize` |
| `fontWeight: FontWeight.bold` | `AppTextStyle.title3.of(context, emphasized: true)` |
| `Colors.white` 之类 | `context.colorScheme.onPrimary` 等语义色 |
| `Divider(color: ...)` | `Divider.colorOf(context.colorScheme)`（onSurface 14%） |

层级规则（`surfaces.md` §Levels）：`page` < `card` < `block` < `inset`，
**靠明度区分层次，不靠边框**。自己造了一个新表面，就必须
`SurfaceScope(level: level, child: ...)` 往下传，让里面的组件自己再降一级。
不许在调用点判断「是不是在 sheet 里」来决定颜色。

## 3. 组件替换对照（最常用的一批）

| Material | prism_ui |
|---|---|
| `Scaffold` | `PrismScaffold`（或套件里的 `JmPage`） |
| `AppBar` | `AppBar`（同名不同库）或 `JmPage.title` |
| `Text` | 同一个 `Text`（widgets 层），但样式必须来自 `AppTextStyle` |
| `Icon` / `Icons.xxx` | **删掉**，用 `GlyphIcon(glyph: AppGlyphs.search, ...)` |
| `InkWell` | `PressSurface` / `Card(onPressed:)` / `PressRegion` |
| `ListTile` | `Card` + `ListRow`（`ListRow` 只管几何，不带点击） |
| `Card` | `Card`（没有 `elevation`，有 `onPressed` / `isSelected` / `isError`） |
| `ElevatedButton` / `FilledButton` / `TextButton` | `FilledButton` / `TextButton`（同名的 prism 版本） |
| `IconButton` | `IconButton(data: IconButtonData(glyph: ..., tooltip: ..., onPressed: ...))` |
| `Switch` / `Checkbox` | 同名的 prism 版本（签名不同，查速查表） |
| `CircularProgressIndicator` | `ActivityIndicator` |
| `showDialog` | `showFloatingDialog` + `AlertDialog` |
| `showModalBottomSheet` | `showSheet` / `showSnapSheet` / `showFormSheet` |
| `SnackBar` / toast | `BannerHost.maybeOf(context)?.show('文案')` |
| `PopupMenuButton` | `PopupAnchor` + `PopupMenu`（菜单项是 `PopupMenuItem` 数据，不是 Widget） |
| `RefreshIndicator` | **不存在** → 刷新改成 app bar 的刷新动作（见 §6） |
| `ListView.separated` | `PrismListView` 或手写 `SliverList`（`ListRowSeparator` 是私有的） |
| `SliverAppBar` / `FlexibleSpaceBar` | 不存在，用 `PrismScaffold` + 可折叠头部自己叠 |
| `MaterialPageRoute` | `CardPageRoute`（`PrismApp` 默认）或自定义 `PageRouteBuilder` |

常用常量：`pageToolbarHeight`(72)、`sheetToolbarHeight`(48)、`listRowMinHeight`(56)、
`midDuration`(200ms)、`commonDuration`(300ms)；自适应尺寸用 `16.ap(context)`。

## 4. 页面骨架

```dart
JmPage(
  title: '设置',
  showBack: false,              // 一级页面没有返回
  actions: [
    ElasticPress(child: AppBarActionButton(data: IconButtonData(
      glyph: AppGlyphs.refresh, tooltip: '刷新', onPressed: _reload,
    ))),
  ],
  body: ...,
)
```

- 一级页面（底部导航的四个）`showBack: false`；二级页面保留默认 `true`。
- 页面 body 自己负责滚动容器（`PrismListView` / `CustomScrollView`）。
- 底部要留出 dock 的高度：用 `context.bottomInset`，不要写死数字。
- 内容顶部让开 bar：用 `context.appBarInset` / `context.contentTopPadding`。

## 5. 三态（加载 / 空 / 错误）

```dart
if (_loading && _items.isEmpty) return const JmLoading();
if (_error != null) return JmError(message: _error!, onRetry: _reload);
if (_items.isEmpty) return const JmEmpty(message: '还没有收藏');
```

- 已有数据时的「刷新中」**不要**把列表换成 Loading（会闪），只在 bar 上显示进度
  （`JmPage(loading: _refreshing)`）。
- 失败且已有数据时：保留旧数据 + `BannerHost` 提示，不要清空。

## 6. 交互约定（`surfaces.md` §Press / §State）

- 按压缩放：卡片、行、chip 用 `PressLook.ink`（状态层 + Android 上的 sparkle），
  **不许自己加 `AnimatedScale`**。
- 桌面悬停：`PressSurface` 自带 4% 覆盖，不要另外做 hover 效果。
- 选中态：**保留本身填充 + 打勾**（成组的行用 `SelectionCheck`，独立卡片用
  `SelectionBadge`）。只有「连体按钮组 / 模式切换 / 紧凑选择 chip」才用
  `Card(fillsSelection: true)` 的实心 primary。
- `primaryContainer` / `secondaryContainer` / `tertiaryContainer` **不许**当卡片、
  行、标记、导航指示器的填充色。
- 状态色（成功/警告/失败）只上文字、图标或小 chip，不染整张卡片。
- 破坏性操作在弹窗里用 `ColorScheme.destructive`（iOS systemRed），不是 `error`。
- **没有下拉刷新**：列表刷新走 app bar 的动作按钮；上拉加载更多保留（滚到底自动加载）。
- 模态：sheet 用 `ColorScheme.modalScrim`（32%），alert 用 `alertScrim`。不要模糊背景。
- 弹层尺寸属于路由，不属于内容：不要给 sheet 内容包固定宽高。

## 7. 行为不许变

`docs/jm_ui_inventory.md` §2 的每个交互都要保留：

- 数据加载时机（进页面就加载，不等转场结束）
- 分页参数、缓存键、请求顺序
- 手势（阅读器点屏切 bar、评论区展开、搜索展开态）
- 动画锚点（专辑详情的圆形揭示转场圆心来自按钮的 `RenderBox`）
- 状态闸门（起始页的 `_enteringHost` / `probing`）
- 图片解密管线（`core/image_loader.dart`、`image_unscramble.dart`、`PageCache`）
- 阅读器的 `ui.Image` 引用计数释放

**只换表现层，不动数据流与手势语义。** 需要改行为才能适配时，先停下来记录，
在交付说明里列出，不要自己决定。

## 8. 验收（每个页面都要做）

> **注意：本会话的模型不支持图像输入**，`read_image` 会报
> 「model does not declare image input」。所以验收不靠「截图人眼看」，靠
> **程序化断言 + 数值检查**。最终观感由人工在设备上确认，这一点会写进交付说明。

1. `flutter analyze <改过的文件>` 必须 `No issues found!`
2. `grep` 确认没有残留 `material` / `M3E` / `Icons.` / `InkWell` / `ElevatedButton`。
3. 写临时 widget 测试，用断言覆盖以下几条（浅色 + 深色，宽 320 / 390 各一遍）：
   - **层级可分辨**：`SurfaceLevel` 四级的 `colorOf` HCT tone 严格单调（浅色递减、
     深色递增），相邻差 ≥ 2；页面里实际用的填充色等于其所在层级的颜色。
   - **圆角**：实际 shape 的 radius 严格等于 `AppCorner` 的某个 token。
   - **对比度**：`onSurface` / `onSurfaceVariant` 对其所在填充的 WCAG 对比度
     正文 ≥ 4.5、次要文字 ≥ 3，浅深两套都要过。
   - **溢出**：`tester.takeException()` 必须为 null（RenderFlex overflow 会抛异常）。
   - **状态齐全**：空数据 / 加载中 / 出错三种状态各 pump 一次，断言各自出现预期文案。
   - **网络打桩**：测试里不许真联网，用 `createTestImage` / 1×1 PNG 常量作封面，
     或用 `test/support/fake_gateway.dart`。
4. 临时测试用完删掉。
5. 该页面对应的现有 widget 测试（`test/` 下）如果断言了 Material 组件类型，
   一并改成断言 prism 组件类型——**测试是契约，不许直接删除断言**。

## 9. 最容易崩的五个点

1. **没有 `ViewScope`** → `AppBar` / `ScaffoldBar` / `showSheet` 直接 assert 崩。
   迁移期由 `PrismHost` 提供（已接在 `main.dart`），测试里要自己包。
2. **`ListRow` 不带点击** → 必须包 `Card` / `PressSurface`。
3. **卡片里放控件**：控件必须能「吃」按压（`Switch` / `IconButton` / `PressSurface`），
   裸 `GestureDetector` 会让整张卡片跟着亮。
4. **`Theme.of` 永远不返回 null** → 忘了包主题时会静默变成紫色默认主题，别以为「能跑就对」。
5. **`Card` 里再放 `Card`** 记得两层之间会自动降一级，不要再手动指定颜色。
