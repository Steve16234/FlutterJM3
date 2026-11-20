import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/comic_query.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/section.dart';
import '../ui/states.dart';
import '../widgets/album_open_transition.dart';
import '../widgets/openable_album.dart';

/// 「发现」页内的搜索面板（prism 版）：搜索历史 + 热门标签（landing）与结果分页。
///
/// 不单独占一页，而是「发现」页的一块内容：由顶部搜索栏的展开态切换进来。
/// 数据流（热门标签、搜索分页、搜索历史读写、JM 号分流）与迁移前完全一致，
/// 这里只换表现层：
///
/// * 历史 / 热词是一组胶囊 chip：历史用 prism 的 [Chip] 逐个挂 [GlobalKey]
///   （作品号 chip 是「详情页容器变换」的起点，必须逐条有 key）；热词走套件的
///   [TagWrap]；
/// * 三种状态用套件的 [JmLoading] / [JmError] / [JmEmpty] 与 prism 的
///   [NullStatus]（搜索无结果用 prism 自带的「没有搜索结果」插图）；
/// * 结果行是 [OpenableAlbumListTile]（内部就是套件的 `AlbumListTile` + prism 的
///   容器变换），列表用 [PrismListView]。
class DiscoverSearchPanel extends StatefulWidget {
  const DiscoverSearchPanel({
    super.key,
    required this.query,
    required this.searchNonce,
    this.onKeywordSelected,
  });

  /// 要搜索的关键词；为 null 时展示搜索历史 / 热门标签。
  final String? query;

  /// 每次提交搜索自增，用于区分「同一个词再次搜索」。
  final int searchNonce;

  /// 点击历史 / 热词时回调，父级可同步填充搜索框。
  final ValueChanged<String>? onKeywordSelected;

  @override
  State<DiscoverSearchPanel> createState() => _DiscoverSearchPanelState();
}

class _DiscoverSearchPanelState extends State<DiscoverSearchPanel> {
  final ScrollController _scroll = ScrollController();

  /// 每枚 chip 的转场起点。旧实现每次 build 现造 `GlobalKey`，同一枚 chip 每帧
  /// 换 key（元素被反复重建）；这里按文案缓存一枚，语义不变、重建更少。
  final Map<String, GlobalKey> _historyKeys = <String, GlobalKey>{};

  List<dynamic> _hotTags = const <dynamic>[];
  final List<AlbumSummary> _results = <AlbumSummary>[];

  String _keyword = '';
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _searched = false;
  String? _error;

  GlobalKey _originKeyOf(String keyword) =>
      _historyKeys.putIfAbsent(keyword, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadHotTags();
    final query = widget.query;
    if (query != null) _search(query);
  }

  @override
  void didUpdateWidget(DiscoverSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.query;
    if (query == null) return;
    if (query != oldWidget.query ||
        widget.searchNonce != oldWidget.searchNonce) {
      _search(query);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 480 &&
        _results.length < _total) {
      _search(_keyword, append: true);
    }
  }

  Future<void> _loadHotTags() async {
    try {
      final client = context.read<AppState>().client;
      final tags = await client.hotTags();
      if (!mounted) return;
      setState(() => _hotTags = tags);
    } catch (_) {
      // 热门标签失败不影响搜索。
    }
  }

  Future<void> _search(String keyword, {bool append = false}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    if (!append) {
      setState(() {
        _keyword = trimmed;
        _results.clear();
        _page = 0;
        _total = 0;
        _searched = true;
        _error = null;
      });
      // `_search` 也会从 `didUpdateWidget` 调到（build 阶段），此时
      // `notifyListeners` 会报 markNeedsBuild during build，所以延后一帧。
      final app = context.read<AppState>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        app.addSearchHistory(trimmed);
      });
    }

    setState(() => _loading = true);

    try {
      final client = context.read<AppState>().client;
      final next = _page + 1;
      final json = await client.search(trimmed, page: next);
      final paged = PagedAlbums.fromJson(json, page: next);
      if (!mounted) return;
      setState(() {
        _page = next;
        _total = paged.total;
        _results.addAll(paged.items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _pick(String keyword, {GlobalKey? originKey}) {
    // 历史 / 热词里的作品号（`1488098` / `JM1488098`）也要直达作品页，
    // 不能当成关键词去搜。
    final albumId = albumIdFromQuery(keyword);
    if (albumId != null) {
      // 这里不能先回调 `onKeywordSelected`：它会把搜索框填上 JM 号，
      // 用户从作品页返回时看到的是一个被改过的搜索框，却并没有搜索过。
      openAlbumPreviewFromCenter(
        context,
        albumId: albumId,
        originKey: originKey,
      );
      return;
    }

    widget.onKeywordSelected?.call(keyword);
    _search(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // 面板滑入期间推荐流还在下方过渡（不是整块替换），必须给一块不透明
    // 的页面底色，否则两个列表的文字会透过对方叠在一起。
    return ColoredBox(
      color: context.colorScheme.surface,
      child: _searched ? _buildResults(app.imgHost) : _buildLanding(app),
    );
  }

  Widget _buildLanding(AppState app) {
    final history = app.searchHistory;

    return ListView(
      // 底部留出浮动 dock 的高度（`context.bottomInset`，不写死数字）。
      padding: EdgeInsets.only(bottom: 24 + context.bottomInset),
      children: <Widget>[
        if (history.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '搜索历史',
            action: TextButton(
              onPressed: app.clearSearchHistory,
              child: const Text('清空'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final keyword in history)
                  Chip(
                    key: _originKeyOf(keyword),
                    label: keyword,
                    onPressed: () =>
                        _pick(keyword, originKey: _originKeyOf(keyword)),
                  ),
              ],
            ),
          ),
        ],
        if (_hotTags.isNotEmpty) ...<Widget>[
          const SectionHeader(title: '热门标签'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 热词只是关键词（不做作品号直达的转场起点），直接走套件的标签云。
            child: TagWrap(
              tags: _hotTags.map(_tagName).toList(growable: false),
              onTagPressed: _pick,
            ),
          ),
        ],
        if (history.isEmpty && _hotTags.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: JmEmpty(message: '输入关键词开始搜索'),
          ),
      ],
    );
  }

  /// 热门标签可能是字符串或对象，两种都兼容。
  String _tagName(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      for (final key in const <String>['name', 'tag', 'title', 'value']) {
        final v = raw[key];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return '';
  }

  Widget _buildResults(String imgHost) {
    if (_results.isEmpty && _loading) {
      return const JmLoading(label: '搜索中…');
    }
    if (_results.isEmpty && _error != null) {
      return JmError(message: _error!, onRetry: () => _search(_keyword));
    }
    if (_results.isEmpty) {
      // 搜索无结果用 prism 自带的「没有搜索结果」插图，不要手写空态。
      return const NullStatus(
        label: '没有找到相关结果',
        description: '换个关键词，或直接输入 JM 号直达。',
        illustration: Illustration.search,
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  '“$_keyword”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '约 $_total 个结果',
                maxLines: 1,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: PrismListView(
            controller: _scroll,
            // 底部留出浮动 dock 的高度（`context.bottomInset`，不写死数字）。
            padding: EdgeInsetsDirectional.fromSTEB(
              16,
              0,
              16,
              24 + context.bottomInset,
            ),
            gap: 8,
            itemCount: _results.length + (_loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _results.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: ActivityIndicator(size: 22)),
                );
              }
              return OpenableAlbumListTile(
                album: _results[index],
                imgHost: imgHost,
              );
            },
          ),
        ),
      ],
    );
  }
}
