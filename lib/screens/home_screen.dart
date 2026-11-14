import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/comic_query.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/album_open_transition.dart';
import '../widgets/common.dart';
import '../widgets/discover_search_bar.dart';
import '../widgets/openable_album.dart';
import '../widgets/search_panel.dart';
import 'album_list_screen.dart';
import 'week_screen.dart';

/// 首页：顶部搜索栏 + 推荐板块 + 最新更新 + 每周连载。
///
/// 搜索不再单独占一页：点击顶部小搜索框会按 MD3 动效拉长铺满 bar，
/// 页面内容切换为搜索面板（历史 / 热词 / 结果）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  Future<_HomeData>? _future;

  final TextEditingController _searchInput = TextEditingController();
  bool _searchExpanded = false;
  String? _searchQuery;
  int _searchNonce = 0;

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
      _setSearchExpanded(false);
      openAlbumPreviewFromCenter(context, albumId: albumId);
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

    return _HomeData(
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
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();

    return Scaffold(
      // 收起态：标题 + 小搜索框；展开态：搜索框拉长铺满整条 bar。
      // 搜索框本身仍是自绘的（伸缩交互太多），只把外壳换成 M3EAppBar。
      appBar: M3EAppBar.top(
        automaticallyImplyLeading: false,
        title: DiscoverSearchBar(
          controller: _searchInput,
          expanded: _searchExpanded,
          onExpandedChanged: _setSearchExpanded,
          onSubmitted: _submitSearch,
          onOpenWeek: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const WeekScreen()),
          ),
        ),
      ),
      body: _searchExpanded
          ? DiscoverSearchPanel(
              query: _searchQuery,
              searchNonce: _searchNonce,
              onKeywordSelected: (keyword) => _searchInput.text = keyword,
            )
          : (!app.ready && app.error != null
              ? ErrorView(message: app.error!, onRetry: app.bootstrap)
              : FutureBuilder<_HomeData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: '正在连接线路…');
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  );
                }
                final data = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    slivers: <Widget>[
                      for (final section in data.sections)
                        if (section.items.isNotEmpty)
                          _sectionSliver(section, app.imgHost),
                      if (data.latest.isNotEmpty) ...<Widget>[
                        SliverToBoxAdapter(
                          child: SectionHeader(
                            title: '最新更新',
                            onMore: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const LatestListScreen(),
                              ),
                            ),
                          ),
                        ),
                        _albumGrid(data.latest, app.imgHost),
                      ],
                      if (data.serialization.items.isNotEmpty) ...<Widget>[
                        const SliverToBoxAdapter(
                          child: SectionHeader(title: '连载更新'),
                        ),
                        _albumGrid(data.serialization.items, app.imgHost),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                );
              },
            )),
    );
  }

  Widget _sectionSliver(PromoteSection section, String imgHost) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: section.title,
            onMore: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PromoteListScreen(
                  id: section.filterValue.isNotEmpty
                      ? section.filterValue
                      : section.id,
                  title: section.title,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final album = section.items[index];
                return OpenableAlbumTileCompact(
                  album: album,
                  imgHost: imgHost,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
          (context, index) {
            final album = albums[index];
            return OpenableAlbumCard(
              album: album,
              imgHost: imgHost,
            );
          },
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
