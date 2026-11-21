import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/states.dart';
import '../widgets/openable_album.dart';

/// 分页数据源签名：给定页码返回一页数据。
typedef PageLoader = Future<PagedAlbums> Function(int page);

/// 通用分页列表页（最新更新 / 推荐更多 / 分类筛选 / 随机推荐）。
///
/// 表现层是 prism_ui（FlClash 规范）：`JmPage` 骨架 + 三态组件 + `AlbumCard` /
/// `AlbumListTile`。**数据流一点没动**：
///
/// * 进页面立刻拉第 1 页（`initState` 里同步发起，不等转场结束）；
/// * 上拉到底自动加载下一页（`maxScrollExtent - 480` 触发）；
/// * `total == 0` 时用「本页是否为空」判结束，`total > 0` 时用
///   `items.length < total`（两个分支都不能删，见 `jm_ui_inventory.md` R11）。
///
/// 唯一的交互变化来自规范本身：prism 没有下拉刷新，刷新改成 app bar 上的刷新动作
/// （`surfaces.md` §6）。刷新时**保留旧列表**，只在 bar 底下走进度条，失败也不清空
/// 已有数据 —— 否则整页会闪一下 Loading。
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

  /// app bar 底下那条 3dp 进度条的数据源（`JmPage.loading`）。
  final ValueNotifier<bool> _refreshingProgress = ValueNotifier<bool>(false);

  int _page = 0;
  bool _loading = false;
  bool _refreshing = false;
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
    _refreshingProgress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      _loadNext();
    }
  }

  /// 一页数据是否说明「后面还有」。
  ///
  /// 接口未给 total 时（上游 `LatestListScreen` / `PromoteListScreen` /
  /// `randomRecommend` 故意传 `total: 0`），用「本页是否为空」判断结束。
  bool _moreAfter(PagedAlbums result) => result.total > 0
      ? result.items.isNotEmpty && _items.length < result.total
      : result.items.isNotEmpty;

  Future<void> _loadNext() async {
    if (_loading || _refreshing || !_hasMore) return;
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
        _hasMore = _moreAfter(result);
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

  /// 重新拉第 1 页（app bar 的刷新动作）。
  ///
  /// 已有数据时不进 Loading 态：旧列表留在屏幕上，bar 走进度条；成功后整段替换，
  /// 失败则保留旧数据 + banner 提示。
  Future<void> _refresh() async {
    if (_refreshing || _loading) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    _refreshingProgress.value = true;

    try {
      final result = await widget.loader(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _page = 1;
        _hasMore = _moreAfter(result);
      });
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        // 什么都没有：整页错误态。
        setState(() => _error = '$e');
      } else {
        // 已有数据：保留旧列表，只提示一句（规约 §5）。
        BannerHost.maybeOf(context)?.show(
          '刷新失败：$e',
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        _refreshingProgress.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;
    final subtitle = widget.subtitle;

    return JmPage(
      title: widget.title,
      // 原来的两行标题（分类 / 子分类）在 prism 里分成「bar 标题 + 条状副标题」。
      bottom: subtitle == null ? null : _SubtitleBar(text: subtitle),
      loading: _refreshingProgress,
      actions: <JmBarAction>[
        JmBarAction(
          glyph: AppGlyphs.refresh,
          tooltip: '刷新',
          onPressed: _refresh,
        ),
      ],
      body: _body(context, imgHost),
    );
  }

  Widget _body(BuildContext context, String imgHost) {
    // 三态只在「一条数据都没有」时占整页；已有数据时刷新不换成 Loading（会闪）。
    if (_items.isEmpty) {
      if (_loading) return const JmLoading();
      final error = _error;
      if (error != null) return JmError(message: error, onRetry: _refresh);
      return const JmEmpty(message: '没有内容');
    }
    return widget.asGrid ? _grid(imgHost) : _list(imgHost);
  }

  Widget _grid(String imgHost) {
    return CustomScrollView(
      controller: _controller,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverGrid(
            // 190 / 0.52 是旧页面的比例，全项目 5 处一致，别改。
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => OpenableAlbumCard(
                album: _items[index],
                imgHost: imgHost,
              ),
              childCount: _items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: Column(children: _footer(context))),
      ],
    );
  }

  Widget _list(String imgHost) {
    return PrismListView(
      controller: _controller,
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Column(children: _footer(context));
        }
        return OpenableAlbumListTile(album: _items[index], imgHost: imgHost);
      },
    );
  }

  /// 列表尾部：加载更多 / 局部失败重试 / 到底提示。
  ///
  /// 局部失败不整页报错，只在那一格放一行可点的文字（`jm_ui_kit.md` §2）。
  List<Widget> _footer(BuildContext context) {
    final scheme = context.colorScheme;
    return <Widget>[
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: ActivityIndicator(size: 22)),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: TextButton.icon(
              onPressed: _loadNext,
              icon: const GlyphIcon(AppGlyphs.refresh, size: 18),
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
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
    ];
  }
}

/// bar 底下的副标题条（旧的「分类 / 子分类」两行标题里的第二行）。
class _SubtitleBar extends StatelessWidget {
  const _SubtitleBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
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
