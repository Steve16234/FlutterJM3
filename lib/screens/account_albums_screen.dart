import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/account_models.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/openable_album.dart';

/// 账号相关列表：我的收藏 / 浏览历史 / 我的关注。
///
/// 分页滚动加载（[loader] 由调用方给出，对应 `favorite` / `watch_list` /
/// `album_tracking` 三个接口）。
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
      setState(() {
        _loading = true;
        _error = null;
      });
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: widget.title,
        leading: const BackButton(),
      ),
      body: _buildBody(imgHost),
    );
  }

  Widget _buildBody(String imgHost) {
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_error != null && _items.isEmpty) {
      return ErrorView(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    }
    if (_items.isEmpty) {
      return EmptyView(message: widget.emptyMessage);
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: GridView.builder(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // 和其它网格保持一致：0.58 会把 AlbumCard 的标题区压到溢出 1px。
          childAspectRatio: 0.52,
        ),
        itemCount: _items.length + (_more ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final album = _items[index];
          return OpenableAlbumCard(album: album, imgHost: imgHost);
        },
      ),
    );
  }
}
