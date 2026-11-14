import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/comic_query.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'album_open_transition.dart';
import 'common.dart';
import 'openable_album.dart';

/// 「发现」页内的搜索面板：搜索历史 + 热门标签 + 结果分页。
///
/// 不再单独占一页，而是作为「发现」页的一个面板，由顶部搜索栏的展开态切换。
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

  /// 点击历史 / 热门标签时回调，父级可同步填充搜索框。
  final ValueChanged<String>? onKeywordSelected;

  @override
  State<DiscoverSearchPanel> createState() => _DiscoverSearchPanelState();
}

class _DiscoverSearchPanelState extends State<DiscoverSearchPanel> {
  final ScrollController _scroll = ScrollController();

  List<dynamic> _hotTags = const <dynamic>[];
  final List<AlbumSummary> _results = <AlbumSummary>[];

  String _keyword = '';
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _searched = false;
  String? _error;

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
      context.read<AppState>().addSearchHistory(trimmed);
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

  void _pick(String keyword) {
    widget.onKeywordSelected?.call(keyword);

    // 历史 / 热词里的作品号（`1488098` / `JM1488098`）也要直达作品页，
    // 不能当成关键词去搜。
    final albumId = albumIdFromQuery(keyword);
    if (albumId != null) {
      openAlbumPreviewFromCenter(context, albumId: albumId);
      return;
    }

    _search(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _searched ? _buildResults(app.imgHost) : _buildLanding(app);
  }

  Widget _buildLanding(AppState app) {
    final history = app.searchHistory;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        if (history.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '搜索历史',
            moreLabel: '清空',
            onMore: app.clearSearchHistory,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: history
                  .map((k) => ActionChip(
                        label: Text(k),
                        onPressed: () => _pick(k),
                      ))
                  .toList(),
            ),
          ),
        ],
        if (_hotTags.isNotEmpty) ...<Widget>[
          const SectionHeader(title: '热门标签'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hotTags.map((raw) {
                final name = _tagName(raw);
                if (name.isEmpty) return const SizedBox.shrink();
                return ActionChip(
                  label: Text(name),
                  onPressed: () => _pick(name),
                );
              }).toList(),
            ),
          ),
        ],
        if (history.isEmpty && _hotTags.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: EmptyView(message: '输入关键词开始搜索'),
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
      return const LoadingView(message: '搜索中…');
    }
    if (_results.isEmpty && _error != null) {
      return ErrorView(message: _error!, onRetry: () => _search(_keyword));
    }
    if (_results.isEmpty) {
      return const EmptyView(message: '没有找到相关结果');
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: <Widget>[
              Text('“$_keyword”', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(
                '约 $_total 个结果',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: _results.length + (_loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _results.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }
              final album = _results[index];
              return OpenableAlbumListTile(album: album, imgHost: imgHost);
            },
          ),
        ),
      ],
    );
  }
}
