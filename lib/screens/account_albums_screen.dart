import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/account_models.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/states.dart';
import '../widgets/openable_album.dart';

/// 账号相关列表：我的收藏 / 浏览历史 / 我的关注。
///
/// 分页滚动加载（[loader] 由调用方给出，对应 `favorite` / `watch_list` /
/// `album_tracking` 三个接口）。
///
/// 表现层：prism_ui。**没有下拉刷新**（prism 里不存在 `RefreshIndicator`），
/// 刷新改到 bar 的刷新按钮；上拉加载更多与原来的阈值 / 页码逻辑保持不变。
class AccountAlbumsScreen extends StatefulWidget {
  const AccountAlbumsScreen({
    super.key,
    required this.title,
    required this.loader,
    this.emptyMessage = '这里还没有内容',
  });

  final String title;
  final Future<AccountAlbumPage> Function(int page) loader;
  final String emptyMessage;

  @override
  State<AccountAlbumsScreen> createState() => _AccountAlbumsScreenState();
}

class _AccountAlbumsScreenState extends State<AccountAlbumsScreen> {
  final ScrollController _controller = ScrollController();
  final List<AlbumSummary> _items = <AlbumSummary>[];

  /// 已有数据时的「刷新中」：只点亮 bar 底部的进度条，不把列表换成加载态。
  final ValueNotifier<bool> _refreshing = ValueNotifier<bool>(false);

  int _page = 1;
  bool _loading = true;
  bool _more = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _refreshing.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    if (!refresh && !_more) return;

    _busy = true;
    if (refresh) {
      if (_items.isEmpty) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else {
        // 已有数据：不闪屏，只在 bar 上显示进度。
        _refreshing.value = true;
        setState(() => _error = null);
      }
    }

    final page = refresh ? 1 : _page;
    try {
      final result = await widget.loader(page);
      if (!mounted) return;
      setState(() {
        if (refresh) _items.clear();
        _items.addAll(result.items);
        _page = page + 1;
        _more = result.hasMore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      // 已有数据时保留旧列表，只用提示条报告失败（整页错误只留给空列表）。
      if (_items.isNotEmpty) {
        BannerHost.maybeOf(context)?.show(
          '加载失败：$e',
          level: BannerLevel.error,
        );
      }
    } finally {
      _busy = false;
      if (mounted) _refreshing.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;

    return JmPage(
      title: widget.title,
      loading: _refreshing,
      actions: <Widget>[
        ElasticPress(
          child: AppBarActionButton(
            data: IconButtonData(
              glyph: AppGlyphs.refresh,
              tooltip: '刷新',
              onPressed: () => _load(refresh: true),
            ),
          ),
        ),
      ],
      body: _buildBody(imgHost),
    );
  }

  Widget _buildBody(String imgHost) {
    if (_items.isEmpty) {
      if (_loading) return const JmLoading();
      if (_error != null) {
        return JmError(
          message: _error!,
          onRetry: () => _load(refresh: true),
        );
      }
      return JmEmpty(message: widget.emptyMessage);
    }

    return CustomScrollView(
      controller: _controller,
      slivers: <Widget>[
        SliverPadding(
          // 底部让开系统栏 / 悬浮底栏（`context.bottomInset`，不写死数字）。
          padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + context.bottomInset),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // 和其它网格保持一致：0.58 会把 AlbumCard 的标题区压到溢出 1px。
              childAspectRatio: 0.52,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 尾项 = 「还在加载下一页」的转圈格子（原来也是这么做的）。
                if (index >= _items.length) {
                  return const Center(child: ActivityIndicator(size: 22));
                }
                return OpenableAlbumCard(
                  album: _items[index],
                  imgHost: imgHost,
                );
              },
              childCount: _items.length + (_more ? 1 : 0),
            ),
          ),
        ),
      ],
    );
  }
}
