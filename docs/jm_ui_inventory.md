# FlutterJM UI 层改造清单（Inventory for UI Rewrite）

> 目标：把 `lib/` 现有 UI（`package:material_ui/material_ui.dart` ≈ `flutter/material` + `package:material_3_expressive`）整体重写成另一套设计系统之前，先把「有什么、谁依赖谁、动了会坏什么」精确记录一份。
>
> 本文档只做清点与风险标注，**不含任何代码改动**。源文件保持只读。

---

## 0. 统计口径与环境

| 项 | 值 |
|---|---|
| 统计对象 | `Q:\Androidproject\lib\` 下全部 `.dart` 文件 |
| 文件数 | **33**（1 main + 8 core + 2 data + 12 screens + 1 state + 2 theme + 7 widgets） |
| 总行数 | **7841** 行 |
| 行数统计方式 | `@(Get-Content -LiteralPath <file>).Count`（含空行与注释，与 IDE 行号一致） |
| Dart SDK | `^3.14.0` |
| UI 依赖 | `material_ui: ^1.11.0`（= `flutter/material` 的等价分发）、`material_3_expressive: ^1.2.1` |
| 状态管理 | `provider: ^6.1.5+1`（仅 `ChangeNotifierProvider` + `Selector` + `context.read/watch/select`） |
| 其它运行时依赖 | `http`、`pointycastle`、`crypto`、`path_provider`（**均不在 UI 层**，见 §5） |

### 0.1 与任务书数字的差异（重要，先对齐）

| 任务书说法 | 实测 | 差异说明 |
|---|---|---|
| `lib/screens/` 13 个页面 | **12 个文件 / 15 个页面级 widget 类**（14 public + 1 private） | 「搜索页」已不再单独成页，被折叠进 `HomeScreen` 内的 `DiscoverSearchPanel`（见 `home_screen.dart:17-19`、`search_panel.dart:12-14` 注释）。13 应为旧版口径。逐页对照见 §2.0 |
| `lib/widgets/` 9 个组件 | **7 个文件 / 14 个 public 组件 + 5 个 private 组件 + 2 个格式化函数 + 1 个转场函数** | 组件个数（19）多于文件数（7），因为 `common.dart`/`album_card.dart`/`openable_album.dart` 各含 3~5 个类 |

### 0.2 目标设计系统：`prism_ui`（已确认，且改造已在进行中）

| 事实 | 证据 |
|---|---|
| 目标系统 = `packages/prism_ui`（v0.1.3，FlClash 的 iOS 风格设计系统：液态玻璃 / 流体动效 / 单色种子派生整套配色，`lib/prism_ui.dart` 导出 **98** 个 barrel 文件） | `pubspec.yaml` → `prism_ui: {path: packages/prism_ui}` |
| 依赖已解析 | `.dart_tool/package_config.json` → `prism_ui: ../packages/prism_ui`（01:26:38 生成） |
| 迁移层已落地 | **`lib/theme/prism_theme.dart`（59 行，01:26:56 新建）**：`abstract final class PrismTheme`（`seed = Color(0xFFE53935)`、`ColorStyle.vivid`、`light()/dark()/of(Brightness)`、`seededColorScheme(...)`、`scheme.elevated`）+ `class PrismBridge({required Brightness brightness, required Widget child})` = `Theme(PrismTheme.of(brightness)) + SurfaceScope(level: SurfaceLevel.page)`；注释明确「已经改成 `PrismApp`，`PrismBridge` 只在未迁移完的角落临时用」 |
| 旧依赖仍在 | `material_ui: ^1.11.0`、`material_3_expressive: ^1.2.1` 尚未从 pubspec 移除 |

> ⚠️ **快照声明**：本文档的行数/频次来自 `lib/` 在 **2026-11-21 01:24–01:30** 的只读扫描。此后 `lib/` 正被并发改造（`theme/prism_theme.dart` 即扫描期间出现），因此：
> - §1–§6 描述的是**改造前的基线**（用于对照与验收），不是最新的 `lib/`；
> - 已确认新 UI **不再以 `material_3_expressive` 为规范源**，`M3E*` 10 个组件族（§3.3）属于**待删除面**，`prism_theme.dart` 是新的 token 源；
> - §7 的 B0 待确认项 1（「目标系统是谁」）现已作答：**prism_ui**。

---

## 1. 全量文件清单（路径 / 行数 / 类别 / 对外暴露类型 / 关键构造参数）

### 1.1 入口

| # | 路径 | 行数 | 类别 | public 类型 | 关键构造参数 |
|---|---|---|---|---|---|
| 1 | `lib/main.dart` | 54 | 入口 | `FlutterJMApp` | `const FlutterJMApp({super.key})` |

`FlutterJMApp` 结构（改造时唯一必须保留的骨架）：
`ChangeNotifierProvider<AppState>` → `Selector<AppState, ThemeMode>` → `MaterialApp(title:'JM', theme/darkTheme: AppTheme.light/dark(null), themeMode, builder: M3EBridge(child), home: StartScreen())`。
`main()` 里还有 `unawaited(PageCache.instance.warmUp())`（`main.dart:15`）。

### 1.2 screens（12 文件 / 15 页面类）

| # | 路径 | 行数 | 页面类（public） | 关键构造参数 |
|---|---|---|---|---|
| 2 | `lib/screens/root_shell.dart` | 86 | `RootShell` | `const RootShell({super.key})` |
| 3 | `lib/screens/start_screen.dart` | 357 | `StartScreen` | `const StartScreen({super.key})` |
| 4 | `lib/screens/home_screen.dart` | 288 | `HomeScreen` | `const HomeScreen({super.key})` |
| 5 | `lib/screens/library_screen.dart` | 248 | `LibraryScreen` | `const LibraryScreen({super.key})` |
| 6 | `lib/screens/settings_screen.dart` | 212 | `SettingsScreen` | `const SettingsScreen({super.key})` |
| 7 | `lib/screens/account_screen.dart` | 350 | `AccountScreen` | `const AccountScreen({super.key})` |
| 8 | `lib/screens/album_list_screen.dart` | 278 | `PagedAlbumScreen`、`LatestListScreen`、`PromoteListScreen`（+ `typedef PageLoader`） | `PagedAlbumScreen({required String title, required PageLoader loader, bool asGrid = false, String? subtitle})`；`LatestListScreen({super.key})`；`PromoteListScreen({required String id, required String title})` |
| 9 | `lib/screens/album_detail_screen.dart` | 543 | `AlbumDetailScreen` | `const AlbumDetailScreen({super.key, required String albumId})` |
| 10 | `lib/screens/reader_screen.dart` | 389 | `ReaderScreen` | `const ReaderScreen({super.key, required String albumId, required String title})` |
| 11 | `lib/screens/week_screen.dart` | 169 | `WeekScreen`（+ private `_WeekDetailScreen`） | `const WeekScreen({super.key})`；private: `_WeekDetailScreen({required WeekIssue issue})` |
| 12 | `lib/screens/account_albums_screen.dart` | 151 | `AccountAlbumsScreen` | `{required String title, required Future<AccountAlbumPage> Function(int page) loader, String emptyMessage = '这里还没有内容'}` |
| 13 | `lib/screens/notifications_screen.dart` | 157 | `NotificationsScreen` | `const NotificationsScreen({super.key})` |

页面文件内的 private 子组件（改造时随页面一起重写，不对外）：
`start_screen`: `_LineButton`、`_FastestBadge`、`_LineSkeleton`、`_ErrorState`；
`home_screen`: `_HomeData`（数据聚合体）；
`library_screen`: `_ActionCard`；
`album_detail_screen`: `_Stat`、`_ScaffoldedLoading`、`_WatchButton`、`_RadialRevealFromButton`、`_CircleRevealClipper`；
`reader_screen`: `_ReaderPage`；
`album_list_screen`: `_PagedAlbumScreenState`（含全部翻页逻辑）。

### 1.3 widgets（7 文件 / 14 public）

| # | 路径 | 行数 | public 类型 | 关键构造参数 |
|---|---|---|---|---|
| 14 | `lib/widgets/common.dart` | 244 | `CoverImage`、`LoadingView`、`ErrorView`、`EmptyView`、`SectionHeader`；函数 `relativeTime(int)`、`compactNumber(int)` | `CoverImage({required String url, BoxFit fit = BoxFit.cover, double aspectRatio = 3/4, BorderRadius? borderRadius})`；`LoadingView({String? message})`；`ErrorView({required String message, VoidCallback? onRetry})`；`EmptyView({required String message})`；`SectionHeader({required String title, VoidCallback? onMore, String moreLabel = '更多'})` |
| 15 | `lib/widgets/album_card.dart` | 196 | `AlbumCardContent`、`AlbumTileCompactContent`、`AlbumListTileContent` | 三者均 `{required AlbumSummary album, required String imgHost}`（**纯内容，无卡片外壳**） |
| 16 | `lib/widgets/openable_album.dart` | 87 | `OpenableAlbumCard`、`OpenableAlbumTileCompact`、`OpenableAlbumListTile` | `OpenableAlbumCard({required album, required imgHost})`；`OpenableAlbumTileCompact({..., double width = 124})`；`OpenableAlbumListTile({..., })` |
| 17 | `lib/widgets/album_open_transition.dart` | 46 | `openAlbumPreviewFromCenter`（函数） | `Future<void> openAlbumPreviewFromCenter(BuildContext context, {required String albumId, GlobalKey? originKey})` |
| 18 | `lib/widgets/discover_search_bar.dart` | 240 | `DiscoverSearchBar` | `{required TextEditingController controller, required bool expanded, required ValueChanged<bool> onExpandedChanged, required ValueChanged<String> onSubmitted, required VoidCallback onOpenWeek}`；静态常量 `compactWidth = 148`、`barHeight = 48` |
| 19 | `lib/widgets/search_panel.dart` | 289 | `DiscoverSearchPanel` | `{required String? query, required int searchNonce, ValueChanged<String>? onKeywordSelected}` |
| 20 | `lib/widgets/comment_section.dart` | 645 | `CommentSection` | `{required String albumId, int totalHint = 0}` |

widgets 文件内 private：`album_card.dart::_Tag`、`comment_section.dart::_CommentComposer / _CommentTile / _Avatar / _LevelBadge`。

### 1.4 theme（基线 2 文件 + 扫描期间新增 1 文件）

| # | 路径 | 行数 | public 类型 | 关键构造参数 / 说明 |
|---|---|---|---|---|
| 21 | `lib/theme/app_theme.dart` | 77 | `AppTheme`（`const AppTheme._()`，纯静态） | `static const Color seed = Color(0xFFE53935)`；`static ThemeData light(ColorScheme?)` / `dark(ColorScheme?)`；**两份 ThemeData 静态缓存**（`_light`/`_dark`），传 null 时返回同一实例 |
| 22 | `lib/theme/m3e_bridge.dart` | 28 | `M3EBridge` | `{required Widget child}`；内部 `M3EThemeData.fromMaterial(ThemeData)` + 以 `ThemeData` identity 做静态缓存（`_source`/`_data`） |
| 22b | `lib/theme/prism_theme.dart` | 59（扫描时新建，仍在变动） | `PrismTheme`（`abstract final`）、`PrismBridge` | `PrismBridge({required Brightness brightness, required Widget child})`；`PrismTheme.seed`、`.style`（`ColorStyle.vivid`）、`.light()`/`.dark()`/`.of(Brightness)`。**这是新设计系统的 token 源**（见 §0.2） |

`AppTheme._build()` 配置的全部 Material 主题项（改造时要么等价迁移、要么整段废弃）：
`colorScheme`、`useMaterial3: true`、`pageTransitionsTheme`（仅 Android = `PredictiveBackPageTransitionsBuilder()`）、`appBarTheme`（centerTitle:false, scrolledUnderElevation:3, title 22/w500）、`cardTheme`（elevation 0, radius 16, `surfaceContainerLow`）、`chipTheme`（radius 8, side outlineVariant）、`navigationBarTheme`（**当前无实际消费者，见 §3.5**）、`snackBarTheme`（floating, radius 12）、`listTileTheme`（radius 12）。

### 1.5 state（1 文件）

| # | 路径 | 行数 | public 类型 | 关键构造参数 |
|---|---|---|---|---|
| 23 | `lib/state/app_state.dart` | 307 | `AppState extends ChangeNotifier`、`extension AppStateContext on BuildContext`（`context.app`） | `AppState({GatewayClient? client, SettingsStore? settings})`；`static const int lineCount = 4`；字段 `client`、`settings`、`late final chapters` |

对外 API（UI 层实际消费的全部成员）：

| 成员 | 类型 | 谁在用 |
|---|---|---|
| `themeMode` | `ThemeMode` getter | main（Selector）、settings |
| `ready` | `bool` | home、start |
| `error` | `String?` | home、start |
| `loggedIn` / `username` / `userId` / `avatarUrl` | getter | root_shell、account、album_detail、comment_section、reader |
| `lines` / `probes` / `probing` / `selectedHost` / `fastestHost` | getter | start |
| `searchHistory` | `List<String>` | search_panel |
| `imgHost` / `baseUrl` | getter | home、library、week、album_list、album_detail、account_albums、comment_section、settings |
| `refreshLines()` | `Future<void>` | start（postFrame + 重测速按钮 + 重试） |
| `selectLine(String)` | `Future<void>` | start |
| `bootstrap()` | `Future<void>` | home（ErrorView onRetry） |
| `switchHost(String)` | `Future<void>` | settings |
| `login({username, password})` / `logout({remote})` | `Future<void>` | account |
| `setThemeMode(ThemeMode)` | `void` | settings |
| `addSearchHistory(String)` / `clearSearchHistory()` | `void` | home、search_panel |
| `chapters` | `ChapterCache` | settings（clear）、reader（cached/load） |
| `restoreSettings()` | `Future<void>` | main |

### 1.6 data（2 文件，非 UI，禁止改）

| # | 路径 | 行数 | public 类型 |
|---|---|---|---|
| 24 | `lib/data/models.dart` | 548 | `Category`、`SubCategory`、`AlbumSummary`(+`coverUrl(imgHost)`)、`PromoteSection`、`AlbumDetail`、`ComicPage`、`ComicRead`、`PagedAlbums`(+`hasMore`)、`WeekIssue`、`Comment`(+`displayName`/`avatarUrl`/`isReply`/`isSpoiler`)、`PagedComments`、`CommentSendResult`、`VideoItem`、函数 `htmlToPlainText(String)` |
| 25 | `lib/data/account_models.dart` | 87 | `FavoriteFolder`、`AccountAlbumPage`(+`hasMore`)、`AccountNotification` |

### 1.7 core（8 文件，非 UI，禁止改）

| # | 路径 | 行数 | 类别 | public 类型 / 能力 |
|---|---|---|---|---|
| 26 | `lib/core/gateway_client.dart` | 840 | 网络 | `GatewayClient({http.Client? client})`、`LineProbe`、`GatewayException`、`AuthSession`；约 35 个业务端点 |
| 27 | `lib/core/page_cache.dart` | 370 | 缓存 | `PageCache`（L1 图片 / L2 字节 / L3 磁盘）、`CacheUsage`、`static PageCache.instance` |
| 28 | `lib/core/chapter_cache.dart` | 61 | 缓存 | `ChapterCache({required Future<Map<String,dynamic>> Function(String) fetch, Duration ttl = 15min, int maxEntries = 12})` |
| 29 | `lib/core/image_loader.dart` | 143 | 图片管线 | `PageImageLoader({http.Client?, PageCache?})`、`static PageImageLoader.shared` |
| 30 | `lib/core/image_unscramble.dart` | 114 | 图片管线 | `ImageUnscrambler`（全静态：`segmentCount` / `pageNumberOf` / `fileNameOf` / `unscramble`） |
| 31 | `lib/core/crypto_utils.dart` | 35 | 加密 | `md5Hex(String)`、`aesEcbDecryptBase64(String, String)` |
| 32 | `lib/core/settings_store.dart` | 188 | 持久化 | `AppSettings`（+`copyWith`/`==`/`hashCode`/`hasSession`）、`SettingsStore({Directory? directory})` |
| 33 | `lib/core/comic_query.dart` | 14 | 工具 | `albumIdFromQuery(String) → String?`（`1488098` / `JM1488098` / `jm 1488098` / `#1488098`） |

---

## 2. 逐页说明（13 → 实际 15 个页面类）

### 2.0 页面映射表（任务书「13 页」↔ 代码）

| 任务书序号 | 页面 | 文件 | 页面类 | 说明 |
|---|---|---|---|---|
| 1 | 起始页/选线路 | `start_screen.dart` | `StartScreen` | App 入口 |
| 2 | 主框架（底栏） | `root_shell.dart` | `RootShell` | 4 页签容器 |
| 3 | 发现（首页） | `home_screen.dart` | `HomeScreen` | 含内嵌搜索面板 |
| 4 | 书库（分类） | `library_screen.dart` | `LibraryScreen` | |
| 5 | 我的/登录 | `account_screen.dart` | `AccountScreen` | 未登录=表单，已登录=资料 |
| 6 | 设置 | `settings_screen.dart` | `SettingsScreen` | |
| 7 | 作品详情 | `album_detail_screen.dart` | `AlbumDetailScreen` | |
| 8 | 阅读器 | `reader_screen.dart` | `ReaderScreen` | |
| 9 | 每周必看（期数列表） | `week_screen.dart` | `WeekScreen` | |
| 10 | 每周必看（某期榜单） | `week_screen.dart` | `_WeekDetailScreen` | **private**，独立一屏 |
| 11 | 我的收藏/历史/关注 | `account_albums_screen.dart` | `AccountAlbumsScreen` | 一个页面三种数据源 |
| 12 | 站内通知 | `notifications_screen.dart` | `NotificationsScreen` | |
| 13 | 通用分页列表 | `album_list_screen.dart` | `PagedAlbumScreen` | 泛型骨架（下方 2 个是薄壳） |
| — | 最新更新列表 | `album_list_screen.dart` | `LatestListScreen` | `PagedAlbumScreen` 的固定 loader 薄壳 |
| — | 推荐板块更多 | `album_list_screen.dart` | `PromoteListScreen` | 同上 |
| （已消失） | 搜索页 | — | — | 已折叠进 `HomeScreen` 的 `DiscoverSearchPanel` |

---

### 2.1 `StartScreen` — 起始页 / 四线路测速（357 行）

| 维度 | 内容 |
|---|---|
| 职责 | 拉线路清单 → 并发测速 4 条线路 → 标注最快 → 选中后 `pushReplacement` 进 `RootShell` |
| 数据来源 | `context.read<AppState>().refreshLines()`（`initState` 的 `addPostFrameCallback`，`:22-24`）、`app.lines`、`app.probes`、`app.probing`、`app.fastestHost`、`app.error`、`app.ready`、`app.selectLine(host)`；`LineProbe`（`gateway_client.dart:26-51`，`pending`/`ok`/`latencyMs`/`kbPerSecond`/`error`） |
| 结构 | `Scaffold` → `SafeArea` → `Column`：①头部 `Padding(24,32,24,8)` 内 `Text('选择线路', headlineMedium)` + 状态副标题；②`Expanded` 内三态：`_ErrorState`（仅 `error != null && lines.isEmpty`）/ `ListView.separated`（`app.lines` 为空时用占位 `AppState.lineCount` = 4 条 `_LineSkeleton`）/ `_LineButton` 列表；③底部 `M3EButton`（图标 `Icons.speed` 或 18×18 转圈，label「测速中…／重新测速」） |
| 交互 | 点线路卡片进入（`_enter`：`_enteringHost` 置位 → `selectLine` → 失败则复位 → 成功 `pushReplacement`）；点「重新测速」`refreshLines`；进入中其它卡片 `onTap: null`（`blocked`） |
| 状态 | ①`probing` 全局测速中；②单线路 `pending`（转圈）/ `ok`（`123 ms · 456 KB/s`）/ `error`（红字 + `error_outline`）；③`lines.isEmpty` → 4 条骨架；④`error && lines.isEmpty` → 整页错误态；⑤`_enteringHost` 非空 → 该卡「正在进入…」，其它禁用 |
| 动画 / 自绘 | `AnimatedContainer`(320ms, easeOutCubic) 卡片底色/边框在「最快/失败/普通」间插值（`:170-180`）；`AnimatedSwitcher`(220ms) 状态文本；最快徽标 `_FastestBadge`（自绘 `Container` 半径 999）；`CircleAvatar` 内 `Icons.bolt` 或序号 |
| 语义色 | `primaryContainer`/`primary`（最快）、`surfaceContainerLow`/`surfaceContainerHigh`/`outlineVariant`（普通/失败）、`error`、`onSurfaceVariant`、`onPrimary` |
| 内部依赖 | `common.dart` 未用；直接用 `material_ui` + `M3EButton` |
| 改造注意 | 这是唯一用 `pushReplacement` 的地方；`app.ready` 是唯一放行信号；`refreshLines` 内部会 `notifyListeners` 每完成一条就刷一次 → 新 UI 必须保持「渐进更新」而不是等全部完成 |

### 2.2 `RootShell` — 主框架 / 底部导航（86 行）

| 维度 | 内容 |
|---|---|
| 职责 | 4 个页签（发现/书库/我的·登录/设置）+ 懒构建 + 状态保活 |
| 数据来源 | `context.select<AppState, bool>((app) => app.loggedIn)`（仅此一项，`:46`） |
| 结构 | `Scaffold(body: IndexedStack(index: _index, children: 已构建页 or SizedBox.shrink), bottomNavigationBar: M3ENavigationBar(...))`；`_pages = [HomeScreen(), LibraryScreen(), AccountScreen(), SettingsScreen()]`（`static const`） |
| 交互 | `onDestinationSelected: _select`；重复点当前页直接 return；首次进入某页才把 `_built[i] = true` |
| 状态 | 仅 `_index` 与 `_built[4]`；第三页图标/文案随登录态切换（`Icons.person`/`Icons.login_outlined`，`'我的'`/`'登录'`） |
| 动画 | 全部来自 `M3ENavigationBar` 自身（选中胶囊弹簧 + 触觉）；本地无动画代码 |
| 改造注意 | **不要换回 `IndexedStack` 全量构建**（`:30-33` 注释：一次性发 3 个首页请求 + 书库请求 + 设置页缓存扫描，push 转场掉帧）；`HomeScreen`/`LibraryScreen` 用 `AutomaticKeepAliveClientMixin`，页签切换不能丢状态；`test/account_tab_test.dart:38,76` 断言四个 label 文案 |

### 2.3 `HomeScreen` — 发现页（288 行）

| 维度 | 内容 |
|---|---|
| 职责 | 顶部搜索栏（可展开）+ 推荐板块横滑 + 最新更新网格 + 连载更新网格；展开时内容区切成搜索面板 |
| 数据来源 | `_load()`：`app.client.ensureReady()` → `Future.wait([client.promote(), client.latest(), client.serialization()])`（`:91-112`）→ `_HomeData{sections: List<PromoteSection>, latest: List<AlbumSummary>, serialization: PagedAlbums}`；`app.imgHost`；`app.ready`/`app.error`；`app.addSearchHistory`；`albumIdFromQuery`（`core/comic_query.dart`） |
| 结构 | `Scaffold(appBar: M3EAppBar.top(automaticallyImplyLeading:false, title: DiscoverSearchBar(key: _searchBarKey, ...)), body: AnimatedSwitcher(Durations.short4, child: _searchExpanded ? DiscoverSearchPanel : KeyedSubtree('home-feed', ...)))`；feed 内 `RefreshIndicator` → `CustomScrollView` slivers：每个 `PromoteSection` 一个 `SliverToBoxAdapter`（`SectionHeader` + 高 210 的横向 `ListView.separated` 装 `OpenableAlbumTileCompact`）、`'最新更新'` + `SliverGrid`(190/0.52, `OpenableAlbumCard`)、`'连载更新'` + 同规格 `SliverGrid`、尾部 `SizedBox(24)` |
| 交互 | ①点搜索框 → 展开；失焦 → 收起（由 `DiscoverSearchBar` 内部触发）；②提交搜索：若是作品号 → `addSearchHistory` + `openAlbumPreviewFromCenter(originKey: _searchBarKey)`，**下一帧**再收起搜索（`:74-83`，注释明确「顺序很重要」）；否则 `_searchQuery = kw; _searchNonce++`；③`SectionHeader.onMore` → `LatestListScreen` / `PromoteListScreen`；④AppBar 右侧 `Icons.leaderboard_outlined` → `WeekScreen`；⑤下拉刷新 `_refresh()`；⑥错误重试 → `app.bootstrap`（连接态错误）或 `_refresh`（数据错误） |
| 状态 | `ConnectionState.waiting` → `LoadingView('正在连接线路…')`；`snapshot.hasError` → `ErrorView(retry=_refresh)`；`!app.ready && app.error != null` → `ErrorView(retry=app.bootstrap)`；空板块（`section.items.isEmpty`）直接跳过；`serialization.items.isEmpty` 跳过整段 |
| 动画 | AppBar→搜索面板 用 `AnimatedSwitcher`(short4, easeOut/easeIn)；搜索栏自身伸缩动画在 `DiscoverSearchBar`；卡片打开动画在 `M3ECard` |
| 改造注意 | 搜索展开是 **父级状态**（`_searchExpanded`/`_searchQuery`/`_searchNonce`），`DiscoverSearchBar` 只是受控组件；JM 号直达与「搜索」是两条不同路径，不能合并；`_searchNonce` 用于「同一个词再搜一次」；`AutomaticKeepAliveClientMixin.wantKeepAlive = true` |

### 2.4 `LibraryScreen` — 书库 / 分类（248 行）

| 维度 | 内容 |
|---|---|
| 职责 | 快捷入口（每周必看 / 随机推荐）+ 两级分类浏览 |
| 数据来源 | `_loadCategories()` → `client.categories()` → `List<Category>`（`:32-39`）；跳转 loader 里用 `client.categoriesFilter({page, category})`、`client.randomRecommend()` |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText:'书库'), body: FutureBuilder<List<Category>>)` → `RefreshIndicator` → `ListView`：`_quickActions()`（两个 `Card(color: primaryContainer)` + `InkWell`）、每个分类一个 `ExpansionTile`（`leading: CircleAvatar(首字 via characters.first)`、`subtitle: '${compactNumber(totalAlbums)} 部'`、`shape/collapsedShape: Border()` 去分割线、children = `Wrap` 装 `M3EChip(type: suggestion)` 子分类 + `FilledButton.tonalIcon('浏览全部')`） |
| 交互 | 点快捷卡 → `WeekScreen` / `PagedAlbumScreen('随机推荐')`；点子分类 chip → `PagedAlbumScreen`(loader=`categoriesFilter(category: sub.id)`)；点「浏览全部」→ 同上但用 `category.id`；下拉刷新重建 future；错误重试重建 future；分类为空 → `EmptyView('没有分类数据')` |
| 状态 | waiting → `LoadingView()`；hasError → `ErrorView`；空分类 → `EmptyView`；正常展开/收起由 `ExpansionTile` 自带 |
| 动画 | 全部来自 `ExpansionTile` / `M3EChip` / `RefreshIndicator`，本地无自定义 |
| 改造注意 | `ExpansionTile` 是 Material 独有的展开语义（新设计系统若没有手风琴组件需自建）；`shape: const Border()` 是为了抹掉 M3 默认的形状渐变，换成新皮肤时要重新确认 |

### 2.5 `SettingsScreen` — 设置（212 行）

| 维度 | 内容 |
|---|---|
| 职责 | 主题模式、线路切换、缓存统计/清理、关于信息 |
| 数据来源 | `app.themeMode`/`app.setThemeMode`；`app.baseUrl`；`app.client.hosts`（`gateway_client.dart:147`）；`app.switchHost(host)`；`PageCache.instance.usage()`（`:28`）、`PageCache.instance.clear()`（`:59`）；`app.chapters.clear()`（`:60`）；`app.imgHost` |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText:'设置'), body: ListView)`：`SectionHeader('外观')` + `M3ESegmentedButton<ThemeMode>`(3 段：跟随系统/浅色/深色, 带 icon)；`SectionHeader('线路')` + `ListTile('当前线路')` + `Wrap` 装 `M3EChip(type: filter, selected: isCurrent)`；`SectionHeader('缓存')` + `ListTile('页图缓存', subtitle = 磁盘/内存统计, trailing = 转圈 or M3EButton(text,'清理'))` + 说明文字；`SectionHeader('关于')` + `ListTile(imgHost / '渲染引擎' / '内容声明')` |
| 交互 | 切主题（立即持久化）；点线路 chip（`switchHost` → SnackBar `已切换到 <host>`）；点缓存行刷新统计；点「清理」→ `showDialog<bool>`(`AlertDialog`，取消=`M3EButton(style: text)`、确认=`M3EButton(child:)`) → 清缓存 → SnackBar `缓存已清理` |
| 状态 | `_usage == null` → `'统计中…'`；`totalBytes == 0` → `'暂无缓存'`；`_busy` → trailing 转圈且行不可点 |
| 动画 | 无本地动画（`M3ESegmentedButton` 自带选中动画） |
| 改造注意 | ①`_clearCache` 必须**同时**清 `PageCache` 与 `app.chapters`，只清一个会导致阅读器拿旧章节列表但图片全丢；②`settings_screen.dart:46` 用 `child:` 而非 `label:` 构造 `M3EButton`（全项目仅此一处，M3E 同时接受两者，改造时统一）；③`test/settings_cache_test.dart:31,52` 用 `find.widgetWithText(FilledButton,'清理')` / `(TextButton,'取消')` 断言 —— 说明 M3EButton 内部渲染为 Material 按钮，换设计系统后此断言必崩 |

### 2.6 `AccountScreen` — 我的 / 登录（350 行）

| 维度 | 内容 |
|---|---|
| 职责 | 未登录 = 内嵌登录表单；已登录 = 资料卡 + 四个二级入口 + 退出 |
| 数据来源 | `app.loggedIn`、`app.username`、`app.userId`、`app.avatarUrl`、`app.login({username,password})`、`app.logout()`；列表页 loader：`app.client.favorites(page)` / `watchList(page)` / `trackingList(page)`（返回 `AccountAlbumPage`） |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText: loggedIn ? '我的' : '登录'), body: loggedIn ? _buildProfile : _buildForm)`；表单 = `ListView`（大 `Icons.account_circle` + 标题 + 说明 + 两个 `TextField`(`OutlineInputBorder`, `prefixIcon`, 密码带 `suffixIcon` 眼睛 `IconButton`) + 错误行 + `M3EButton('登录')` + 脚注）；资料 = `ListView`（头像 `ClipOval`+`Image.network` 64 或 `CircleAvatar` 回退 + 昵称 + `UID n` + `Divider` + 4×`ListTile`（收藏/历史/关注/通知）+ `Divider` + `M3EButton('退出登录')` + 脚注） |
| 交互 | 键盘 `next`/`done` 流转焦点（`_passwordFocus`）；密码显隐；提交登录（`_busy` 期间禁用 + 按钮内转圈 + `FocusScope.unfocus()`）；退出 → `showDialog<bool>` + `AlertDialog` → `app.logout()` → SnackBar；四个 `ListTile` → `AccountAlbumsScreen` / `NotificationsScreen` |
| 状态 | `_busy`（禁用输入 + 按钮转圈）；`_error`（红色行内错误）；`_obscure`；`loggedIn` 两套整页布局；登录态由服务端 401 异步清空（`AppState._onAuthExpired`）→ 页面自动切回表单 |
| 动画 | 无本地动画 |
| 改造注意 | 底栏文案/图标随登录态变化（`root_shell.dart:72-76`），login 成功后 `notifyListeners` 会同时刷新 `RootShell` 与 `AccountScreen`；`test/account_tab_test.dart` 断言「禁漫账号」「账号 / 邮箱」「密码」「UID 42」「M3EButton '退出登录'」 |

### 2.7 `PagedAlbumScreen` / `LatestListScreen` / `PromoteListScreen` — 通用分页列表（278 行）

| 维度 | 内容 |
|---|---|
| 职责 | 一个泛型骨架复用 4 种数据源：最新更新、推荐更多、分类筛选、随机推荐 |
| 数据来源 | 构造传入 `PageLoader = Future<PagedAlbums> Function(int page)`；`List<LatestListScreen>` → `client.latest(page:)`；`PromoteListScreen` → `client.promoteList(id, page:)`；`LibraryScreen` 内联 → `categoriesFilter` / `randomRecommend`（后者每次返回同一批，`total: 0`） |
| 结构 | `Scaffold(appBar: AppBar(title: Column[Text(title), if(subtitle) Text(subtitle, labelSmall)]))`；body 四态；`asGrid` 决定 `CustomScrollView`+`SliverGrid`(190/0.52) 或 `ListView.builder`(`OpenableAlbumListTile`)；footer 作为一个额外 cell |
| 交互 | 上拉加载（`_onScroll`：`pixels >= maxScrollExtent - 480` 触发 `_loadNext`）；下拉刷新（`RefreshIndicator` → 清空 + 重拉第 1 页）；footer「加载失败，点击重试」`TextButton.icon` |
| 状态 | `_items.isEmpty && _loading` → `LoadingView()`；`_items.isEmpty && _error != null` → `ErrorView`；`_items.isEmpty` → `EmptyView('没有内容')`；有数据 + `_loading` → footer 转圈；`_error != null`（已有数据）→ footer 重试；`!_hasMore` → `'已经到底了'` |
| 动画 | 无本地动画（`RefreshIndicator` 自带） |
| 改造注意 | `_hasMore` 语义是双分支（`:78-80`）：`total > 0` 时用 `items.length < total`，`total == 0` 时用「本页非空」。上游 `LatestListScreen`/`PromoteListScreen` 故意传 `total: 0`，所以**不能**把它简化成单一判断，否则会无限翻页或提前停止 |

### 2.8 `AlbumDetailScreen` — 作品详情（543 行）

| 维度 | 内容 |
|---|---|
| 职责 | 封面大图 + 观看入口 + 元数据 + 标签/系列 + 评论区 + 相关推荐 |
| 数据来源 | `_load()` → `app.client.album(albumId)` → `AlbumDetail.fromJson`（`:40-44`）；收藏 `client.addFavorite(aid)`、关注 `client.toggleTracking(aid)`；`CommentSection` 自己拉 `client.forum(aid:, page:)`；`app.imgHost`；`app.loggedIn`（收藏/关注前置校验） |
| 结构 | `Scaffold` → `FutureBuilder<AlbumDetail>`：waiting → `_ScaffoldedLoading`（`Scaffold(body: LoadingView())`）；error → `Scaffold(appBar: AppBar(), body: ErrorView)`；data → `CustomScrollView`：`SliverAppBar(expandedHeight: width*4/3, pinned: true, actions: [收藏 M3EIconButton, 关注 M3EIconButton], flexibleSpace: FlexibleSpaceBar(collapseMode: parallax, background: Stack[CoverImage(3/4, radius 0), 顶部渐变 DecoratedBox]))` → `SliverToBoxAdapter(_WatchButton(key: _watchKey))` → `_header`（标题/作者/4 个 `_Stat`/简介）→ 标签/作品/角色三组 `Chip` → 系列（`SectionHeader` + 高 210 横滑）→ `CommentSection` → 相关推荐（`SectionHeader` + `SliverGrid` 190/0.52）→ 尾部 24 |
| 交互 | 收藏（登录校验 → `_actionBusy` 守卫 → SnackBar `已加入收藏`/错误；已收藏后不再重复调用）；关注（toggle → SnackBar `已关注`/`已取消关注`）；「观看漫画」→ `_read()` 圆形揭示转场进阅读器；点相关推荐/系列 → `M3ECard` 容器变换进新详情页 |
| 状态 | 整页 loading / error / data；`_favorited`、`_tracked`（本地乐观态，**不回读服务端**）；`_actionBusy`（防连点）；未登录访问收藏/关注 → SnackBar `请先在底栏「登录」页登录` |
| 动画 / 自绘 | ①`SliverAppBar` 折叠 + `CollapseMode.parallax`；②`_RadialRevealFromButton`：`AnimatedBuilder` + `CustomClipper<Path>`(`_CircleRevealClipper` 画圆) + `Transform.scale`（1.06→1.0，`alignment` 由按钮中心换算），`maxRadius = sqrt(dx²+dy²)` 到最远屏幕角；进出共用 `Durations.long2`；③`PageRouteBuilder` 提交该转场（`:107-120`） |
| 改造注意 | 骨架/占位加载只有一层 `LoadingView()`（没有 skeleton shimmer）；`_watchKey` 是转场唯一锚点，改布局必须先保证它存在且 `hasSize`；`FlexibleSpaceBar` + `expandedHeight` 与封面 3:4 强绑定；10 个 `SliverToBoxAdapter` 的顺序即信息架构 |

### 2.9 `ReaderScreen` — 阅读器（389 行）

| 维度 | 内容 |
|---|---|
| 职责 | 纵向滚动逐页看图（解密还原后的 `ui.Image`），点屏幕切显隐 bars |
| 数据来源 | `app.chapters.cached(albumId)`（同步命中，`:47`）与 `app.chapters.load(albumId, force:)`（`:104`）；`app.client.recordWatch(albumId)`（登录后 unawaited，忽略失败，`:114-118`）；图片走 `PageImageLoader.shared.load/prefetch/release`（`core/image_loader.dart`），内部再经 `PageCache` 三层缓存 + `ImageUnscrambler` 还原 |
| 结构 | `Scaffold(backgroundColor: scheme.surface, body: Stack[Positioned.fill(内容), AnimatedPositioned(顶栏), AnimatedPositioned(底栏)])`；内容 = `GestureDetector(translucent, onTap 切 _showBars)` → `ListView.builder(padding bottom 40, itemCount: pages.length)`，每项 `_ReaderPage(key: ValueKey(page.url))`；顶栏 = `Material(surface α0.94)` + `SafeArea(bottom:false)` + 高 56 `Row`(返回 `IconButton` + 标题)；底栏 = `Material` + `SafeArea(top:false)` + `Row('$cur / $total', TweenAnimationBuilder → LinearProgressIndicator)` |
| 交互 | 点击画面切 bars；滚动更新进度；返回 `Navigator.maybePop()`；单页失败可点「重试」 |
| 状态 | ①`_loading && _data == null` → `LoadingView('正在加载章节…')`；②`_error` → `ErrorView(retry: force reload)`；③`pages.isEmpty` → `EmptyView('该章节没有可显示的页面')`；④单页：`_image == null` → 高 320 转圈；`_failed` → `errorContainer` 底 + 页码 + 重试；有图 → `RawImage` |
| 动画 / 自定义绘制 | `AnimatedPositioned`(240ms, easeOutCubic) 顶栏 `top: 0 / -120`、底栏 `bottom: 0 / -100`；`AnimatedSwitcher`(220ms) 图片出现；`TweenAnimationBuilder`(220ms) 进度条；**图片解密还原**（`ImageUnscrambler.unscramble` → 按 num 段重排 RGBA 行） |
| 改造注意 | ①`_onScroll` 的页码是用 `offset / maxScrollExtent` **比例估算**（`:64-76`），不是真实页索引 → 换成 `PageView` 会整体失效；②`_ReaderPage.dispose` 必须 `loader.release(url)`（`:298-305`），一页 RGBA 约 25MB，漏掉就泄漏且无法淘汰；③`prefetchAround(cur..cur+2)` 是滚动流畅度的关键；④有缓存时后台刷新失败**不能清空已显示内容**（`:119-126`）；⑤全项目 **无 `Hero`、无 `PageView`、无 `InteractiveViewer`、无缩放手势、无长按**（已用正则全量确认，见 §3.5）——阅读器是纯纵向 `ListView` |

### 2.10 `WeekScreen` — 每周必看 / 期数（169 行）

| 维度 | 内容 |
|---|---|
| 职责 | 列出期数 → 点进某期榜单 |
| 数据来源 | `client.week()` → `List<WeekIssue>`（`:27-34`） |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText:'每週必看', leading: BackButton()))` + `FutureBuilder` → `ListView.separated`(`Divider(height:1, indent:16)`) + `ListTile(leading: CircleAvatar(issue.id), title: time or '第 id 期', trailing: chevron_right)` |
| 交互 | 点行 → `Navigator.push(MaterialPageRoute(_WeekDetailScreen))` |
| 状态 | waiting → `LoadingView()`；error → `ErrorView(retry 重建 future)`；空 → `EmptyView('暂无榜单')`；**无下拉刷新** |
| 动画 | 无 |
| 改造注意 | `leading` 用 `issue.id` 当徽标文字（不是序号），期号可能是长数字，宽度需兜住 |

### 2.11 `_WeekDetailScreen` — 某期榜单（private，同上文件）

| 维度 | 内容 |
|---|---|
| 职责 | 展示一期榜单的封面网格 |
| 数据来源 | `client.weekFilter(id:)` → `PagedAlbums`（`:117-121`） |
| 结构 | `M3EAppBar.top(titleText: time or '第 id 期', leading: BackButton())` + `FutureBuilder` → `GridView.builder(190/0.52, OpenableAlbumCard)` |
| 交互 | 点卡片 → `M3ECard` 容器变换进详情；**无分页、无下拉刷新** |
| 状态 | loading / error / empty(`'该期暂无内容'`) / data |
| 改造注意 | 无分页是既定行为（`weekFilter` 返回整页），不要顺手加无限滚动 |

### 2.12 `AccountAlbumsScreen` — 收藏 / 历史 / 关注（151 行）

| 维度 | 内容 |
|---|---|
| 职责 | 一个页面承载三种账号列表（由调用方传 loader） |
| 数据来源 | `widget.loader(page)` → `AccountAlbumPage{items, page, total, hasMore}`；调用方 = `account_screen.dart:267/277/287` → `favorites` / `watchList` / `trackingList` |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText: title, leading: BackButton()), body: GridView.builder(190/0.52) + RefreshIndicator)`；`itemCount = items.length + (_more ? 1 : 0)`，尾项是转圈 |
| 交互 | 上拉加载（阈值 400px，`_busy` 去重）；下拉刷新（回到第 1 页）；点卡片进详情 |
| 状态 | `_loading && items.isEmpty` → `LoadingView()`；error+空 → `ErrorView`；空 → `EmptyView(widget.emptyMessage)`；有数据 + `_more` → 尾部转圈 |
| 改造注意 | `AccountAlbumPage.hasMore` 是「本页非空」而非 total 比较（`account_models.dart:53`）；`childAspectRatio: 0.52` 有注释说明 0.58 会溢出 1px（`:131`），新皮肤若改字号必须重算 |

### 2.13 `NotificationsScreen` — 站内通知（157 行）

| 维度 | 内容 |
|---|---|
| 职责 | 通知列表 + 点开看 HTML 正文全文 |
| 数据来源 | `client.notifications()` → `List<AccountNotification>`（`:34`）；正文已在 `account_models.dart:79-81` 用 `htmlToPlainText` 折成纯文本 |
| 结构 | `Scaffold(appBar: M3EAppBar.top(titleText:'站内通知', leading: BackButton()))` + 四态嵌套三元；列表 = `RefreshIndicator` → `ListView.separated(Divider height 1)` + `ListTile(leading: 已读/未读图标, title 1 行省略, subtitle 最多 4 行, trailing: 时间 labelSmall)` |
| 交互 | 点行 → `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)` → `DraggableScrollableSheet(expand:false, 0.6/0.3/0.95)` → `ListView` 内 `SelectableText` 全文 |
| 状态 | loading / error / empty(`'还没有通知'`) / data；未读用 `scheme.primary` 着色 |
| 动画 | 无本地动画（`showModalBottomSheet` + 拖拽自带） |
| 改造注意 | 只有这里用 `SelectableText` 和 `DraggableScrollableSheet`；`test/notifications_test.dart:64` 断言 `find.byType(SelectableText)` |

### 2.14 `DiscoverSearchBar` — 顶部搜索栏（组件，240 行）

| 维度 | 内容 |
|---|---|
| 职责 | 收起态 = 标题 `'发现'` + 小胶囊搜索框 + 「每周必看」图标；展开态 = 搜索框拉长铺满整条 bar |
| 数据来源 | 全受控（`controller` / `expanded` 由 `HomeScreen` 持有）；自身只持 `FocusNode` |
| 结构 | `LayoutBuilder` → `Stack`：①标题行（`IgnorePointer(expanded)` + `AnimatedOpacity` + `AnimatedSlide` + `Row('发现', Spacer, IconButton(leaderboard))`）；②`Align(centerRight)` → `AnimatedContainer(width: expanded ? fullWidth : 148, height: 48, margin right 16→0, 圆角 24→0)` → `Material(transparency)` → `Row[AnimatedSwitcher(返回箭头/搜索图标), Expanded(TextField), ValueListenableBuilder(清空按钮)]` |
| 交互 | 点小框 → 展开（下一帧 `requestFocus`，`:52-56`）；失焦 → 自动收起（`:71-77`）；点返回箭头 → `_collapse`；回车 → `onSubmitted(trim)`；有内容显示清空按钮 |
| 动画 | `AnimatedContainer`(medium2, easeInOutCubic) 宽度/外边距/圆角；`AnimatedOpacity` + `AnimatedSlide`(short4) 标题淡出上移；`AnimatedSwitcher`(short4) 图标切换 |
| 改造注意 | ①展开/收起完全由父级驱动，组件不能自己 setState 改 `expanded`；②`readOnly: !expanded` + `showCursor: expanded` 是「收起态仍能点击展开」的关键；③`_searchBarKey` 挂在它上面，是 JM 号直达转场的原点 |

### 2.15 `DiscoverSearchPanel` — 搜索面板（组件，289 行）

| 维度 | 内容 |
|---|---|
| 职责 | 搜索历史 + 热门标签（landing）/ 搜索结果分页 |
| 数据来源 | `client.hotTags()`（失败静默，`:84-93`）；`client.search(keyword, page:)` → `PagedAlbums`（`:121-123`）；`app.searchHistory` / `app.addSearchHistory` / `app.clearSearchHistory` |
| 结构 | landing：`ListView`（`SectionHeader('搜索历史', moreLabel:'清空')` + `Wrap` 装 `M3EChip(suggestion)`、`SectionHeader('热门标签')` + 同款 `Wrap`、两者皆空 → `EmptyView('输入关键词开始搜索')`）；results：`Column`(查询词 + `约 N 个结果` 表头 + `Expanded(ListView.builder(OpenableAlbumListTile))`) |
| 交互 | 点 chip → `_pick`：作品号 → `openAlbumPreviewFromCenter(originKey: chip 的 GlobalKey)`；普通词 → `onKeywordSelected` + `_search`；上拉加载（阈值 480，且 `results.length < total`）；重复点同词靠 `searchNonce` 触发 |
| 状态 | `_searched` 决定整块切换；`_results.isEmpty && _loading` → `LoadingView('搜索中…')`；空 + error → `ErrorView`；空 → `EmptyView('没有找到相关结果')`；加载更多 → footer 转圈 |
| 改造注意 | ①每个 chip 现造一个 `GlobalKey`，是容器变换的起点（`:183-188`）；②`addSearchHistory` 放在 `addPostFrameCallback`，否则 build 期间 `notifyListeners` 报 `markNeedsBuild during build`（`:108-113` 注释）；③热门标签兼容 `String` 与 `Map` 两种形态（`_tagName`） |

### 2.16 `CommentSection` — 评论区（组件，645 行，最大 UI 文件）

| 维度 | 内容 |
|---|---|
| 职责 | 评论计数 + 写评论面板（默认收起）+ 分页评论列表 + 剧透折叠 |
| 数据来源 | `client.forum(aid:, page:)` → `PagedComments`（`:82-83`）；`client.sendComment(aid:, content:, spoiler:)` → `CommentSendResult`（`:306-310`）；`app.loggedIn`；`app.imgHost` |
| 结构 | `Column`：①`AnimatedSize(medium2, easeOutCubic, alignment: topCenter)` 包住 `_CommentComposer` 或 `SizedBox(width: infinity)`；②标题行（`'评论'` + 计数徽标 + `Spacer` + `TextButton.icon('写评论')`）；③列表体（首屏转圈 / 行内错误 + 重试 / `'还没有评论'` / `..._items.map(_CommentTile)`）；④footer（`OutlinedButton('查看更多评论（n/total）')` 或 `'没有更多评论了'`） |
| 交互 | 写评论（未登录 → SnackBar 引导）；发送（`_sending` 禁用、成功后清空 + 收起 + `_reload()` 整页重拉）；查看更多（手动按钮，不是滚动触发）；剧透评论 → `InkWell` 点击展开；剧透开关 `FilterChip`；字数 `n/200` 自绘计数器（`buildCounter: null`） |
| 状态 | `_loading`/`_error`/`_loadedOnce`（首屏 vs 增量）/`_items`/`_total`/`_composerOpen`/`_sending`/`_spoiler`/`_revealed`（每条） |
| 动画 | `AnimatedSize` 展开写评论面板 |
| 改造注意 | ①`_reload()` 而不是 append：新评论出现在第 1 页顶部，逐页 append 会错位（`:57-70`）；②`_hasMore = _items.length < _total`；③`filterChip` + 自绘计数 + `AnimatedSize` 三处都与「面板可折叠」语义耦合；④它是 `AlbumDetailScreen` 的一个 sliver 子节点，**没有自己的 Scaffold/滚动容器**（滚动由外层 `CustomScrollView` 提供）—— 换布局时不能改成独立可滚组件 |

---

## 3. Material / M3E 组件与 API 全清单（按使用频次）

计数方式：对 `lib/` 全量正则统计，`文件数` = 出现该符号的文件个数，`次数` = 全项目出现总次数。装饰性 API（`Theme.of`/`Icons.`/`EdgeInsets`/`SizedBox`）一并列出，因为它们决定改造的真实工作量。

### 3.1 总频次表（Top，降序）

| 排名 | 组件 / API | 文件数 | 次数 | 出现文件（次数） |
|---:|---|---:|---:|---|
| 1 | `Text(...)` | 14 | 118 | account(18), album_detail(14), comment_section(22), settings(18), start(9), album_card(7), common(6), notifications(6), library(5), album_list(4), reader(4), week(2), search_panel(2), discover_search_bar(1) |
| 2 | `scheme.<role>`（ColorScheme 取色） | 13 | 99 | comment_section(22), start(19), account(10), reader(7), common(7), album_detail(6), app_theme(6), library(5), album_card(5), notifications(4), settings(4), discover_search_bar(3), album_open_transition(1) |
| 3 | `Theme.of(context)` | 17 | 91 | comment_section(17), album_card(10), account(9), common(8), start(8), album_detail(7), notifications(6), reader(6), album_list(4), discover_search_bar(4), search_panel(3), library(2), m3e_bridge(2), week(2), settings(1), album_open_transition(1), main(1) |
| 4 | `SizedBox` | 17 | 90 | comment_section(18), account(15), album_detail(11), start(11), reader(7), album_card(6), common(4), home(3), discover_search_bar(3), search_panel(3), library(2), notifications(2), main(1), album_list(1), account_albums(1), root_shell(1), settings(1) |
| 5 | `Icons.*` | 13 | 76 | account(16), album_detail(10), root_shell(8), settings(8), start(5), common(6), comment_section(6), discover_search_bar(4), library(3), reader(3), notifications(2), album_list(1), week(1) |
| 6 | `EdgeInsets` | 17 | 71 | comment_section(14), album_detail(6), library(6), start(6), search_panel(6), album_card(5), album_list(4), settings(4), discover_search_bar(3), reader(3), openable_album(3), home(2), notifications(2), week(2), account(2), common(2), account_albums(1) |
| 7 | `Icon(...)` | 13 | 65 | account(15), root_shell(8), settings(8), common(6), comment_section(6), album_detail(5), start(5), discover_search_bar(4), reader(3), library(2), notifications(1), album_list(1), week(1) |
| 8 | `textTheme.*` | 11 | 39 | comment_section(9), album_card(7), album_detail(6), account(3), common(3), album_list(2), notifications(2), reader(2), start(2), search_panel(2), discover_search_bar(1) |
| 9 | `Row(...)` | 10 | 25 | comment_section(7), album_detail(3), account(2), library(2), reader(2), start(2), album_card(2), common(2), discover_search_bar(2), search_panel(1) |
| 10 | `Column(...)` | 10 | 23 | album_card(4), start(4), album_list(3), comment_section(3), common(3), album_detail(2), home(1), library(1)... (全 10 文件) |
| 11 | `Navigator.*` | 8 | 16 | account(4), home(3), library(3), settings(2), album_detail(1), reader(1), start(1), week(1) |
| 12 | `Expanded(...)` | 10 | 16 | account(2), library(2), reader(2), start(2), album_card(2), comment_section(2), album_detail(1), common(1), discover_search_bar(1), search_panel(1) |
| 13 | `SliverToBoxAdapter` | 3 | 15 | album_detail(10), home(4), album_list(1) |
| 14 | **`Scaffold`** | **12** | **15** | album_detail(3＝页面+错误态+加载态), week(2＝列表页+详情页), account(1), account_albums(1), album_list(1), home(1), library(1), notifications(1), reader(1), root_shell(1), settings(1), start(1) |
| 15 | `CircularProgressIndicator` | 9 | 13 | start(3), comment_section(3), account(1), account_albums(1), album_list(1), reader(1), settings(1), common(1), search_panel(1) |
| 16 | `SnackBar(...)` | 4 | 11 | album_detail(5), comment_section(3), settings(2), account(1) |
| 17 | `ListTile` | 4 | 11 | settings(5), account(4), notifications(1), week(1) |
| 18 | **`M3EButton(...)`** | 5 | 10 | account(4), settings(3), album_detail(1), start(1), common(1) |
| 19 | `appBar:` 命名参数 | 9 | 10 | week(2), 其余各 1（account, account_albums, album_detail, album_list, home, library, notifications, settings） |
| 20 | `GlobalKey` | 4 | 10 | album_detail(3), search_panel(3), home(2), album_open_transition(2) |
| 21 | **`M3EAppBar.top(...)`** | 7 | 8 | week(2), account(1), account_albums(1), home(1), library(1), notifications(1), settings(1) |
| 22 | `ListView.*` | 8 | 8 | album_detail, album_list, home, notifications, reader, start, week, search_panel 各 1 |
| 23 | `Wrap(...)` | 4 | 6 | album_detail(2), search_panel(2), library(1), settings(1) |
| 24 | `AnimatedSwitcher` | 5 | 6 | common(2), home(1), reader(1), start(1), discover_search_bar(1) |
| 25 | `RefreshIndicator` | 5 | 6 | album_list(2), account_albums(1), home(1), library(1), notifications(1) |
| 26 | `FutureBuilder` | 4 | 5 | week(2), album_detail(1), home(1), library(1) |
| 27 | `IconButton`（Material 原生，不含 M3E） | 3 | 5 | discover_search_bar(3), account(1), reader(1) |
| 28 | `M3EChip(...)` / `M3EChipType` | 3 / 3 | 4 / 4 | search_panel(2), library(1), settings(1) |
| 29 | `CircleAvatar` | 4 | 4 | account, library, start, week 各 1 |
| 30 | `TextField` | 3 | 4 | account(2), comment_section(1), discover_search_bar(1) |
| 31 | `Divider(...)` | 3 | 4 | account(2), notifications(1), week(1) |
| 32 | `MediaQuery` | 2 | 4 | album_detail(3), album_open_transition(1) |
| 33 | `M3ECard(...)` | 1 | 3 | openable_album(3) |
| 34 | `CustomScrollView` / `SliverGrid(` | 3 / 3 | 3 / 3 | album_detail, album_list, home |
| 35 | `Stack(...)` | 3 | 3 | album_detail, reader, discover_search_bar |
| 36 | `M3ESegment`（`M3ESegmentedButton` 内） | 1 | 3 | settings |
| 37 | 其余中低频组件（逐条见下表） | — | — | — |

> 口径注释（2026-11-21 复核）：上表基于 33 个基线文件（`lib/theme/prism_theme.dart` 尚未存在）。若把新增的 `prism_theme.dart` 计入，则 `scheme.*` 变 **14 文件 / 100 次**、`Theme.of` 变 **18 文件 / 92 次**（其中 1 次是 `PrismTheme.of(brightness)` 的**子串误匹配**，非 `Theme.of(context)` 调用）；其余各行数字不变。

**3.1.1 中低频组件明细（次数 ≤ 20）**| 组件 / API | 文件数 | 次数 | 出现位置 |
|---|---:|---:|---|
| `BorderRadius` | 8 | 20 | start(4), app_theme(4), comment_section(5), album_detail(2), common(2), album_card(1), discover_search_bar(1), reader(1) |
| `BoxDecoration` | 5 | 11 | comment_section(4), start(3), album_detail(2), album_card(1), discover_search_bar(1) |
| `TextButton`（含 `.icon`/`.styleFrom`） | 4 | 9 | comment_section(5), reader(2), album_list(1), common(1) |
| `AspectRatio` | 6 | 7 | common(2), account_albums(1), album_detail(1), album_list(1), home(1), week(1) |
| `Material(...)` | 3 | 4 | reader(2), start(1), discover_search_bar(1) |
| `FilledButton`（含 `.tonalIcon`） | 3 | 4 | comment_section(2), library(1), start(1) |
| `BackButton` | 3 | 4 | week(2), account_albums(1), notifications(1) |
| `withValues(alpha:)` | 3 | 4 | reader(2), album_detail(1), common(1) |
| `SafeArea` | 2 | 3 | reader(2), start(1) |
| `Positioned` | 1 | 3 | reader(3) |
| `InkWell` | 3 | 3 | comment_section(1), library(1), start(1) |
| `Image.network` | 3 | 3 | account(1), comment_section(1), common(1) |
| `ClipOval` | 2 | 2 | account(1), comment_section(1) |
| `FilterChip` | 1 | 2 | comment_section(2) |
| `OutlinedButton` | 1 | 2 | comment_section(2) |
| `AnimatedContainer` | 2 | 2 | start(1), discover_search_bar(1) |
| `IndexedStack` | 1 | 2 | root_shell(2) |
| `showDialog` | 2 | 2 | account(1), settings(1) |
| `AlertDialog` | 2 | 2 | account(1), settings(1) |
| `GridView.builder` | 2 | 2 | account_albums(1), week(1) |
| `ClipRRect` | 1 | 2 | common(2) |
| `characters`（扩展） | 2 | 2 | library(1), comment_section(1) |
| 单次（1 文件 / 1 次） | — | — | `SliverAppBar`、`FlexibleSpaceBar`、`CollapseMode`、`CustomClipper`、`ClipPath`、`Transform.scale`(2)、`AnimatedBuilder`、`PageRouteBuilder`、`RawImage`、`LinearProgressIndicator`、`TweenAnimationBuilder`、`AnimatedPositioned`(2)、`AnimatedSize`、`AnimatedOpacity`、`AnimatedSlide`、`LayoutBuilder`、`IgnorePointer`、`ValueListenableBuilder`、`Card(`、`ExpansionTile`、`Chip(`、`SelectableText`、`DraggableScrollableSheet`、`showModalBottomSheet`、`DecoratedBox`、`KeyedSubtree`、`GestureDetector`、`Colors.transparent` |

### 3.2 「某组件出现在哪几个文件」速查（改造排期用）

| 组件 | 文件 |
|---|---|
`Scaffold` | album_detail, week, account, account_albums, album_list, home, library, notifications, reader, root_shell, settings, start
`M3EAppBar.top` | account, account_albums, home, library, notifications, settings, week
`AppBar(`（Material 原生） | album_list, album_detail(错误态空 AppBar)
`SliverAppBar`+`FlexibleSpaceBar`+`CollapseMode` | album_detail（唯一）
`CustomScrollView` | album_detail, home, album_list
`ListView` | account, album_detail, album_list, home, notifications(2), reader, settings, start, week, search_panel(2)
`GridView.builder` | account_albums, week(_WeekDetailScreen)
`SliverGrid` | album_detail, album_list, home（+ account_albums/week 的 GridView 同一套 190/0.52 参数）
`RefreshIndicator` | account_albums, album_list(2), home, library, notifications
`FutureBuilder` | album_detail, home, library, week(2)
`AnimatedSwitcher` | common(2), discover_search_bar, home, reader, start
`AnimatedContainer` | discover_search_bar, start
`AnimatedPositioned` | reader(2)
`AnimatedSize` | comment_section
`AnimatedBuilder` | album_detail
`TweenAnimationBuilder` | reader
`LayoutBuilder` | discover_search_bar
`IndexedStack` | root_shell(2)
`M3ENavigationBar` (+`Destination`) | root_shell（唯一）
`M3ECard` (+`M3ECardVariant`) | openable_album(3)
`M3ECardContainerTransform.show` | album_open_transition（唯一）
`M3EButton` | account(4), settings(3), album_detail(1), start(1), common(1)
`M3EIconButton` (+`Variant`, +`M3EHapticFeedback`) | album_detail(2)
`M3EChip` | search_panel(2), library(1), settings(1)
`M3ESegmentedButton`/`M3ESegment` | settings（唯一）
`M3ETheme`/`M3EThemeData` | m3e_bridge（唯一，`main.dart` 只引用 `M3EBridge`）
`SnackBar`+`ScaffoldMessenger` | account, album_detail, comment_section, settings（+ 主题里 snackBarTheme）
`AlertDialog`+`showDialog` | account（退出确认）, settings（清缓存确认）
`showModalBottomSheet`+`DraggableScrollableSheet`+`SelectableText` | notifications（唯一）
`TextField` | account(2), comment_section(1), discover_search_bar(1)
`FilterChip` | comment_section(2)
`ExpansionTile` | library（唯一）
`CircleAvatar` | account, library, start, week
`Card(` | library（唯一）
`InkWell` | comment_section, library, start
`RawImage` | reader（唯一）
`ClipPath`+`CustomClipper`+`Transform.scale` | album_detail（转场，唯一）
`LinearProgressIndicator` | reader（唯一）
`GestureDetector` | reader（唯一，用于点屏切 bars）
`BackButton` | account_albums, notifications, week(2)
`PageRouteBuilder` | album_detail（唯一）
`MaterialPageRoute` | account(2), home(3), library(3), start(1), week(1)

### 3.3 M3E（`material_3_expressive`）依赖面 —— 改造必须整体替换/移植

`lib/` 中引用 M3E 符号共 **76 处 / 17 文件**，实际用到的 API 只有 10 个组件族：

| M3E API | 用途 | 文件:行 | 迁移要点 |
|---|---|---|---|
| `M3ETheme(data:)` + `M3EThemeData.fromMaterial(ThemeData)` | 把 Material ThemeData 桥接成 M3E token | `m3e_bridge.dart:24,26` | **唯一的注入点**，新设计系统在此替换；静态缓存了 `_source`/`_data` |
| `M3EAppBar.top(titleText:/title:/leading:/automaticallyImplyLeading:)` | 7 个页面的顶栏 | account:115, account_albums:102, home:127, library:89, notifications:99, settings:82, week:47,128 | 参数形态 3 种（`titleText` / `title: Widget` / 带 `leading`） |
| `M3ENavigationBar` + `M3ENavigationBarDestination` | 底部导航 4 项 | root_shell:57-83 | 选中胶囊弹簧 + 触觉；label 动态（登录态） |
| `M3ECard(variant: filled, padding: zero, clipBehavior, haptic, openBuilder:, child:/width:)` | 卡片 + **容器变换打开详情页**（全项目唯一的「点作品→详情」入口） | openable_album:27,53,78 | 起点矩形/圆角/底色/淡入节奏由组件内部算，替换时需新系统自带等价 transform 或退回 `Hero`+自定义 Route |
| `M3ECardContainerTransform.show(origin:, originRadius:, originColor:, builder:)` | 无卡片时（JM 号直达）的容器变换 | album_open_transition:38-45 | 依赖 `GlobalKey` → `RenderBox` 矩形 |
| `M3EButton(onPressed:, enabled:, icon:, label:/child:, style:)` + `M3EButtonStyle.text` | 主行动按钮 | account:92,97,198,301; settings:41,46,157; start:108; album_detail:431; common:135 | 内部渲染为 Material `FilledButton`/`TextButton`（测试以此断言）；`label` 与 `child` 两种写法并存 |
| `M3EIconButton(variant:, tooltip:, haptic:, onPressed:, icon:)` + `M3EIconButtonVariant.standard` | 详情页收藏/关注 | album_detail:153,162 | |
| `M3EHapticFeedback.light` | 触觉反馈枚举 | album_detail:156,165; openable_album:31,58,82 | |
| `M3EChip(label:, type:, selected:, onPressed:)` + `M3EChipType.suggestion/filter` | 搜索历史/热词/子分类/线路 | search_panel:184,205; library:186; settings:130 | chip 同时是「转场原点」（`GlobalKey`） |
| `M3ESegmentedButton<T>(segments:, selected:, onSelectionChanged:)` + `M3ESegment<T>(value:, icon:, label:)` | 主题三选一 | settings:89-110 | 唯一的分段控件 |

> 注意：`M3ETappable`、`M3EHaptics`、`M3EMotion` 只在 `openable_album.dart:12-14` 的**注释**里出现，不是实际 API 调用。

### 3.4 Material 的「隐式依赖」（不是组件，但换设计系统一定会踩）

| 依赖 | 位置 | 说明 |
|---|---|---|
| `Theme.of(context).colorScheme` 的 22 个语义角色 | 见 §3.6 | 全部取色都走 `scheme.*`，新系统需要提供同语义 token 字典 |
| `Theme.of(context).textTheme` 的 11 个字号档 | 39 处 | 实际用到的档位：`headlineMedium`、`headlineSmall`、`titleLarge`、`titleMedium`、`titleSmall`、`bodyLarge`、`bodyMedium`、`bodySmall`、`labelLarge`、`labelMedium`、`labelSmall` |
| `Durations.*`（Material motion token） | 9 处：album_detail(long2×2), home(short4), comment_section(medium2), discover_search_bar(short4×4, medium2) | 新系统若改时长需同步 |
| `Curves.*` | 14 处（easeOutCubic / easeInOutCubic / easeOut / easeIn） | |
| `PageTransitionsTheme` + `PredictiveBackPageTransitionsBuilder` | app_theme:34-38 | 全局 Android 预测式返回 |
| `MediaQuery.sizeOf` | album_detail(3), album_open_transition(1) | 转场几何计算 |
| `characters` 扩展（`xxx.characters.first`） | library:163, comment_section:331 | 依赖 flutter 的 `characters` 导出 |
| `Icons.*`（Material Icons 字体，`uses-material-design: true`） | 76 处 / 13 文件 | 换图标体系时是**全覆盖替换**，需逐条映射 |
| `Color.withValues(alpha:)` | 4 处（reader×2, album_detail, common） | 新 Flutter 色彩 API |

### 3.5 负向清单（**没有**用到，可以据此砍工作量）

已用正则全量确认：

| 能力 | 结论 |
|---|---|
| `Hero` 转场 | **0 处**。所有「图片飞入」观感都由 `M3ECard` 容器变换实现 |
| `PageView` / 翻页 | **0 处**。阅读器是纵向 `ListView`，无左右翻页 |
| `InteractiveViewer` / 双指缩放 / `onScaleUpdate` | **0 处**。无手势缩放 |
| `onLongPress` / `Dismissible` / 滑动删除 | **0 处**。站长功能（长按菜单、滑动删收藏）**尚未实现** |
| 命名路由 / `Route` 子类 / `onGenerateRoute` | **0 处**（全部 `Navigator.push` + `MaterialPageRoute`/`PageRouteBuilder`） |
| 骨架屏 shimmer | **0 处**（只有 `start_screen` 的 `_LineSkeleton` 是静态占位块，无动画） |
| 深色/浅色以外的主题、字体资产、`assets:` | **0 处**（`pubspec.yaml` 的 `assets`/`fonts` 全部注释未启用） |
| `flutter_localizations` / 多语言 | **0 处**（全部中文硬编码字符串） |
| `navigationBarTheme` 配置 | 已配置但**无消费者**（底栏是 `M3ENavigationBar`，读 `M3ETheme`）→ 属死配置 |

### 3.6 语义色使用频次（token 映射用）

| ColorScheme 角色 | 次数 | 文件 |
|---|---:|---|
| `onSurfaceVariant` | 33 | comment_section(10), account(4), start(4), album_detail(3), notifications(3), settings(3), album_card(3), common(2), discover_search_bar(1) |
| `secondaryContainer` / `onSecondaryContainer` | 5 / 5 | account(2/1), library(1/1), album_card(1/1), comment_section(1/2) |
| `primary` | 6 | start(3), account(1), album_detail(1), notifications(1) |
| `error` | 10 | comment_section(3), start(3), account(2), settings(1), common(1) |
| `surfaceContainerHigh` | 3 | start(2), discover_search_bar(1) |
| `surfaceContainerHighest` | 4 | comment_section(3), common(1) |
| `surfaceContainerLow` | 3 | start(1), app_theme(1), album_open_transition(1) |
| `surfaceContainer` | 2 | app_theme(1), discover_search_bar(1) |
| `surface` / `onSurface` | 4 / 2 | reader(3)+app_theme(1) / app_theme(2) |
| `errorContainer` / `onErrorContainer` | 2 / 4 | reader, common |
| `primaryContainer` / `onPrimaryContainer` | 3 / 3 | library, start, comment_section |
| `outlineVariant` | 3 | start(2), app_theme(1) |
| `outline` | 2 | comment_section, common |
| `onPrimary` | 4 | album_detail(2), start(2) |
| `Colors.transparent` | 1 | start_screen:182（唯一硬编码色，可忽略） |

---

## 4. 不属于 UI 层 —— 不要动

> 原则：这 8 个文件（+ `data/`）只被 UI 以「构造参数 / 方法调用 / 数据对象」的方式消费。改造 UI 时**只允许改调用处的呈现**，禁止改这些文件的签名或内部行为。

| 文件 | 行数 | 提供什么能力 | 页面改造时如何继续调用 |
|---|---|---|---|
| `lib/core/gateway_client.dart` | 840 | 网关协议全套：线路清单解密（AES-256-ECB，key=`md5("diosfjckwpqpdfjkvnqQjsik")`）、`Token`/`Tokenparam` 签名、响应封套解密（2 个候选 secret）、3 次重试、401 自动清会话、`ensureReady/probeHost/switchHost`，以及约 35 个业务端点（`promote/latest/serialization/categories/categoriesFilter/week/weekFilter/search/hotTags/randomRecommend/album/comicRead/chapter/forum/sendComment/videos/novels/blogs/creatorAuthor/favorites/favoriteFolders/addFavorite/watchList/recordWatch/trackingList/toggleTracking/notifications/unreadNotificationCount/userProfile`） | 统一通过 `context.read<AppState>().client`（或 `.app.client`）调用；`imgHost`/`baseUrl` 走 `AppState` 的 getter。**新 UI 不得自行拼 URL、不得自己发 http** |
| `lib/core/page_cache.dart` | 370 | 三层缓存：L1 解码 `ui.Image` LRU 64MB（**带引用计数**）、L2 原始字节 32MB、L3 磁盘 256MB（`<cacheDir>/jm_pages`）；`obtainImage/releaseImage/putImage/readBytes/writeBytes/usage()/clear()/warmUp()` | 阅读器经 `PageImageLoader` 间接用；设置页直接用 `PageCache.instance.usage()` / `.clear()`。**`obtainImage` 必须配对 `releaseImage`** |
| `lib/core/chapter_cache.dart` | 61 | 章节页列表内存缓存（ttl 15min, 最多 12 章）：`cached(id)` / `load(id, force:)` / `invalidate` / `clear` | 阅读器 `app.chapters.cached/load`；设置页 `app.chapters.clear()` |
| `lib/core/image_loader.dart` | 143 | 单页图片管线：缓存命中 → 下载（带 UA/Referer 头，30s 超时）→ 解码 → 按需还原乱序；并发同 URL 合并；`load/prefetch/release`；`static shared` | 阅读器 `PageImageLoader.shared.load(url:aid:scrambleId:)`，**必须 `release`**；`prefetch` 用于预取 |
| `lib/core/image_unscramble.dart` | 114 | 乱序还原算法：`segmentCount(scrambleId, aid, fileName)`（`aid < scrambleId` 不还原；`aid < 268850` 固定 10 段；否则 `md5("<aid><页号>")` 末位 ASCII % x *2+2）、`unscramble(ui.Image, num)` 按行重排 RGBA | 只被 `image_loader.dart` 调用。**UI 层不要直接碰**；新阅读器只要继续走 `PageImageLoader` 就自动正确 |
| `lib/core/crypto_utils.dart` | 35 | `md5Hex`、`aesEcbDecryptBase64`（含 PKCS7 去填充、密文清洗） | 只被 `gateway_client.dart` 使用 |
| `lib/core/settings_store.dart` | 188 | `AppSettings{themeMode, searchHistory, jwtToken, avs, memberInfo}` + JSON 落盘（`<appSupportDir>/settings.json`，临时文件+rename，失败静默）；`hasSession` | 只经 `AppState.settings` / `AppState.restoreSettings/_persist`。**注意 `AppSettings` 里 import 了 `material_ui` 只为 `ThemeMode` 枚举** —— 若新设计系统不再用 `ThemeMode`，应改在 `AppState` 层做适配，不要动这个文件 |
| `lib/core/comic_query.dart` | 14 | `albumIdFromQuery`：`1488098`/`JM1488098`/`jm 1488098`/`#1488098` → `"1488098"`，≥4 位数字才认 | `home_screen:68`、`search_panel:142`。**这是「作品号直达」与「搜索」的分流开关**，新 UI 必须保留这两个调用点 |
| `lib/data/models.dart` | 548 | 14 个数据类 + `fromJson` + 工具 getter（`AlbumSummary.coverUrl(imgHost)`、`Comment.displayName/avatarUrl/isSpoiler`、`PagedAlbums.hasMore`）+ `htmlToPlainText` | UI 只读字段。**不要改字段名/不要加 UI 专用字段**；`coverUrl` 是封面地址唯一来源（接口常返回空 `image`） |
| `lib/data/account_models.dart` | 87 | `FavoriteFolder`、`AccountAlbumPage`(+`hasMore`)、`AccountNotification`（含 HTML→纯文本） | 同上 |
| `lib/state/app_state.dart` | 307 | 见 §1.5 | UI 只 `context.watch/read/select`；**不要往 AppState 里加 UI 临时状态**（搜索展开态、收藏乐观态现在都留在页面里，这是对的） |

---

## 5. 风险点（改造最容易破坏行为的地方）

| # | 风险点 | 位置 | 为什么容易坏 | 正确做法 |
|---:|---|---|---|---|
| R1 | **阅读器图片生命周期** | `reader_screen.dart:264-388` + `image_loader.dart:38-72` + `page_cache.dart:64-98` | `load` 拿到的 `ui.Image` 带引用计数，`dispose` 里必须 `release`；一页 RGBA ≈ 25MB。改造时若把 `_ReaderPage` 换成无状态 widget、或忘记在 `didUpdateWidget`/`dispose` 里配对，就会出现「已释放的图被绘制」（崩溃）或缓存永不淘汰（OOM） | 保留「有状态单页 + `_holding` 标记 + dispose 释放」这一结构；若换 `PageView`/`SliverList` 必须重新论证可见性回收 |
| R2 | **阅读器进度与滚动耦合** | `reader_screen.dart:64-76` | 页码是 `offset / maxScrollExtent` 比例估算，不是真实索引；换成 `PageView`、加 header、改 padding 都会让「当前页」漂移 | 换布局时改用「可见项」判定，并同步改 `_prefetchAround` 的触发点 |
| R3 | **阅读器有缓存时的刷新失败** | `reader_screen.dart:95-127` | 有缓存时后台刷新失败**不能**清空 `_data`（`:124` 的 `if (_data == null)` 是关键），否则看一半白屏 | 保留「缓存优先、错误只在不曾有数据时展示」的三态模型 |
| R4 | **详情页转场锚点** | `album_detail_screen.dart:96-121, 475-543`；`_watchKey:28` | 圆形揭示的圆心/半径来自「观看漫画」按钮的 `RenderBox`；按钮一旦被移出首屏、被 `SliverAppBar` 遮挡、或改成 `Expanded` 占位，`box.hasSize == false` 就退化成全屏矩形兜底（观感全变） | 保留 `_watchKey` 挂在真实按钮上且首帧可见；`maxRadius` 计算依赖 `MediaQuery`，横屏/分屏需回归 |
| R5 | **详情页骨架与封面比例** | `album_detail_screen.dart:145-195` | `expandedHeight = screenWidth * 4/3` 是写死的封面比例，与 `SliverAppBar`+`FlexibleSpaceBar.parallax` 组合；加载态只有 `LoadingView`（无骨架），换布局容易出现「先白屏再跳图」 | 若要做真骨架屏，需与 `expandedHeight` 同尺寸占位，否则会二次布局抖动 |
| R6 | **起始页测速状态机** | `start_screen.dart:17-126`；`app_state.dart:110-154` | `refreshLines` 会在**每条线路完成时** `notifyListeners`（渐进更新）；`fastestHost` 只在测速中为假的条件下生效；`_enteringHost` 是唯一防重复进入的闸门；`selectLine` 要一次网络往返，成功后靠 `app.ready` 放行 | 不要引入本地 `Future.wait` 聚合导致一次性刷新；不要用「点击后立刻跳转」；`blocked/entering/probing` 三个状态必须都在 |
| R7 | **卡片打开详情是唯一入口** | `openable_album.dart`（3 个组件）、`album_open_transition.dart` | 全项目「点作品→详情」只经 `M3ECard.openBuilder` / `M3ECardContainerTransform.show`；换成 `Navigator.push` 会丢掉容器变换，且 `test/album_open_transition_test.dart:67,72` 直接断言 `find.byType(M3ECard)` | 先在新设计系统里确定「容器变换」能力（或 `Hero` 替代方案），再替换这 4 个入口 |
| R8 | **JM 号直达与搜索分流** | `home_screen.dart:66-89`、`search_panel.dart:139-156` | 两条路径的后续动作完全不同（直达=不改搜索框/不开结果页；搜索=写历史+开结果）。`home` 里还依赖「先开详情页、下一帧再收搜索框」的顺序（注释说明三套动画同时推会乱） | 保留 `albumIdFromQuery` 分流 + `addPostFrameCallback` 时序 |
| R9 | **搜索栏受控与失焦收起** | `discover_search_bar.dart:49-88` | `expanded` 是父级属性；失焦自动收起、展开后下一帧 focus、`readOnly`/`showCursor` 组合，任何一处改动都会出现「键盘收了框没收」或「点了没反应」 | 逐条保留 4 个时序钩子：`didUpdateWidget` focus、`_onFocusChanged` postFrame、`_expand`、`_collapse` |
| R10 | **评论区「重拉而非追加」** | `comment_section.dart:57-70` | 发评论成功后必须整段重拉（新评论在第 1 页顶部），append 会让 `_page`/`_total` 不自洽 | 保留 `_reload()`；`_hasMore = _items.length < _total` |
| R11 | **分页 `total == 0` 语义** | `album_list_screen.dart:77-81`；上游 `total: 0` | `LatestListScreen`/`PromoteListScreen`/`randomRecommend` 都传 `total: 0`，靠「本页是否为空」判结束；简化成 `items.length < total` 会立刻停止翻页 | 保留双分支；或把「未知总数」建模成 `int? total`（改动会波及 `data/models.dart`，不建议） |
| R12 | **页签懒构建 + 保活** | `root_shell.dart:30-34`；`home/library` 的 `AutomaticKeepAliveClientMixin` | 换 `Navigator`/`PageView` 做页签会一次性建 4 页 → 首帧 6+ 请求；丢掉 KeepAlive → 每次切页都重新请求 | 保留 `IndexedStack + _built[]`（或新系统的惰性容器）+ `wantKeepAlive = true` |
| R13 | **主题桥接与缓存** | `theme/m3e_bridge.dart`、`theme/app_theme.dart` | `M3EBridge` 以 `ThemeData` **identity** 缓存 M3E token；`AppTheme` 缓存两份 ThemeData。新设计系统若在 `MaterialApp.builder` 里再包一层自己的 Theme，`Theme.of` 取到的就不是 `AppTheme` 那份，缓存会失效或串色 | 明确「谁是 token 源」：建议新系统替换 `M3EBridge` 位置，`AppTheme` 保留为 Material 兜底 |
| R14 | **设置页两级缓存清理** | `settings_screen.dart:33-66` | 必须同时清 `PageCache` + `app.chapters`；只清图片会导致「章节列表还在、图片全丢」的假象 | 保留成对调用；SnackBar 文案保持 |
| R15 | **M3EButton 双写法** | `settings_screen.dart:46`（`child:`）vs 其它（`label:`） | 迁移时容易漏掉其中一种；两者渲染结果不同（`label` 常带 icon 布局） | 迁移前统一成一种 |
| R16 | **测试即契约** | 6 个测试文件 | `account_tab_test`（4 个 label + `M3ENavigationBar` 类型 + 文案）、`album_open_transition_test`（`M3ECard` 类型）、`notifications_test`（`SelectableText` 类型 + 文案）、`comic_history_test`（`TextField` + `AlbumDetailScreen` 类型）、`settings_cache_test`（`FilledButton`/`TextButton` 类型 + 文案） | 改造前先把这些断言列成验收清单；换组件类型时必须同步改测试，否则无法判断「行为是否等价」 |
| R17 | **硬编码尺寸常量散落** | `190` / `0.52` 出现在 5 个文件（home:257-261, album_list:183-187, album_detail:238-242, account_albums:127-133, week:153-157）；`210` 横滑高度 3 处；`148`/`48` 在 `discover_search_bar` | 新皮肤改卡片比例/字号时，5 处必须同步，否则「某页多 1px 溢出」（`account_albums:131` 注释已踩过） | 建议新 UI 抽成统一 token（`GridSpec`），但**属于新代码**，不在本次清点范围 |

---

## 6. 页面跳转关系与路由方式

### 6.1 全部跳转（16 处 push）

| # | 起点 | 终点 | 触发 | 路由方式 | 转场 | 代码位置 |
|---:|---|---|---|---|---|---|
| 1 | `StartScreen` | `RootShell` | 选中线路成功且 `app.ready` | `Navigator.pushReplacement(MaterialPageRoute)` | Material 默认（Android = 预测式返回） | `start_screen.dart:43-45` |
| 2 | 任意页 → 详情 | `AlbumDetailScreen` | 点 `OpenableAlbumCard` | `M3ECard.openBuilder` → **容器变换**（M3E 内部 Route） | 卡片矩形→全屏（弹簧） | `openable_album.dart:32` |
| 3 | 横向小卡 | `AlbumDetailScreen` | 点 `OpenableAlbumTileCompact` | 同上 | 同上 | `openable_album.dart:59` |
| 4 | 列表行 | `AlbumDetailScreen` | 点 `OpenableAlbumListTile`（搜索结果） | 同上 | 同上 | `openable_album.dart:83` |
| 5 | 首页搜索栏 / 搜索面板 | `AlbumDetailScreen` | 输入或点选 JM 号 | `M3ECardContainerTransform.show(origin: GlobalKey 矩形)` | 容器变换（起点=真实控件） | `album_open_transition.dart:38-45`；调用点 `home_screen.dart:74`、`search_panel.dart:146` |
| 6 | `HomeScreen` | `WeekScreen` | 点 AppBar 榜单图标 | `MaterialPageRoute` | 默认 | `home_screen.dart:135-137` |
| 7 | `HomeScreen` | `LatestListScreen` | 「最新更新」的「更多」 | `MaterialPageRoute` | 默认 | `home_screen.dart:181-186` |
| 8 | `HomeScreen` | `PromoteListScreen` | 推荐板块的「更多」 | `MaterialPageRoute` | 默认 | `home_screen.dart:221-229` |
| 9 | `LibraryScreen` | `PagedAlbumScreen`（分类/子分类） | 点「浏览全部」/ 子分类 chip | `MaterialPageRoute` | 默认 | `library_screen.dart:43-58` |
| 10 | `LibraryScreen` | `PagedAlbumScreen`（随机推荐） | 点快捷卡 | `MaterialPageRoute` | 默认 | `library_screen.dart:63-81` |
| 11 | `LibraryScreen` | `WeekScreen` | 点「每周必看」 | `MaterialPageRoute` | 默认 | `library_screen.dart:138-140` |
| 12 | `WeekScreen` | `_WeekDetailScreen` | 点某一期 | `MaterialPageRoute` | 默认 | `week_screen.dart:37-41` |
| 13 | `AccountScreen` | `AccountAlbumsScreen` | 收藏/历史/关注 | `MaterialPageRoute` | 默认 | `account_screen.dart:74-82` |
| 14 | `AccountScreen` | `NotificationsScreen` | 站内通知 | `MaterialPageRoute` | 默认 | `account_screen.dart:295-297` |
| 15 | `AlbumDetailScreen` | `ReaderScreen` | 「观看漫画」按钮 | `Navigator.push(PageRouteBuilder)` | **圆形揭示**：`ClipPath(_CircleRevealClipper)` + `Transform.scale(1.06→1.0, alignment=按钮中心)`，`Durations.long2` 进/出对称 | `album_detail_screen.dart:107-120, 475-543` |
| 16 | `ReaderScreen` | 返回上一页 | 顶栏返回按钮 | `Navigator.maybePop()` | 反向播放圆形揭示 | `reader_screen.dart:205` |

### 6.2 非路由的「页面切换」

| 机制 | 位置 | 说明 |
|---|---|---|
| `IndexedStack` 页签切换 | `root_shell.dart:49-55` | 4 个主页面互不 push，靠 `M3ENavigationBar.onDestinationSelected` 改 index |
| `AnimatedSwitcher` 面板切换 | `home_screen.dart:141-151` | 同一个 Scaffold 内「推荐流 ↔ 搜索面板」用 `KeyedSubtree` + ValueKey 切换，非路由 |
| `showDialog<bool>` | `account_screen.dart:86-103`（退出）、`settings_screen.dart:35-52`（清缓存） | `AlertDialog` + `M3EButton` |
| `showModalBottomSheet` + `DraggableScrollableSheet` | `notifications_screen.dart:53-92` | 通知全文 |
| `ExpansionTile` 展开 | `library_screen.dart:159-207` | 分类展开子分类 |
| `AnimatedSize` 展开 | `comment_section.dart:114-128` | 写评论面板 |

### 6.3 路由方式结论

- **无命名路由、无 `onGenerateRoute`、无自定义 `Route` 子类**。
- 常规跳转 = `MaterialPageRoute`（10 处）。
- 特殊转场 = 2 套，且都由组件内部完成：
  1. M3E 容器变换（打开详情，5 处入口）；
  2. 手写 `PageRouteBuilder` + 圆形裁剪（详情→阅读器）。
- 全局返回观感由 `AppTheme` 的 `pageTransitionsTheme: {android: PredictiveBackPageTransitionsBuilder()}` 决定（`app_theme.dart:34-38`）。
- **改造含义**：新设计系统若提供自己的 `PageTransitionsBuilder`/`Route`，只需替换 3 处（`app_theme` 的 transitions、`openable_album` 的 3 个组件、`album_open_transition` 的函数），其余 10 处 `MaterialPageRoute` 可批量替换。

---

## 7. 按依赖关系排序的改造批次建议

### 7.1 依赖图（`A → B` 表示 B 依赖 A 的 API）

```
[theme/prism_theme.dart]（新 token 源：PrismTheme / PrismBridge / SurfaceScope）  ← 谁都依赖
[theme/app_theme.dart + m3e_bridge.dart]（旧 token 源，迁移期保留兜底）
        │
[widgets/common.dart]（CoverImage / LoadingView / ErrorView / EmptyView / SectionHeader）
        │
[widgets/album_card.dart]（3 个 *Content：纯内容，无外壳）
        │
[widgets/openable_album.dart]（3 个可点卡片壳）──→ 所有列表页
        │
[widgets/album_open_transition.dart]（JM 号直达转场）
        │
[screens/album_list_screen.dart]（PagedAlbumScreen 泛型分页）
        │                    │
   [library_screen]     [home_screen]
        │                    │
        └──→ [week_screen]   ├──→ [discover_search_bar]
                             └──→ [search_panel]

[widgets/comment_section.dart] ──→ [album_detail_screen] ──→ [reader_screen]
                                        ↑
                              openable_album / album_open_transition

[root_shell.dart] ──→ home / library / account / settings
[start_screen.dart] ──→ root_shell
```

### 7.2 批次表

| 批次 | 内容（文件） | 前置依赖 | 可并行数 | 风险 | 验收点 |
|---|---|---|---|---|---|
| **B0 基线固化**（不动代码） | 无源文件改动；产出：①新旧 token 映射表（§3.4/§3.6）②14 张页面截图基线③把 §5-R16 的测试断言抄成验收清单④确认目标设计系统 → **已确认：`prism_ui`，见 §0.2** | — | — | 低 | 能对每个页面说出「输入→状态→输出」三件事 |
| **B1 基础原子层** ⭐关键路径 | `theme/app_theme.dart`、`theme/m3e_bridge.dart`（替换成新系统的 Theme 注入）、`widgets/common.dart`、`widgets/album_card.dart`（3 个 `*Content` 保持不变，只改内部排版/字号） | B0 | 2 人（theme 1 人 / common+card 1 人） | 中 | 全局换色/换字号后：`LoadingView`/`ErrorView`/`EmptyView`/`CoverImage`/`SectionHeader` 在 9 个页面里观感一致；`auto` 主题切换不闪 |
| **B2 共享卡片壳 + 导航 + 分页框架** ⭐关键路径 | `widgets/openable_album.dart`、`widgets/album_open_transition.dart`、`screens/album_list_screen.dart`、`screens/root_shell.dart`、`screens/start_screen.dart` | B1 | 2 人（卡片壳+转场 1 人 / 分页骨架+壳+起始页 1 人，但**壳的 API 必须先定**） | **中高** | 卡片→详情的转场四端（grid/compact/list/JM 直达）一致；4 个页签切换不重建、不丢状态；起始页测速渐进更新；`album_open_transition_test` 通过 |
| **B3 并行低风险页**（可 4 路并行） | ①`screens/notifications_screen.dart` ②`screens/account_albums_screen.dart` ③`screens/week_screen.dart` ④`screens/library_screen.dart` ⑤`screens/settings_screen.dart` | B1 + B2（卡片壳 API、`M3EAppBar` 替代品） | **5 人并行** | 低 | 每页四态（loading/empty/error/data）+ 下拉刷新 + 上拉分页；`settings_cache_test`、`notifications_test` 通过或已等价改写 |
| **B4 强耦合业务页**（可 2 路并行） | A：`screens/account_screen.dart`；B：`screens/home_screen.dart` + `widgets/discover_search_bar.dart` + `widgets/search_panel.dart`（**三者必须同一人/同一批**） | B1 + B2（B 还依赖 `PagedAlbumScreen` 的 `LatestListScreen`/`PromoteListScreen`） | 2 人 | 中高 | 登录态切换两套布局 + 底栏文案联动；搜索展开/收起/失焦/JM 直达/历史热词 5 条路径；`account_tab_test`、`comic_history_test` 通过 |
| **B5 最高风险页**（最后做，串行评审） | ①`screens/album_detail_screen.dart` + `widgets/comment_section.dart`（**同一批**：详情页骨架 + 评论面板折叠 + 转场锚点）②`screens/reader_screen.dart`（可与①并行开发，但**转场合并必须同一人验证**） | B1 + B2（B2 的卡片壳决定详情页入口；`_watchKey` 决定阅读器转场） | 2 人 + 1 评审 | **高** | 详情页：封面比例/折叠/收藏关注 SnackBar/评论分页/发评论重拉/相关推荐；阅读器：缓存优先、逐页释放引用、进度条、点屏切 bars、失败重试、预取；连续进出阅读器 10 次内存不涨 |

### 7.3 并行/串行约束（硬规则）

| 约束 | 原因 |
|---|---|
| `theme/*` 必须在任何人动手前冻结 | 所有人都在 `Theme.of` + `scheme.*` 上取色；token 一改全部返工 |
| `openable_album.dart` + `album_open_transition.dart` 必须先于任何列表页 | 5 个列表页（home/library/week/account_albums/album_list/album_detail 的相关推荐）都用它；API 变了要全量改调用点 |
| `PagedAlbumScreen` 必须先于 `library_screen` 与 `home_screen` | 两者都直接构造它（`library_screen.dart:45,65`、`home_screen` 的 `LatestListScreen`/`PromoteListScreen`） |
| `home_screen` + `discover_search_bar` + `search_panel` 不可拆给不同人 | 展开态是父级状态、`GlobalKey` 在父级、时序靠 `addPostFrameCallback`；拆开必冲突 |
| `album_detail_screen` + `comment_section` 不可拆 | 评论区是详情页的一个 sliver 子节点，折叠面板与外层滚动强耦合 |
| `reader_screen` 最后合并 | 依赖详情页给出的转场，且图片管线是唯一会「泄漏内存/崩溃」的模块 |
| `data/` 与 `core/` 禁止任何批次改动 | 见 §4；若新设计系统需要 `ThemeMode` 之外的枚举，只在 `AppState`/`theme` 层适配 |

### 7.4 建议工时权重（按行数 × 风险系数，仅供排期）

| 页面/模块 | 行数 | 风险系数 | 权重 |
|---|---:|---:|---:|
| `comment_section.dart` | 645 | 1.4 | 903 |
| `album_detail_screen.dart` | 543 | 1.5 | 815 |
| `reader_screen.dart` | 389 | 1.5 | 584 |
| `start_screen.dart` | 357 | 1.2 | 428 |
| `account_screen.dart` | 350 | 1.0 | 350 |
| `home_screen.dart` + 搜索三件套（288+240+289） | 817 | 1.2 | 980 |
| `album_list_screen.dart` | 278 | 1.0 | 278 |
| `library_screen.dart` | 248 | 0.9 | 223 |
| `common.dart` | 244 | 1.1 | 268 |
| `settings_screen.dart` | 212 | 0.8 | 170 |
| `album_card.dart` | 196 | 0.9 | 176 |
| `week_screen.dart` | 169 | 0.8 | 135 |
| `notifications_screen.dart` | 157 | 0.8 | 126 |
| `account_albums_screen.dart` | 151 | 0.8 | 121 |
| `root_shell.dart` | 86 | 1.0 | 86 |
| `openable_album.dart` + `album_open_transition.dart` | 133 | 1.3 | 173 |
| `theme/*` | 105 | 1.2 | 126 |

> 结论：**B5 的两个模块（`comment_section` + `album_detail` + `reader` = 1577 行）占了改造成本约 1/4**，应最后做、单独评审。

---

## 附录 A：现有测试对 UI 的约束（改造即契约）

| 测试文件 | 断言的 UI 事实 | 改造影响 |
|---|---|---|
| `test/account_tab_test.dart` | `find.byType(M3ENavigationBar)`；4 个 label `['发现','书库','登录','设置']` → 登录后 `['发现','书库','我的','设置']`；文案「禁漫账号」「账号 / 邮箱」「密码」「UID 42」；`find.widgetWithText(M3EButton,'退出登录')`；设置页无「账号」分组、有「页图缓存」 | **必崩**（依赖 M3E 类型 + 具体文案） |
| `test/album_open_transition_test.dart` | `find.byType(M3ECard)` 存在；点 `M3ECard` 后 200ms 内出现 `AlbumDetailScreen`；`openAlbumPreviewFromCenter` 也能打开详情 | **必崩**（容器变换若换实现） |
| `test/notifications_test.dart` | 标题/正文/时间文案；点开详情后 `find.byType(SelectableText)` | 若全文弹层不用 `SelectableText` 则崩 |
| `test/comic_history_test.dart` | 点 `TextField` 展开搜索；点历史 chip `JM1488098` → 出现 `AlbumDetailScreen`；普通词「催眠」→ **不**出现详情 | 依赖搜索分流逻辑，是行为契约 |
| `test/settings_cache_test.dart` | 「缓存」「页图缓存」「暂无缓存」文案；点「清理」→ 弹窗确认文案；`find.widgetWithText(FilledButton,'清理')`、`(TextButton,'取消')`；SnackBar「缓存已清理」 | 依赖 M3EButton 内部渲染类型 |
| 其余 12 个测试 | 纯 `core/`/`data/` 逻辑（网关、缓存、解密、设置持久化等） | **不受 UI 改造影响**（这 12 个必须始终绿） |

## 附录 B：改造前需要产品/设计确认的 4 个问题

1. ~~新设计系统是 `packages/prism_ui` 还是另选？~~ **已确认 = `prism_ui`**（`lib/theme/prism_theme.dart` 已落地，见 §0.2）。待确认的是：`material_3_expressive` 何时从 pubspec 移除、`M3E*` 组件是否一次性全删。
2. 「卡片→详情」是否保留容器变换？`prism_ui` 有 `open_container.dart`/`card_surface.dart`/`page_transition.dart`/`deferred_push.dart`/`route_motion_hold.dart`，需确认新方案与现 `M3ECard` 的观感差异是否可接受。
3. 阅读器是否仍为「纵向连续滚动」？若要加左右翻页/双击缩放，属于**新增功能**，不属于 UI 改写，需单独排期（当前 0 处 `PageView`/`InteractiveViewer`）。
4. 图标体系：当前 76 处 `Icons.*`（Material Icons 字体，`uses-material-design: true`）；`prism_ui` 自带 `icons/glyph.dart`/`glyphs.dart`/`glyph_icon.dart` 体系。换图标是**全覆盖替换**，需先出 `Icons.* → Glyph` 映射表，并决定是否保留 `uses-material-design`。

> 已无障碍项：主题是否仍跟随系统 —— `PrismTheme.of(Brightness)` + `SurfaceScope` 已覆盖，`ThemeMode` 只需在 `AppState`/`theme` 层适配，`core/settings_store.dart` 不动。

---

*文档结束。所有行数为 `Get-Content` 实测；所有频次为正则全量统计（`lib/` 33 文件 / 7841 行）。*
