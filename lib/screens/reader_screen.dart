import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/image_loader.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/prism_theme.dart';
import '../ui/icons/icons.dart';
import '../ui/states.dart';

/// 阅读器：纵向滚动，逐页展示（带三层缓存的）乱序还原图。
///
/// 表现层是 prism_ui（浮动的上下 bars + 表面层级 + `AppTextStyle`），但
/// **数据流 / 手势语义 / 图片生命周期与旧实现逐行一致**（`docs/jm_ui_inventory.md`
/// §2.9、§5 R1–R3）：
///
/// 1. 页码是 `offset / maxScrollExtent` 的**比例估算**，不是真实页索引，
///    所以内容容器必须保持「纯纵向 `ListView` + 同一条 `padding`」；
/// 2. 每页的 `ui.Image` 由 [_ReaderPage] 持有引用，`dispose` 里归还给
///    `PageImageLoader`，一个都不能漏（一页 RGBA ≈ 25MB）；
/// 3. 有缓存时后台刷新失败只会记下错误、**不清空**已显示的页面。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.albumId, required this.title});

  final String albumId;
  final String title;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// 列表底部留白。**不要改这个值**：页码估算读的是 `maxScrollExtent`，
/// 留白变了「当前页」就会整体漂移（§5 R2）。
const double _listBottomPadding = 40;

/// bars 收起时滑出屏幕的距离，必须大于 bar 自身高度（含安全区）。
const double _topBarSlideOut = 120;
const double _bottomBarSlideOut = 100;

/// 浮动表面的最小高度（与旧 bar 的 56 一致，保证点屏热区不缩水）。
const double _barHeight = 56;

/// 浮层阴影：`.agents/surfaces.md` §Levels —— 阴影标记「浮在内容之上」。
const double _floatingElevation = 6;

const Duration _barsDuration = Duration(milliseconds: 240);
const Curve _barsCurve = Curves.easeOutCubic;
const Duration _imageFadeDuration = Duration(milliseconds: 220);
const Duration _progressDuration = Duration(milliseconds: 220);

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
    // 阅读器固定暗色、沉浸：漫画页压在深色底上才不发灰。
    //
    // 这里**没有写死黑色**——只是把 prism 的主题切到暗色一份，底色/浮层色
    // 仍全部来自暗色 `ColorScheme` 的 `SurfaceLevel` token：
    //   * 页面底 = `SurfaceLevel.page`（暗色下即 `surface`）；
    //   * 上下 bars = `SurfaceLevel.floatingOf`（暗色下即 `block`，比页面亮一级，
    //     符合 `.agents/surfaces.md`「浮层必须比它盖住的卡片更亮」）。
    // 若产品后来要求「跟随系统明暗」，把下面这行换成
    // `PrismTheme.of(Theme.of(context).brightness)` 即可，其余不用动。
    return Theme(
      data: PrismTheme.of(Brightness.dark),
      child: Builder(
        builder: (context) {
          final scheme = context.colorScheme;
          return SurfaceScope(
            level: SurfaceLevel.page,
            child: ColoredBox(
              color: SurfaceLevel.page.colorOf(scheme),
              // 点屏切 bars：手势挂在整个 Stack 外层，所以点画面、点 bars 的
              // 空白处都能收起/唤出（按钮自己的手势会在 arena 里赢下点击）。
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _showBars = !_showBars),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _buildContent()),
                    // 顶部 / 底部栏，点击画面切换显隐（动画时长与位移不变）。
                    AnimatedPositioned(
                      duration: _barsDuration,
                      curve: _barsCurve,
                      top: _showBars ? 0 : -_topBarSlideOut,
                      left: 0,
                      right: 0,
                      child: _TopBar(
                        title: widget.title,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: _barsDuration,
                      curve: _barsCurve,
                      bottom: _showBars ? 0 : -_bottomBarSlideOut,
                      left: 0,
                      right: 0,
                      child: _BottomBar(
                        currentPage: _currentPage,
                        total: _data?.pages.length ?? 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _data == null) {
      return const JmLoading(label: '正在加载章节…');
    }
    if (_error != null) {
      return JmError(message: _error!, onRetry: () => _load(force: true));
    }
    final data = _data!;
    if (data.pages.isEmpty) {
      return const JmEmpty(message: '该章节没有可显示的页面');
    }

    // 结构保持「纯纵向 ListView + 同一条 padding」：`_onScroll` 的比例估算
    // 依赖它，换 PageView / 加 header 都会让页码与预取窗口漂移。
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.only(bottom: _listBottomPadding),
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
    );
  }
}

/// 顶部浮动 bar：返回 + 章节标题。
///
/// 浮层用 `SurfaceLevel.floatingOf`（亮色 card / 暗色 block），内容通过
/// `SurfaceScope` 下传同一层级，让里面的组件自己再降一级。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final level = SurfaceLevel.floatingOf(scheme);
    return Surface(
      color: level.colorOf(scheme),
      shape: AppShape.vertical(bottom: AppCorner.xl),
      elevation: _floatingElevation,
      child: SurfaceScope(
        level: level,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: _barHeight,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '返回',
                  onPressed: onBack,
                  icon: const GlyphIcon(AppGlyphs.arrowBack),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.headline.of(context),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部浮动 bar：页码 + 进度。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentPage, required this.total});

  final int currentPage;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final level = SurfaceLevel.floatingOf(scheme);
    final progress = total == 0 ? 0.0 : currentPage / total;

    return Surface(
      color: level.colorOf(scheme),
      shape: AppShape.vertical(top: AppCorner.xl),
      elevation: _floatingElevation,
      child: SurfaceScope(
        level: level,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Text(
                    '$currentPage / $total',
                    style: AppTextStyle.footnote.of(context).toTabular,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: progress),
                      duration: _progressDuration,
                      curve: Curves.easeOut,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(value: value),
                    ),
                  ),
                ],
              ),
            ),
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
    final scheme = context.colorScheme;
    final image = _image;

    if (_failed) {
      // 错误表面用 prism 的 Card(isError:)：errorContainer 填充 +
      // onErrorContainer 内容色，不画边框（`surfaces.md` §State）。
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 240,
          child: Card(
            isError: true,
            inert: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const GlyphIcon(AppGlyphs.warning),
                const SizedBox(height: 8),
                Text(
                  '第 ${widget.pageNumber} 页加载失败',
                  style: AppTextStyle.footnote.of(context),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _load,
                  icon: const GlyphIcon(AppGlyphs.refresh, size: 18),
                  label: const Text('重试'),
                  style: ButtonStyle.from(
                    foregroundColor: scheme.onErrorContainer,
                    iconSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (image == null) {
      // 占位高度与旧实现一致（320），避免图片到达时整页跳动。
      return const SizedBox(
        height: 320,
        child: Center(child: ActivityIndicator(size: 24)),
      );
    }

    return AnimatedSwitcher(
      duration: _imageFadeDuration,
      child: RawImage(
        key: ValueKey<String>(widget.url),
        image: image,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
