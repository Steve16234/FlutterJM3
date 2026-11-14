import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/image_loader.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 阅读器：纵向滚动，逐页展示（带三层缓存的）乱序还原图。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.albumId,
    required this.title,
  });

  final String albumId;
  final String title;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  /// 全局共享的加载器与缓存池，退出阅读器后依然保留缓存。
  PageImageLoader get _loader => PageImageLoader.shared;

  final ScrollController _controller = ScrollController();

  ComicRead? _data;
  String? _error;
  bool _loading = true;
  bool _showBars = true;

  /// 当前阅读到第几页（1 基）。
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);

    // 有缓存就先出图，再后台刷新，避免每次都转圈。
    final cached = context.read<AppState>().chapters.cached(widget.albumId);
    if (cached != null) {
      _data = cached;
      _loading = false;
      _prefetchAround(1);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    // 共享的 loader / 缓存池不在这里释放。
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final itemExtent = _controller.position.maxScrollExtent;
    if (itemExtent <= 0) return;
    final progress = _controller.offset / itemExtent;
    final total = _data?.pages.length ?? 1;
    final page = (progress * total).floor() + 1;
    final clamped = page.clamp(1, total);
    if (clamped != _currentPage) {
      setState(() => _currentPage = clamped);
      _prefetchAround(clamped);
    }
  }

  /// 提前把当前页及后两页塞进缓存，滚动更顺。
  void _prefetchAround(int page) {
    final data = _data;
    if (data == null || data.pages.isEmpty) return;
    final aid = int.tryParse(data.id) ?? 0;
    for (var i = page; i <= page + 2; i++) {
      if (i < 1 || i > data.pages.length) continue;
      unawaited(
        _loader.prefetch(
          url: data.pages[i - 1].url,
          aid: aid,
          scrambleId: data.scrambleId,
        ),
      );
    }
  }

  Future<void> _load({bool force = false}) async {
    if (_data == null && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final app = context.read<AppState>();
      final read = await app.chapters.load(widget.albumId, force: force);
      if (!mounted) return;
      setState(() {
        _data = read;
        _loading = false;
        _error = null;
      });
      _prefetchAround(_currentPage);

      // 登录后把这一章记进“浏览历史”（`watch_list`），失败不影响阅读。
      if (app.loggedIn) {
        unawaited(
          app.client.recordWatch(widget.albumId).catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 手上有缓存时，后台刷新失败不该把已显示的页面清空。
        if (_data == null) _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildContent()),
          // 顶部 / 底部栏，点击画面切换显隐。
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: _showBars ? 0 : -120,
            left: 0,
            right: 0,
            child: _topBar(),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            bottom: _showBars ? 0 : -100,
            left: 0,
            right: 0,
            child: _bottomBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _data == null) {
      return const LoadingView(message: '正在加载章节…');
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: () => _load(force: true));
    }
    final data = _data!;
    if (data.pages.isEmpty) {
      return const EmptyView(message: '该章节没有可显示的页面');
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => _showBars = !_showBars),
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: data.pages.length,
        itemBuilder: (context, index) {
          final page = data.pages[index];
          return _ReaderPage(
            key: ValueKey<String>(page.url),
            loader: _loader,
            url: page.url,
            aid: int.tryParse(data.id) ?? 0,
            scrambleId: data.scrambleId,
            pageNumber: page.page,
          );
        },
      ),
    );
  }

  Widget _topBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
              ),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    final total = _data?.pages.length ?? 0;
    final progress = total == 0 ? 0.0 : _currentPage / total;

    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              Text(
                '$_currentPage / $total',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单页图片：命中缓存立刻显示，未命中才下载。
class _ReaderPage extends StatefulWidget {
  const _ReaderPage({
    super.key,
    required this.loader,
    required this.url,
    required this.aid,
    required this.scrambleId,
    required this.pageNumber,
  });

  final PageImageLoader loader;
  final String url;
  final int aid;
  final int scrambleId;
  final int pageNumber;

  @override
  State<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<_ReaderPage> {
  ui.Image? _image;
  bool _failed = false;
  bool _busy = false;

  /// 是否持有该图的引用（销毁时归还给缓存池）。
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_holding) {
      _holding = false;
      widget.loader.release(widget.url);
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    if (_failed) setState(() => _failed = false);
    try {
      final image = await widget.loader.load(
        url: widget.url,
        aid: widget.aid,
        scrambleId: widget.scrambleId,
      );
      if (!mounted) {
        // 已经销毁：立刻归还引用，否则这张图永远淘汰不掉。
        widget.loader.release(widget.url);
        return;
      }
      _holding = true;
      setState(() => _image = image);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _image;

    if (_failed) {
      return Container(
        height: 240,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: scheme.errorContainer,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.broken_image_outlined, color: scheme.onErrorContainer),
            const SizedBox(height: 8),
            Text(
              '第 ${widget.pageNumber} 页加载失败',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }

    if (image == null) {
      return const SizedBox(
        height: 320,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: RawImage(
        key: ValueKey<String>(widget.url),
        image: image,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
