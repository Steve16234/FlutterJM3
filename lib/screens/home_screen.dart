import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/comic_query.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/section.dart';
import '../ui/states.dart';
import '../ui/top_bar.dart' show GlassIconButton;
import '../widgets/album_open_transition.dart';
import '../widgets/discover_search_bar.dart';
import '../widgets/openable_album.dart';
import '../widgets/search_panel.dart';
import 'album_list_screen.dart';
import 'week_screen.dart';

/// 首页（发现页）：顶部可伸缩搜索栏 + 推荐板块 + 最新更新 + 每周连载。
///
/// 搜索不再单独占一页：点顶部搜索胶囊会按 MD3 动效拉长成填充胶囊，
/// **内容区整块换成搜索面板**（历史 / 热词 / 结果），不是路由跳转。
///
/// 表现层是 prism_ui（`JmPage` + 套件三态 + `AlbumCard` / `AlbumTileCompact`），
/// 数据流与交互时序与迁移前一致：
///
/// * 进页面就 `_load()`（`ensureReady` → `promote/latest/serialization` 三请求并发）；
/// * 提交搜索时作品号走「先打开详情页、下一帧再收起搜索框」；
/// * 卡片点击仍是 prism 的容器变换（`OpenableAlbumCard` 等）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  Future<_HomeData>? _future;

  /// 最近一次成功的数据。刷新失败时回退到它，不清空已有内容（规约 §5）。
  _HomeData? _data;

  /// bar 底部那条刷新进度条（`JmPage.loading`）；没有下拉刷新。
  final ValueNotifier<bool> _refreshing = ValueNotifier<bool>(false);

  final TextEditingController _searchInput = TextEditingController();
  bool _searchExpanded = false;
  String? _searchQuery;
  int _searchNonce = 0;

  /// 搜索栏的位置，用于作品号直达时从搜索框长出来。
  final GlobalKey _searchBarKey = GlobalKey();

  /// 推荐位横滑条的高度（旧实现的 210，卡片内是 3:4 封面 + 两行标题）。
  static const double _promoteStripHeight = 210;

  /// 悬浮搜索框占据的垂直空间（barHeight 48 + 下方 12 留白）。
  /// 玻璃浮在推荐流之上，推荐流顶部要留出这段，首屏内容才不被胶囊盖住。
  static const double _searchOverlayHeight = 60;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void dispose() {
    _searchInput.dispose();
    _refreshing.dispose();
    super.dispose();
  }

  /// 展开 / 收起搜索：收起时清空搜索态，回到推荐流。
  void _setSearchExpanded(bool expanded) {
    if (_searchExpanded == expanded) return;
    setState(() {
      _searchExpanded = expanded;
      if (!expanded) {
        _searchInput.clear();
        _searchQuery = null;
      }
    });
  }

  void _submitSearch(String keyword) {
    // 输入作品号（`1488098` / `JM1488098`）直接打开作品页，不再走搜索结果。
    final albumId = albumIdFromQuery(keyword);
    if (albumId != null) {
      context.read<AppState>().addSearchHistory(keyword.trim());
      // 顺序很重要：先开作品页，收起搜索另起一帧。
      // 并行的话「搜索框缩短 + 面板淡出 + 作品页展开」三套动画同时推，
      // 画面会一起乱动。
      openAlbumPreviewFromCenter(
        context,
        albumId: albumId,
        originKey: _searchBarKey,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setSearchExpanded(false);
      });
      return;
    }

    setState(() {
      _searchQuery = keyword;
      _searchNonce++;
    });
  }

  Future<_HomeData> _load() async {
    final client = context.read<AppState>().client;
    await client.ensureReady();

    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      client.promote(),
      client.latest(),
      client.serialization(),
    ]);

    final data = _HomeData(
      sections: (results[0] as List)
          .whereType<Map>()
          .map((e) => PromoteSection.fromJson(e.cast<String, dynamic>()))
          .toList(),
      latest: (results[1] as List)
          .whereType<Map>()
          .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
          .toList(),
      serialization: PagedAlbums.fromJson(results[2] as Map<String, dynamic>),
    );
    _data = data;
    return data;
  }

  /// 刷新（bar 上的动作；prism 没有下拉刷新）。
  ///
  /// 已经有数据时刷失败**不清空**列表：回退到上一次的结果 + banner 提示。
  Future<void> _refresh() async {
    final previous = _data;
    _refreshing.value = true;
    setState(() => _future = _load());
    try {
      await _future;
    } catch (error) {
      if (!mounted) return;
      if (previous != null) {
        setState(() => _future = Future<_HomeData>.value(previous));
        BannerHost.maybeOf(context)?.show(
          '刷新失败：$error',
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) _refreshing.value = false;
    }
  }

  void _openWeek() => BaseNavigator.push<void>(context, const WeekScreen());

  /// 「最新更新」的「更多」：同一个接口按页取，跳通用分页列表。
  void _openLatest() {
    BaseNavigator.push<void>(
      context,
      PagedAlbumScreen(
        title: '最新更新',
        asGrid: true,
        loader: (page) async {
          final list = await context.read<AppState>().client.latest(page: page);
          return PagedAlbums(
            items: list
                .whereType<Map>()
                .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
                .toList(),
            // 该接口不给 total，用「本页是否为空」判断到底（见 PagedAlbumScreen）。
            total: 0,
            page: page,
          );
        },
      ),
    );
  }

  /// 推荐板块的「更多」：按板块的 `filter_val`（缺省用 id）分页。
  void _openPromote(PromoteSection section) {
    final id = section.filterValue.isNotEmpty
        ? section.filterValue
        : section.id;
    BaseNavigator.push<void>(
      context,
      PagedAlbumScreen(
        title: section.title,
        asGrid: true,
        loader: (page) async {
          final list = await context.read<AppState>().client.promoteList(
            id,
            page: page,
          );
          return PagedAlbums(
            items: list
                .whereType<Map>()
                .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
                .toList(),
            total: 0,
            page: page,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();

    return JmPage(
      // 去掉传统「发现」标题顶栏：顶部改成一行独立的 iOS 26 玻璃控件，
      // 由下面 body 里的 _topControls 自己排布，避免和顶栏重叠互相点不到。
      showBar: false,
      body: Builder(
        builder: (context) {
          final topInset = MediaQuery.paddingOf(context).top;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AnimatedSlide(
                duration: midDuration,
                curve: _searchExpanded ? Curves.easeInOutCubic : Curves.easeOut,
                offset: _searchExpanded ? const Offset(0, 1) : Offset.zero,
                child: IgnorePointer(
                  ignoring: _searchExpanded,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('home-feed'),
                    child: _feed(app),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: midDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                // 面板从下方轻微上滑（收起时向下滑出），配合淡入淡出。
                // 位移刻意保持很小：保证面板立刻就在屏内可点（测试里展开后
                // 只 pump 一帧也能点到历史 chip），「让位」的主动作交给推荐流下滑。
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _searchExpanded
                    ? Padding(
                        // 面板内容从搜索控件下方开始：状态栏让位 + 控件行占位。
                        padding: EdgeInsets.only(
                          top: topInset + _searchOverlayHeight,
                        ),
                        child: DiscoverSearchPanel(
                          key: const ValueKey<String>('search-panel'),
                          query: _searchQuery,
                          searchNonce: _searchNonce,
                          onKeywordSelected: (keyword) =>
                              _searchInput.text = keyword,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('none')),
              ),
              // 顶部一行：搜索胶囊（6/9）+ 刷新 + 日历（各 1.5/9），
              // 三者是彼此独立的玻璃控件，互不遮挡。
              Positioned(
                top: topInset,
                left: 16,
                right: 16,
                child: _topControls(),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 顶部控件行：三个彼此独立的 iOS 26 玻璃控件，聚成紧凑的一组。
  /// 搜索胶囊占大头（吃掉剩余空间），刷新、日历两个圆钮紧跟其后、彼此靠近，
  /// 不像之前那样用 Expanded 槽位把它们推到屏幕两端。
  /// 下方挂一条细刷新进度条。
  Widget _topControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: DiscoverSearchBar.barHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 搜索胶囊：吃掉除两枚圆钮之外的全部宽度。
              Expanded(
                child: DiscoverSearchBar(
                  key: _searchBarKey,
                  controller: _searchInput,
                  expanded: _searchExpanded,
                  fillWidth: true,
                  onExpandedChanged: _setSearchExpanded,
                  onSubmitted: _submitSearch,
                ),
              ),
              // 圆钮紧凑跟随，间距统一 8dp（iOS 26 工具栏组内间距）。
              const SizedBox(width: 8),
              GlassIconButton(
                glyph: AppGlyphs.refresh,
                tooltip: '刷新',
                onPressed: _refresh,
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                glyph: AppGlyphs.calendar,
                tooltip: '每周必看',
                onPressed: _openWeek,
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _refreshing,
          builder: (_, active, _) => SizedBox(
            height: LoadingBar.extent,
            child: LoadingBar(active: active),
          ),
        ),
      ],
    );
  }

  /// 推荐流：连接态错误 → 整页错误；数据未到 → 加载；否则渲染内容。
  Widget _feed(AppState app) {
    if (!app.ready && app.error != null) {
      return JmError(message: app.error!, onRetry: app.bootstrap);
    }
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        // 刷新中（future 换了但上一次的数据还在）继续显示旧内容，不闪 Loading。
        final data = snapshot.data ?? _data;
        if (data == null) {
          if (snapshot.hasError) {
            return JmError(message: '${snapshot.error}', onRetry: _refresh);
          }
          return const JmLoading(label: '正在连接线路…');
        }
        return _content(data, app.imgHost);
      },
    );
  }

  Widget _content(_HomeData data, String imgHost) {
    return CustomScrollView(
      slivers: <Widget>[
        // 顶部留出悬浮玻璃搜索框的空间：初始时内容在玻璃下方，向上滚动时
        // 卡片会从玻璃背后滑过，prism 每帧重采样 → 实时折射（液态观感）。
        const SliverToBoxAdapter(
          child: SizedBox(height: _searchOverlayHeight),
        ),
        for (final section in data.sections)
          if (section.items.isNotEmpty) _promoteSection(section, imgHost),
        if (data.latest.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '最新更新',
              action: TextButton(
                onPressed: _openLatest,
                child: const Text('更多'),
              ),
            ),
          ),
          _albumGrid(data.latest, imgHost),
        ],
        // 「每周连载」在原实现里就没有「更多」入口（`serialization` 是单页板块），
        // 这里保持原样，不新增入口。
        if (data.serialization.items.isNotEmpty) ...<Widget>[
          const SliverToBoxAdapter(child: SectionHeader(title: '连载更新')),
          _albumGrid(data.serialization.items, imgHost),
        ],
        // 底部留出浮动 dock 的高度（`context.bottomInset`，不写死数字）。
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + context.bottomInset),
        ),
      ],
    );
  }

  /// 推荐板块：小标题 + 横滑小卡。
  ///
  /// 小卡用 [OpenableAlbumTileCompact]：套件目前只有网格卡（`AlbumCard`）与列表行
  /// （`AlbumListTile`），没有「横滑 mini 卡」形态，那个组件就是按同一套 token
  /// 写的补齐件（封面 3:4、圆角 `AppCorner.lg`、prism 容器变换）。
  Widget _promoteSection(PromoteSection section, String imgHost) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: section.title,
            action: TextButton(
              onPressed: () => _openPromote(section),
              child: const Text('更多'),
            ),
          ),
          SizedBox(
            height: _promoteStripHeight,
            child: PrismListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gap: 12,
              itemCount: section.items.length,
              itemBuilder: (context, index) => OpenableAlbumTileCompact(
                album: section.items[index],
                imgHost: imgHost,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 网格分区（最新更新 / 连载更新）。比例 0.52 与旧实现一致，别改。
  Widget _albumGrid(List<AlbumSummary> albums, String imgHost) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.52,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => OpenableAlbumCard(
            album: albums[index],
            imgHost: imgHost,
          ),
          childCount: albums.length,
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.sections,
    required this.latest,
    required this.serialization,
  });

  final List<PromoteSection> sections;
  final List<AlbumSummary> latest;
  final PagedAlbums serialization;
}
