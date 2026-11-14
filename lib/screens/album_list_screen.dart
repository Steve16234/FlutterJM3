import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/album_card.dart';
import '../widgets/common.dart';
import 'album_detail_screen.dart';

/// 分页数据源签名：给定页码返回一页数据。
typedef PageLoader = Future<PagedAlbums> Function(int page);

/// 通用分页列表页（最新更新 / 推荐更多 / 分类筛选 / 搜索结果）。
class PagedAlbumScreen extends StatefulWidget {
  const PagedAlbumScreen({
    super.key,
    required this.title,
    required this.loader,
    this.asGrid = false,
    this.subtitle,
  });

  final String title;
  final PageLoader loader;

  /// true 用网格，false 用列表行。
  final bool asGrid;
  final String? subtitle;

  @override
  State<PagedAlbumScreen> createState() => _PagedAlbumScreenState();
}

class _PagedAlbumScreenState extends State<PagedAlbumScreen> {
  final List<AlbumSummary> _items = <AlbumSummary>[];
  final ScrollController _controller = ScrollController();

  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      _loadNext();
    }
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final next = _page + 1;
      final result = await widget.loader(next);
      if (!mounted) return;
      setState(() {
        _page = next;
        _items.addAll(result.items);
        // 接口未给 total 时，用「本页是否为空」判断结束。
        _hasMore = result.total > 0
            ? result.items.isNotEmpty && _items.length < result.total
            : result.items.isNotEmpty;
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

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadNext();
  }

  void _open(AlbumSummary album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(albumId: album.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.title),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
      body: _buildBody(imgHost),
    );
  }

  Widget _buildBody(String imgHost) {
    if (_items.isEmpty && _loading) {
      return const LoadingView();
    }
    if (_items.isEmpty && _error != null) {
      return ErrorView(message: _error!, onRetry: _refresh);
    }
    if (_items.isEmpty) {
      return const EmptyView(message: '没有内容');
    }

    final footer = <Widget>[
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: TextButton.icon(
              onPressed: _loadNext,
              icon: const Icon(Icons.refresh),
              label: Text('加载失败，点击重试：$_error'),
            ),
          ),
        ),
      if (!_hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '已经到底了',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
    ];

    if (widget.asGrid) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _controller,
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.52,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => AlbumCard(
                    album: _items[index],
                    imgHost: imgHost,
                    onTap: () => _open(_items[index]),
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(children: footer),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _controller,
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Column(children: footer);
          }
          return AlbumListTile(
            album: _items[index],
            imgHost: imgHost,
            onTap: () => _open(_items[index]),
          );
        },
      ),
    );
  }
}

/// 最新更新列表页。
class LatestListScreen extends StatelessWidget {
  const LatestListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = context.read<AppState>().client;
    return PagedAlbumScreen(
      title: '最新更新',
      asGrid: true,
      loader: (page) async {
        final list = await client.latest(page: page);
        return PagedAlbums(
          items: list
              .whereType<Map>()
              .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
              .toList(),
          total: 0,
          page: page,
        );
      },
    );
  }
}

/// 推荐板块「更多」列表页。
class PromoteListScreen extends StatelessWidget {
  const PromoteListScreen({
    super.key,
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  @override
  Widget build(BuildContext context) {
    final client = context.read<AppState>().client;
    return PagedAlbumScreen(
      title: title,
      asGrid: true,
      loader: (page) async {
        final list = await client.promoteList(id, page: page);
        return PagedAlbums(
          items: list
              .whereType<Map>()
              .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
              .toList(),
          total: 0,
          page: page,
        );
      },
    );
  }
}
