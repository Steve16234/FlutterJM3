# JM UI 套件（lib/ui）

> 面向：接下来重写 12 个页面的开发者。
> 这份文档里的签名**逐字来自源码**（`lib/ui/*.dart`），复制粘贴即可用。
> 设计规范来源：`docs/prism_ui_api.md`（prism_ui v0.1.3）与 `lib/theme/prism_theme.dart`。

---

## 0. 三条铁律（先看这个）

```dart
// 1. 页面只 import 这两个 + 图标
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import '../ui/icons/icons.dart';        // AppGlyphs.search / GlyphIcon 等
```

1. **绝不 import `flutter/material.dart` / `flutter/cupertino.dart`**，也不用任何 Material 组件（`Scaffold`、`AppBar`、`ListTile`、`CircularProgressIndicator`、`Icons.*`、`InkWell`、`showDialog`、`SnackBar`、`RefreshIndicator`…全部换成 prism 的对应物）。本套件里的 6 个文件已经做到了，新增页面照做。
2. **不写死任何颜色、圆角、字号。** 颜色只从 `context.colorScheme` / `SurfaceLevel.xxx.colorOf(scheme)` 取；圆角只用 `AppCorner.*` / `AppShape.*` / `AppRadius.*`；字号只用 `AppTextStyle.xxx.of(context)`。
3. **图标只用 glyph**：`GlyphIcon(AppGlyphs.search, size: 20)`。prism 自带的 20 个在 `Glyphs`，本应用的图标集在 `lib/ui/icons/app_glyphs.dart`（`AppGlyphs.*`，复用 prism 的名字如 `AppGlyphs.arrowBack` 就是 `Glyphs.arrowBack`）。

### 运行环境（页面被谁包着）

prism 的组件依赖三样东西，`lib/theme/prism_host.dart` 的 `PrismHost` 已经全部提供（`main.dart` 里包在 App 上）：

| 环境 | 谁需要 | 缺了会怎样 |
|---|---|---|
| `ViewScope` | `AppBar` / `ScaffoldBar` / `showSheet` | **assert 崩**（`No ViewScope found`） |
| `MeasureScope` | `ListRow` / `ListHeader` / `SectionHeader` | **assert 崩** |
| `BannerHost` | `BannerHost.maybeOf(context)?.show(...)`（prism 的 SnackBar） | 提示无处可显示 |
| `UiLocalizations`（`JmUiLocalizations`） | `showSheet` / `showFloatingDialog` / 组件的返回按钮 tooltip | **assert 崩** |

写 **widget 测试**时同样要包一层：`Directionality` → `Localizations`（`JmUiLocalizations.delegate`）→ `ViewScope` + `MeasureScope` + `Theme(data: PrismTheme.of(brightness))` + `SurfaceScope(level: SurfaceLevel.page)`。参考 `PrismHost` 的 25 行实现照抄即可。

---

## 1. `lib/ui/page.dart` — `JmPage` 页面骨架

### 签名

```dart
class JmPage extends StatelessWidget {
  const JmPage({
    super.key,
    this.title,                        // String?   null = 不显示标题（阅读器 / 起始页）
    this.showBack = true,              // bool      有上级页面时显示返回按钮
    this.actions = const <Widget>[],    // List<Widget>  bar 右侧动作
    this.bottom,                       // Widget?   贴在 bar 下方（搜索框 / tab 条 / 关键词条）
    this.body,                         // Widget?   页面主体
    this.backgroundColor,              // Color?    默认 SurfaceLevel.page
    this.resizeToAvoidBottomInset,     // bool?
    this.loading,                      // ValueListenable<bool>?  bar 底部的 3dp 进度条
    this.foot,                         // Widget?   悬浮在 body 之上的底栏
  });
}
```

### 用途

一个页面 = 一条 bar + 一块 body。内部是 `PrismScaffold` + `ScaffoldBar` + `AppBar`，很薄：动作直接塞 `AppBar.actions`。

### 最小用法

```dart
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return JmPage(
      title: '设置',
      actions: <Widget>[
        AppBarActionButton(
          data: IconButtonData(
            glyph: AppGlyphs.refresh,
            tooltip: '刷新',
            onPressed: () => reload(),
          ),
        ),
      ],
      // bar 底部那条进度条；同一个 notifier 也可以给别处用
      loading: _refreshing,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          const SectionHeader(title: '外观'),
          SectionCard(children: <Widget>[
            SettingRow(title: '主题', subtitle: '跟随系统'),
          ]),
        ],
      ),
    );
  }
}
```

带搜索框的页面（搜索框是 `bottom`，不是 body 的第一行）：

```dart
JmPage(
  title: '发现',
  bottom: const Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: JmSearchField(hint: '搜索作品名 / JM 号'),
  ),
  body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [...]),
);
```

### 注意（很重要，实测踩过）

- **body 已经替你让开了 bar 的高度。** `PrismScaffold` 的 bar 浮在 body 之上，只把高度写进 `MediaQuery.padding.top`；而 `ListView(padding: …)` / `Column` 不会自动消费它。`JmPage` 已经改成显式让位（垫一层 padding + 把这段从 MediaQuery 去掉），所以：
  - body 里**不要**再自己加顶部留白；
  - 不要在 body 外面再包 `SafeArea(top: true)`。
- `bottom` 非空时，body 从 `bottom` 下面开始，同样不需要额外留白。
- `foot` 是**悬浮**的，不占 body 空间：要避免内容被盖住，自己在 body 末尾留出等高空白（或把 body 包进 `BottomInsetScope`）。
- `actions` 建议 ≤ 3 个；超了要自己收敛成 `PopupAnchor` 溢出菜单（本套件刻意不搬 FlClash 那套 870 行的 Scaffold）。
- `showBack: true` 只在 `Navigator` 真的能 pop 时才画箭头，所以根页面传默认值也不会出现「按了没反应」的返回键。

### 什么时候别用

- sheet / dialog 里：直接 `PrismScaffold`（`ScaffoldBar(isCompact: true)`）。
- 沉浸式页面（阅读器、作品详情的可折叠封面）：bar 要自己浮动，用 `PrismScaffold` + 自定义 `ScaffoldBar`。
- 带底部导航的主框架（`RootShell`）：`PrismScaffold(foot: NavigationDock(...))` 自己拼。

---

## 2. `lib/ui/states.dart` — 三态

### 签名

```dart
class JmLoading extends StatelessWidget {
  const JmLoading({super.key, this.label});
  const JmLoading.sliver({super.key, this.label});
  final String? label;
}

class JmEmpty extends StatelessWidget {
  const JmEmpty({
    super.key,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  });
  const JmEmpty.sliver({
    super.key,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class JmError extends StatelessWidget {
  const JmError({super.key, required this.message, this.onRetry});
  const JmError.sliver({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
}
```

### 用途

- `JmLoading`：prism 的整页转圈（`ActivityIndicator.page()`）+ 可选说明。
- `JmEmpty`：`NullStatus` + 本应用的插图；`actionLabel` + `onAction` 给一个引导按钮。
- `JmError`：`NullStatus`（错误配色）+ 「重试」填充按钮。

三者都会**居中填充父级高度**；高度无界时退化成按内容自适应（不崩）。

### 最小用法

```dart
// 页面 body（高度有界）
FutureBuilder<AlbumDetail>(
  future: _future,
  builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const JmLoading(label: '正在加载作品…');
    }
    if (snap.hasError) {
      return JmError(message: '加载失败：${snap.error}', onRetry: _reload);
    }
    final detail = snap.data!;
    return _content(detail);
  },
)
```

```dart
// CustomScrollView 里（sliver）
CustomScrollView(
  slivers: <Widget>[
    _header,
    if (loading)
      const JmLoading.sliver(label: '正在加载…')
    else if (items.isEmpty)
      JmEmpty.sliver(
        message: '还没有收藏',
        hint: '在作品详情页点收藏，就会出现在这里。',
        actionLabel: '去发现',
        onAction: () => openDiscover(context),
      )
    else
      SliverPrismList(itemCount: items.length, itemBuilder: ...),
  ],
)
```

```dart
// ListView 里（高度无界）→ 给一个高度，别直接塞
SizedBox(height: 240, child: JmEmpty(message: '这里还没有内容'))
```

### 什么时候别用

- 搜索无结果：用 `NullStatusSwitcher(isSearching: true)`（prism 自带「没有搜索结果」插图），不要手写 `JmEmpty`。
- 局部失败（列表尾部「加载更多」失败）：在那一格放一行可点的文字，不要整页 `JmError`。
- 已经有数据、只是正在刷新：用 `JmPage(loading: …)` 的顶部进度条，不要把内容换成 `JmLoading`（会闪屏）。

---

## 3. `lib/ui/album_card.dart` — 封面卡（最常用）

### 签名

```dart
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,     // AlbumSummary
    this.onPressed,          // VoidCallback?
    this.radius,             // double?   默认 AppCorner.lg
    this.imgHost,            // String?   图片 CDN 前缀
  });
}

class AlbumListTile extends StatelessWidget {
  const AlbumListTile({
    super.key,
    required this.album,     // AlbumSummary
    this.onPressed,
    this.subtitle,           // String?   右侧元信息（阅读量 / 更新时间）
    this.imgHost,
  });
}

/// 给整页提供图片 CDN 前缀，省掉每个卡片都传 imgHost。
class JmImageHost extends InheritedWidget {
  const JmImageHost({super.key, required this.imgHost, required super.child});
  final String imgHost;
  static String of(BuildContext context);
}
```

### 用途 / 规格

| | `AlbumCard`（网格） | `AlbumListTile`（横排） |
|---|---|---|
| 封面 | 3:4，与卡片同边（无内边距） | 3:4，宽 84，圆角 `AppCorner.md` |
| 卡片圆角 | `AppCorner.lg`（20） | `AppCorner.xl`（24，全宽通栏） |
| 文字 | 标题 2 行（`subheadline` 加粗）+ 作者 1 行（`caption1`/`onSurfaceVariant`） | 标题 2 行 + 作者 1 行 + 标签 chip + `subtitle` 1 行 |
| 标签 | — | `MetaChip`（灰底，**不是** `primaryContainer`） |
| 点击 | `Card(onPressed:)`（ink + 焦点环 + 语义齐全） | 同上 |

封面占位色 = **inset** 层级（`context.raisedSurfaceLevel.next`）。原因：亮色下 prism 的 `block` 与 `page` 是同一个颜色（都是 `surfaceContainer`），若用 block，卡片上半张会和页面糊成一片。

### 最小用法

```dart
// 网格（高度有界 —— SliverGrid / GridView）
SliverGrid(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.52,          // ← 旧页面的比例，别改，卡片内是 3:4 封面
  ),
  delegate: SliverChildBuilderDelegate(
    (context, i) => AlbumCard(
      album: items[i],
      imgHost: app.imgHost,
      onPressed: () => openAlbum(context, items[i].id),
    ),
    childCount: items.length,
  ),
)
```

```dart
// 横排列表
PrismListView(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  gap: 8,
  itemCount: results.length,
  itemBuilder: (context, i) => AlbumListTile(
    album: results[i],
    imgHost: app.imgHost,
    subtitle: '${results[i].updateAt} 更新',
    onPressed: () => openAlbum(context, results[i].id),
  ),
)
```

```dart
// 不想每个卡片都传 imgHost：页面根部包一次
JmImageHost(
  imgHost: context.watch<AppState>().imgHost,
  child: body,
)
```

### 封面管线（别自己造）

封面走 `lib/core/image_loader.dart` 的 `PageImageLoader.shared`：UA / Referer、三层缓存（解码图 / 字节 / 磁盘）、同 URL 并发合并都在里面，**不要**改成 `Image.network`。

- 管线没有 `ImageProvider`，所以 `_AlbumCover` 自己持有一个 `ui.Image` 引用，并在 `dispose` 时 `PageImageLoader.shared.release(url)` —— 和阅读器的 `_ReaderPage` 完全一致。**自己写新卡片时照抄这个 owning 模式，漏 release 那张图永远淘汰不掉。**
- 封面不做乱序还原：`ImageUnscrambler.segmentCount` 只在 `aid < scrambleId` 时返回 0，所以封面固定传 `(aid: 0, scrambleId: 1)`。
- URL 为空 / 拿不到 http 前缀 → 直接显示占位（不发请求、不崩）；下载失败 → 占位块 + 一个淡 glyph。两条分支都**不会**跳尺寸。

### 什么时候别用

- 只有文字、没有封面的条目：用 `rows.dart` 的 `NavigationRow` / `SettingRow`，别硬套 `AlbumCard`。
- 需要显示阅读进度、收藏角标、连载状态：另写变体，不要往 `AlbumCard` 里塞第四行文字（0.52 的比例会溢出）。
- 横向「推荐位」小卡（旧 `AlbumTileCompactContent`）：目前没有对应组件，需要时按同一套 token 新写一个，别改 `AlbumCard` 的比例。

---

## 4. `lib/ui/rows.dart` — 行

### 签名

```dart
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    this.glyph,              // Glyph?   左侧图标（null = 不留图标位）
    required this.title,     // String
    this.subtitle,           // String?
    this.trailing,           // Widget?  开关 / 按钮 / 值文字
    this.onPressed,          // VoidCallback?  null = 不可点但保持正常颜色
    this.danger = false,     // bool     删除类动作用 ColorScheme.destructive
  });
}

class NavigationRow extends StatelessWidget {
  const NavigationRow({
    super.key,
    this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,                    // 放在 chevron 左边的附加内容
    required this.onPressed,          // 必填：带 chevron 的行永远可点
  });
}

class ValueRow extends StatelessWidget {
  const ValueRow({super.key, required this.title, required this.value});
}
```

### 用途

- `SettingRow`：设置项。`trailing` 放 `Switch` / `Checkbox` / `IconButton` / 值文字。
- `NavigationRow`：跳转行，右侧固定 `DisclosureIndicator`（`>`）。
- `ValueRow`：只读的「标题 + 右侧值」，不可点。

**行是自适应的**：直接放页面上 → 每行是一张独立 `Card`（`AppCorner.xl`）；已经被 `SectionCard` 包进分组 → 只画按压状态层，填充和圆角交给外层那张卡。判断依据是 `context.surfaceLevel`，调用点什么都不用做，也**不要**自己写层级。

### 最小用法

```dart
// 分组里（推荐）
SectionCard(children: <Widget>[
  SettingRow(
    glyph: AppGlyphs.palette,
    title: '主题',
    subtitle: '跟随系统',
    trailing: Switch(value: isDark, onChanged: (v) => setDark(v)),
  ),
  NavigationRow(
    glyph: AppGlyphs.star,
    title: '我的收藏',
    subtitle: '共 128 部',
    trailing: const Text('新'),
    onPressed: () => openFavorites(context),
  ),
  const ValueRow(title: '当前线路', value: 'https://18comic.vip'),
])
```

```dart
// 单独一行（自己就是一张卡）
SettingRow(
  glyph: AppGlyphs.delete,
  title: '退出登录',
  danger: true,
  onPressed: () => confirmLogout(context),
)
```

### 注意

- `danger: true` 用 `ColorScheme.destructive`（iOS systemRed），**不是** `error`：`error` 表示「出错了」。
- 不可点的行（`onPressed: null`）仍然是正常颜色（prism 的 `inert`），不会变成 38% 灰。
- 行与行之间**不要**画边框；分隔线由 `SectionCard` 统一画（`Divider.colorOf`）。
- 行尾不要放「⋯」按钮，次要操作走 `ContextMenuRegion`（prism 规范）。

### 什么时候别用

- 需要两行以上说明文字：`ListRow` 的副标题排版是按两行设计的，超过请改成卡片 + 自定义排版。
- 需要左侧头像 / 封面：用 `AlbumListTile`，不要往 `ListRow.leading` 里塞图片（高度只有 56）。

---

## 5. `lib/ui/section.dart` — 分组

### 签名

```dart
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});
  final String title;
  final Widget? action;      // 右侧动作（TextButton / IconButton）
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;   // 默认 0，行的左右 16 由 ListRow 给
}

class TagWrap extends StatelessWidget {
  const TagWrap({super.key, required this.tags, this.onTagPressed});
  final List<String> tags;
  final ValueChanged<String>? onTagPressed;
}
```

### 用途

- `SectionHeader`：小节标题，直接复用 prism 的 `ListHeader`（`headline` + `onSurfaceVariant`，上 24 / 下 8）。
- `SectionCard`：把若干行包成**一张**卡（card 层级），行间自动加发丝线（`Divider.colorOf`，左右内缩 16），并把 `SurfaceScope` 往下传一级，让里面的行变成透明行。
- `TagWrap`：标签云。给了 `onTagPressed` → 可点的 `Chip`（36dp 药丸）；没给 → `MetaChip`（小号灰底）。两者都是灰底，**没有**用 `primaryContainer`。

### 最小用法

```dart
ListView(
  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
  children: <Widget>[
    const SectionHeader(title: '外观'),
    SectionCard(children: <Widget>[
      SettingRow(title: '跟随系统', trailing: Switch(value: v, onChanged: setV)),
      SettingRow(title: '纯黑模式', trailing: Switch(value: p, onChanged: setP)),
    ]),
    const SectionHeader(title: '标签', action: _moreButton),
    TagWrap(tags: detail.tags, onTagPressed: (tag) => search(tag)),
    const SizedBox(height: 16),
  ],
)
```

### 注意

- `SectionCard` 是**一次性构建全部子行**的 `Column`：行数很多（几十行）的长列表用 `ListHeader` + `generateGroup` 的 sliver 版本，不要塞进 `SectionCard`。
- `SectionHeader` 依赖 `MeasureScope`（`ListHeader` 要量字高）：页面里没问题，裸 widget 测试里要先包 `MeasureScope`。
- 一个页面里这种分组标题不要超过 4 个。

### 什么时候别用

- 只有一行：单个 `SettingRow` 自己就是一张卡，不需要 `SectionCard`。
- 需要折叠 / 手风琴：prism 没有 `ExpansionTile`，用 `SliverCollapsibleSection` 或自己做。

---

## 6. `lib/ui/search_field.dart` — 填充胶囊搜索框

### 签名

```dart
class JmSearchField extends StatefulWidget {
  const JmSearchField({
    super.key,
    this.controller,               // TextEditingController?
    this.hint = '搜索',             // String
    this.onChanged,                // ValueChanged<String>?
    this.onSubmitted,              // ValueChanged<String>?  已 trim
    this.onClear,                  // VoidCallback?          点右侧 × 时
    this.autofocus = false,        // bool
    this.leading,                  // Widget?                默认放大镜 glyph
  });
}
```

### 用途

规范里的「填充胶囊」搜索框：`AppShape.input` 去描边 + `AppRadius.full`，填充 = 当前表面的下一级；**焦点环只在键盘 / 遥控器把焦点移上来时出现**（鼠标点进来不画环）。

### 最小用法

```dart
JmSearchField(
  controller: _controller,
  hint: '搜索作品名 / JM 号',
  onChanged: (value) => setState(() => _query = value),
  onSubmitted: (value) => _search(value),        // value 已 trim
  onClear: () => setState(() { _query = ''; _results = const []; }),
)
```

放在 `JmPage.bottom` 里最省事（见第 1 节）。

### 注意

- 不传 `controller` 时组件自己建一个并负责 dispose；传了由调用方负责。
- 有内容才出现右侧清空按钮；`onClear` 只在点它时触发（用户手动删空不会触发）。
- `onSubmitted` 只在键盘回车（`TextInputAction.search`）时触发。

### 什么时候别用

- 表单输入（账号、密码、订阅链接）：用 prism 的 `TextField` + `ListRow`（裸字段 + 行标题），搜索框的胶囊形态不属于表单。
- 「收起态迷你胶囊 + 展开动画」那种 bar 级搜索：需要父级控制宽度与展开状态，自己写（旧 `DiscoverSearchBar` 的逻辑），别用这个组件硬拼。

---

## 7. 现成配方

### 7.1 四态列表页

```dart
class PagedAlbumsPage extends StatelessWidget {
  const PagedAlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return JmPage(
      title: '最新更新',
      loading: _refreshing,
      body: _items.isEmpty
          ? (_loading
                ? const JmLoading()
                : _error != null
                ? JmError(message: _error!, onRetry: _reload)
                : const JmEmpty(message: '没有内容'))
          : CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.52,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => AlbumCard(
                        album: _items[i],
                        imgHost: _imgHost,
                        onPressed: () => _open(_items[i]),
                      ),
                      childCount: _items.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
```

### 7.2 设置页

```dart
JmPage(
  title: '设置',
  body: ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    children: <Widget>[
      const SectionHeader(title: '外观'),
      SectionCard(children: <Widget>[
        SettingRow(
          glyph: AppGlyphs.palette,
          title: '主题',
          subtitle: _themeLabel,
          trailing: Switch(value: _dark, onChanged: _setDark),
        ),
      ]),
      const SectionHeader(title: '缓存'),
      SectionCard(children: <Widget>[
        SettingRow(
          glyph: AppGlyphs.broom,
          title: '页图缓存',
          subtitle: _usageLabel,
          trailing: _busy ? const ActivityIndicator(size: 20) : const Text('清理'),
          onPressed: _busy ? null : _clearCache,
        ),
      ]),
      const SectionHeader(title: '关于'),
      SectionCard(children: <Widget>[
        ValueRow(title: '图片线路', value: _imgHost),
        const ValueRow(title: '渲染引擎', value: 'Flutter 3.50 / prism_ui'),
      ]),
    ],
  ),
)
```

### 7.3 提示（替代 SnackBar）

```dart
BannerHost.maybeOf(context)?.show('已加入收藏', level: BannerLevel.success);
BannerHost.maybeOf(context)?.show('连接失败', level: BannerLevel.error);
```

---

## 8. 交付前自查（逐条对）

- [ ] 没有 `import 'package:flutter/material.dart'`，没有 Material 组件 / `Icons.*`。
- [ ] 页面骨架是 `JmPage`（或明确写了为什么不用）。
- [ ] 每个异步区都有三态：`JmLoading` / `JmEmpty` / `JmError`。
- [ ] 封面用 `AlbumCard` / `AlbumListTile`，没有新写 `Image.network`。
- [ ] 列表行没包 `GestureDetector`（点击由 `Card` / `PressSurface` 提供）。
- [ ] 没有裸颜色（`Color(0x...)` / `Colors.black`）、裸圆角（`BorderRadius.circular(12)`）、裸字号（`fontSize: 14`）。
- [ ] 分隔线只用 `Divider.colorOf`（通常由 `SectionCard` 代劳）。
- [ ] 320 宽也不溢出（`flutter test` 里跑一遍窄宽度）。
- [ ] `flutter analyze lib` 干净。

---

## 9. 已知边界（客观上只能人眼看设备的地方）

程序化断言已经覆盖了：表面层级 tone 单调 + 相邻差 ≥ 2、组件实际填充色 = 所处层级色、圆角全是 token、嵌套圆角 = 外层 − 内边距、WCAG 对比度（正文 ≥ 4.5 / 次要 ≥ 3.0）、320/390 两种宽度 × 明暗两模式无溢出、body 不被浮动 bar 盖住、行/卡片点击真的接上了、源码无 Material 残留。

剩下这些**只能上真机看**：

1. **封面的真实观感**：图片缩放质量（`FilterQuality.medium` 的取舍）、异形比例封面（非 3:4）裁切位置、低分辨率图放大后的噪点。
2. **动效手感**：按压 ink 的 150ms 延迟、`Card` 的填充缓动、`AnimatedSwitcher` 的 200ms 淡入、`JmLoading` 转圈节奏；这些是时间轴上的东西，截图和断言都看不出来。
3. **滚动时 bar 的观感**：prism 的 `FloatingHeader` 在内容滚到 bar 下面时的渐变是否够干净（`JmPage` 已经把首屏内容让开了，但滚动中的穿透效果需要真机确认）。
4. **中文字体**：本机测试加载的是 `simhei.ttf` 替身；设备上的系统字体（MiSans/思源）字重与行高差异会影响 2 行标题的截断点。
5. **深色下 inset 占位偏亮**：这是 prism 层级模型的必然结果（暗色越往上越亮），放在真实封面旁边是否顺眼需要人眼判断；如果嫌亮，把 `_AlbumCover` 的占位改成 card 层级即可（一处改动）。
