import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/image_loader.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/section.dart';
import '../ui/states.dart';
// 只借这个纯函数（1.2万 这样的数字缩写）；封面 / 三态 / 分组标题都已换成 prism 组件。
import '../core/format.dart' show compactNumber;
import '../widgets/comment_section.dart';
import '../widgets/openable_album.dart';
import 'reader_screen.dart';

/// 漫画详情页。
///
/// 信息架构与迁移前逐条对齐（顺序即架构，别动）：
/// 封面折叠头 → 观看按钮 → 元数据 → 标签 → 作品 → 角色 → 系列 →
/// 评论区 → 相关推荐 → 尾部留白。
///
/// prism_ui 没有 `SliverAppBar` / `FlexibleSpaceBar`，所以折叠头是自己写的
/// [SliverPersistentHeader]：`maxExtent` = 屏宽 × 4/3（封面 3:4），
/// `minExtent` = 状态栏 + 72dp 的固定 bar；同一个 `shrinkOffset` 同时驱动
/// 封面视差（半速上移）、顶部压暗和「收起后换成页面底色」的过渡。
class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  Future<AlbumDetail>? _future;

  /// 「观看漫画」按钮的位置，用于转场时从按钮位置张开光圈。
  final GlobalKey _watchKey = GlobalKey();

  bool _favorited = false;
  bool _tracked = false;
  bool _actionBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 进页面就加载，不等转场结束。
    _future ??= _load();
  }

  Future<AlbumDetail> _load() async {
    final client = context.read<AppState>().client;
    final json = await client.album(widget.albumId);
    return AlbumDetail.fromJson(json);
  }

  /// 收藏 / 关注需要登录。
  bool _requireLogin() {
    if (context.read<AppState>().loggedIn) return true;
    BannerHost.maybeOf(context)?.show('请先在底栏「登录」页登录');
    return false;
  }

  Future<void> _favorite(String aid) async {
    if (_actionBusy || _favorited || !_requireLogin()) return;
    setState(() => _actionBusy = true);
    final banners = BannerHost.maybeOf(context);
    try {
      await context.read<AppState>().client.addFavorite(aid);
      if (!mounted) return;
      setState(() {
        _favorited = true;
        _actionBusy = false;
      });
      banners?.show('已加入收藏', level: BannerLevel.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      banners?.show('$e', level: BannerLevel.error);
    }
  }

  Future<void> _track(String aid) async {
    if (_actionBusy || !_requireLogin()) return;
    setState(() => _actionBusy = true);
    final banners = BannerHost.maybeOf(context);
    try {
      await context.read<AppState>().client.toggleTracking(aid);
      if (!mounted) return;
      setState(() {
        _tracked = !_tracked;
        _actionBusy = false;
      });
      banners?.show(
        _tracked ? '已关注' : '已取消关注',
        level: BannerLevel.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      banners?.show('$e', level: BannerLevel.error);
    }
  }

  /// 进入阅读器：以「观看漫画」按钮为圆心的光圈向四周张开，把阅读页揭示出来。
  ///
  /// 圆心只有一个来源：[_watchKey] 的 `RenderBox`。按钮确实离屏（还没被布局出来）
  /// 时才退回屏幕中央的兜底矩形 —— 这条兜底与改造前完全一致。
  void _read(AlbumDetail album) {
    final box = _watchKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final rect = box == null || !box.hasSize
        ? Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: screen.width - 32,
            height: 52,
          )
        : box.localToGlobal(Offset.zero) & box.size;

    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: _revealDuration,
        reverseTransitionDuration: _revealDuration,
        pageBuilder: (_, _, _) =>
            ReaderScreen(albumId: album.id, title: album.name),
        transitionsBuilder: (context, animation, _, child) =>
            _RadialRevealFromButton(
          animation: animation,
          from: rect,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;

    return FutureBuilder<AlbumDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _statusFrame(const JmLoading(label: '正在加载作品…'));
        }
        if (snapshot.hasError) {
          return _statusFrame(
            JmError(
              message: '${snapshot.error}',
              // 注意别写成 `setState(() => _future = _load())`：箭头函数会把
              // Future 当成 setState 回调的返回值，debug 下直接 assert 崩。
              onRetry: () => setState(() {
                _future = _load();
              }),
            ),
          );
        }
        return _body(snapshot.data!, imgHost);
      },
    );
  }

  /// 加载 / 出错时的页面骨架：一条常规 bar（带返回）+ 三态视图。
  Widget _statusFrame(Widget body) => JmPage(title: null, body: body);

  Widget _body(AlbumDetail album, String imgHost) {
    debugPrint(
      'BODY_IMGHOST=$imgHost settings=${context.read<AppState>().client.settings}',
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 封面是 3:4 竖图，预览区高度按宽度算出，避免被 BoxFit.cover 裁掉上下。
    final coverHeight = screenWidth * 4 / 3;
    final topInset = MediaQuery.paddingOf(context).top;
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;

    return PrismScaffold(
      // bar 由折叠头自己画（prism 没有 SliverAppBar）；这里给一条 0 高度的占位
      // bar，只为拿到 PrismScaffold 的页面底色、键盘让位与 body 的 MediaQuery。
      bar: const _HeaderBarSlot(),
      body: CustomScrollView(
        slivers: <Widget>[
          // ① 封面视差折叠头（含返回 / 收藏 / 关注）。
          SliverPersistentHeader(
            pinned: true,
            delegate: _CoverHeader(
              coverUrl: '$imgHost/media/albums/${album.id}.jpg',
              coverHeight: coverHeight,
              topInset: topInset,
              favorited: _favorited,
              tracked: _tracked,
              canPop: canPop,
              onBack: () => Navigator.maybePop(context),
              onFavorite: () => _favorite(album.id),
              onTrack: () => _track(album.id),
            ),
          ),
          // ② 观看漫画：紧跟在预览图下方、标题上方。
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _WatchButton(
                key: _watchKey,
                pageCount: album.totalPhotos,
                onWatch: () => _read(album),
              ),
            ),
          ),
          // ③ 标题 / 作者 / 四个统计 / 简介。
          SliverToBoxAdapter(child: _header(album)),
          // ④⑤⑥ 标签 / 作品 / 角色。
          if (album.tags.isNotEmpty)
            SliverToBoxAdapter(child: _tags('标签', album.tags)),
          if (album.works.isNotEmpty)
            SliverToBoxAdapter(child: _tags('作品', album.works)),
          if (album.actors.isNotEmpty)
            SliverToBoxAdapter(child: _tags('角色', album.actors)),
          // ⑦ 系列。
          if (album.series.isNotEmpty) ...<Widget>[
            const SliverToBoxAdapter(child: SectionHeader(title: '系列')),
            SliverToBoxAdapter(child: _horizontal(album.series, imgHost)),
          ],
          // ⑧ 评论区：拉 forum 接口分页加载，剧透内容默认折叠。
          SliverToBoxAdapter(
            child: CommentSection(
              albumId: album.id,
              totalHint: album.commentTotal,
            ),
          ),
          // ⑨ 相关推荐放在评论区下面。
          if (album.related.isNotEmpty) ...<Widget>[
            const SliverToBoxAdapter(child: SectionHeader(title: '相关推荐')),
            SliverPadding(
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
                    final item = album.related[index];
                    return OpenableAlbumCard(album: item, imgHost: imgHost);
                  },
                  childCount: album.related.length,
                ),
              ),
            ),
          ],
          // ⑩ 尾部留白。
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header(AlbumDetail album) {
    final scheme = context.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            album.name,
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 10),
          if (album.authors.isNotEmpty)
            Row(
              children: <Widget>[
                GlyphIcon(
                  AppGlyphs.account,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    album.authors.join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(context).copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: <Widget>[
              _Stat(
                glyph: AppGlyphs.eye,
                value: compactNumber(album.totalViews),
                label: '浏览',
              ),
              _Stat(
                glyph: AppGlyphs.heart,
                value: compactNumber(album.likes),
                label: '喜欢',
              ),
              _Stat(
                glyph: AppGlyphs.photos,
                value: '${album.totalPhotos}',
                label: '页数',
              ),
              _Stat(
                glyph: AppGlyphs.comment,
                value: '${album.commentTotal}',
                label: '评论',
              ),
            ],
          ),
          if (album.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              album.description,
              style: AppTextStyle.subheadline.of(context).copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  /// 标签 / 作品 / 角色：小标题 + 标签云（复用套件的 `TagWrap`）。
  Widget _tags(String title, List<String> values) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppTextStyle.footnote.of(context).copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TagWrap(tags: values),
        ],
      ),
    );
  }

  Widget _horizontal(List<AlbumSummary> albums, String imgHost) {
    return SizedBox(
      height: 210,
      child: PrismListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gap: 12,
        itemCount: albums.length,
        itemBuilder: (context, index) => OpenableAlbumTileCompact(
          album: albums[index],
          imgHost: imgHost,
        ),
      ),
    );
  }
}

/// 四个统计项之一：图标 + 数值 + 说明。
class _Stat extends StatelessWidget {
  const _Stat({required this.glyph, required this.value, required this.label});

  final Glyph glyph;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GlyphIcon(glyph, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(value, style: AppTextStyle.footnote.of(context, emphasized: true)),
        const SizedBox(width: 3),
        Text(
          label,
          style: AppTextStyle.caption2.of(context).copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 「观看漫画」主按钮。
///
/// 位于预览图下方、标题上方；[GlobalKey] 由外部持有，用于转场时把它的位置
/// 作为光圈起点（[AlbumDetailScreen] 里的 `_watchKey`）。
class _WatchButton extends StatelessWidget {
  const _WatchButton({
    super.key,
    required this.pageCount,
    required this.onWatch,
  });

  final int pageCount;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onWatch,
        style: ButtonStyle.from(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const GlyphIcon(AppGlyphs.play, size: 22),
            const SizedBox(width: 8),
            Text(
              '观看漫画',
              style: AppTextStyle.callout.of(context, emphasized: true),
            ),
            if (pageCount > 0) ...<Widget>[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.18),
                  shape: AppShape.full,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    '$pageCount 页',
                    style: AppTextStyle.caption2.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 折叠头的 bar：返回 / 收藏 / 关注。
///
/// 压在封面上时是一颗 scrim 底色的圆按钮（封面深浅未知，靠底色保证可读），
/// 随着折叠进度过渡成页面上的普通图标按钮。
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    required this.ink,
    required this.fill,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final Color ink;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return ElasticPress(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: GlyphIcon(glyph),
        style: ButtonStyle.from(
          foregroundColor: ink,
          backgroundColor: fill,
        ),
      ),
    );
  }
}

/// `PrismScaffold` 的占位 bar：折叠头自己画 bar，这里只占 0 高度。
///
/// 需要它而不是完全不用 `PrismScaffold`，是为了页面底色、键盘弹起时的让位
/// （写评论面板在很下面）以及 `body` 的 MediaQuery 处理。
class _HeaderBarSlot extends StatelessWidget implements PreferredSizeWidget {
  const _HeaderBarSlot();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 封面折叠头：`SliverPersistentHeader` + 手写视差。
///
/// 与旧 `SliverAppBar(pinned: true) + FlexibleSpaceBar(parallax)` 的对应关系：
/// * `maxExtent` ↔ `expandedHeight`（屏宽 × 4/3）；
/// * `minExtent` ↔ 收起的 bar（状态栏 + 72dp）；
/// * `shrinkOffset / 2` ↔ `CollapseMode.parallax` 的半速位移；
/// * 顶部渐变 ↔ 旧的 `DecoratedBox(gradient)`（改成 scrim 派生色，不再是字面量）。
class _CoverHeader extends SliverPersistentHeaderDelegate {
  _CoverHeader({
    required this.coverUrl,
    required this.coverHeight,
    required this.topInset,
    required this.favorited,
    required this.tracked,
    required this.canPop,
    required this.onBack,
    required this.onFavorite,
    required this.onTrack,
  });

  final String coverUrl;
  final double coverHeight;
  final double topInset;
  final bool favorited;
  final bool tracked;
  final bool canPop;
  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final VoidCallback onTrack;

  /// 收起后 bar 的高度，与 prism 的常规页面 bar 一致。
  static const double _barHeight = pageToolbarHeight;

  /// 顶部压暗渐变比 bar 多铺一点，收起过程中不会出现硬边。
  static const double _scrimOverhang = 24;

  @override
  double get minExtent => topInset + _barHeight;

  @override
  double get maxExtent => math.max(coverHeight, minExtent);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = context.colorScheme;
    final range = maxExtent - minExtent;
    // 0 = 封面完全展开；1 = 已经收成一条 bar。
    final collapse = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // 压在封面上的图标：底色是 scrim，前景用 onPrimary（本应用 vivid 配色下
    // 明暗两套都是浅色），收起来以后换回页面上的 onSurface。
    final fill = scheme.scrim.withValues(alpha: 0.32 * (1 - collapse));
    final ink = Color.lerp(scheme.onPrimary, scheme.onSurface, collapse)!;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 封面：视差 = 滚动距离的一半。
          Positioned(
            top: -shrinkOffset / 2,
            left: 0,
            right: 0,
            height: maxExtent,
            child: _Cover(url: coverUrl),
          ),
          // 顶部压暗，保证 bar 上的图标在浅色封面上也读得清。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: minExtent + _scrimOverhang,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    scheme.scrim.withValues(alpha: 0.45 * (1 - collapse)),
                    scheme.scrim.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // 收起后整块换成页面底色，和普通页面的 bar 一致。
          ColoredBox(
            color: SurfaceLevel.page
                .colorOf(scheme)
                .withValues(alpha: collapse),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: minExtent,
            child: Padding(
              padding: EdgeInsets.only(top: topInset, left: 8, right: 8),
              child: Row(
                children: <Widget>[
                  if (canPop)
                    _BarAction(
                      glyph: AppGlyphs.arrowBack,
                      tooltip: '返回',
                      onPressed: onBack,
                      ink: ink,
                      fill: fill,
                    ),
                  const Spacer(),
                  _BarAction(
                    glyph: AppGlyphs.heart,
                    tooltip: favorited ? '已收藏' : '收藏',
                    onPressed: onFavorite,
                    ink: favorited ? scheme.primary : ink,
                    fill: fill,
                  ),
                  const SizedBox(width: 4),
                  _BarAction(
                    glyph: AppGlyphs.bookmarks,
                    tooltip: tracked ? '已关注' : '关注',
                    onPressed: onTrack,
                    ink: tracked ? scheme.primary : ink,
                    fill: fill,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_CoverHeader oldDelegate) =>
      oldDelegate.coverUrl != coverUrl ||
      oldDelegate.coverHeight != coverHeight ||
      oldDelegate.topInset != topInset ||
      oldDelegate.favorited != favorited ||
      oldDelegate.tracked != tracked ||
      oldDelegate.canPop != canPop;
}

/// 折叠头里的封面：走 `PageImageLoader` 的既有管线（UA / Referer / 三层缓存 /
/// 并发合并），引用计数与 `lib/ui/album_card.dart` 里的封面完全一致 ——
/// `load` 拿到的 `ui.Image` 必须在 dispose 时 `release`，否则那张图永远淘汰不掉。
///
/// 详情页的大封面不是 `AlbumCard` 的一种形态（无圆角、比例由折叠头给定），
/// 所以按同一套 owning 模式在本地实现。封面不做乱序还原：
/// `ImageUnscrambler.segmentCount` 只在 `aid < scrambleId` 时返回 0，
/// 这里固定传 `(aid: 0, scrambleId: 1)` 让管线原样解码。
class _Cover extends StatefulWidget {
  const _Cover({required this.url});

  final String url;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  static const int _coverAid = 0;
  static const int _coverScrambleId = 1;
  static const Duration _fade = Duration(milliseconds: 200);

  ui.Image? _image;
  bool _failed = false;

  /// 已向缓存借出引用、还没归还的 URL。
  String? _heldUrl;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _release();
      _failed = false;
      _image = null;
      _start();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    final url = _heldUrl;
    if (url == null) return;
    _heldUrl = null;
    PageImageLoader.shared.release(url);
  }

  void _start() {
    final url = widget.url;
    debugPrint('COVER_URL=$url failed=${!url.startsWith('http')}');
    // 空 URL 或没拿到 CDN 前缀的相对地址当失败处理：占位块稳定，不会跳尺寸。
    if (url.isEmpty || !url.startsWith('http')) {
      _failed = true;
      return;
    }
    _fetch(url);
  }

  Future<void> _fetch(String url) async {
    try {
      final image = await PageImageLoader.shared.load(
        url: url,
        aid: _coverAid,
        scrambleId: _coverScrambleId,
      );
      if (!mounted || widget.url != url) {
        PageImageLoader.shared.release(url);
        return;
      }
      _heldUrl = url;
      setState(() => _image = image);
    } catch (_) {
      if (!mounted || widget.url != url) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // 占位色取 inset 层级：亮色下明显更深，暗色下更亮，加载前后不会糊成一片。
    final fill = SurfaceLevel.inset.colorOf(scheme);
    final image = _image;
    return ColoredBox(
      color: fill,
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: _fade,
          switchInCurve: Curves.easeOut,
          child: image == null
              ? SizedBox.expand(
                  key: const ValueKey<String>('placeholder'),
                  child: Center(
                    child: _failed
                        ? GlyphIcon(
                            AppGlyphs.photos,
                            size: 24,
                            color: scheme.onSurfaceVariant.opacity38,
                          )
                        : null,
                  ),
                )
              : SizedBox.expand(
                  key: ValueKey<String>(widget.url),
                  child: RawImage(
                    image: image,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 旧的 `Durations.long2`（450ms）。Material 的时长 token 不在 prism 里，
/// 这里保留原时长，进 / 退共用同一条曲线，手感与改造前一致。
const Duration _revealDuration = Duration(milliseconds: 450);

/// 阅读器转场：以按钮为圆心的「光圈揭示」。
///
/// 设计思路：不再变换按钮本身，而是把阅读页当成一张被“擦开”的蒙版，
/// 从按钮中心向外张开一个圆形窗口，同时给阅读页一点推近的纵深感。
///
/// 为什么这样更顺：
/// * 只有一层（阅读页）在动，不存在两个图层互相渗透的透明夹层；
/// * 圆窗外露出的就是详情页本身，天然衔接，不需要任何淡入淡出；
/// * 全程只有一次 `ClipPath` + 一次 `Transform.scale`，没有重新布局。
/// * 进 / 退共用一个 `t` 和一条曲线，收起时就是打开时的严格逆放。
class _RadialRevealFromButton extends StatelessWidget {
  const _RadialRevealFromButton({
    required this.animation,
    required this.from,
    required this.child,
  });

  final Animation<double> animation;

  /// 圆心来源：`_watchKey` 那个按钮的矩形。
  final Rect from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final center = from.center;

    // 圆需要盖住的最远距离：到屏幕四角里最远的那一个。
    final dx = math.max(center.dx, size.width - center.dx);
    final dy = math.max(center.dy, size.height - center.dy);
    final maxRadius = math.sqrt(dx * dx + dy * dy);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);

        // 光圈：匀速张开，半径与时间成正比，没有快慢变化。
        final radius = maxRadius * t;

        // 纵深：同样匀速推回 1.0，与光圈同步，避免两者节奏打架。
        final scale = 1.06 - 0.06 * t;

        // 缩放必须绕「按钮中心」而不是屏幕中心，
        // 否则推近的焦点和光圈中心错开，光圈的发出位置会看着不对。
        final alignment = Alignment(
          size.width == 0 ? 0 : center.dx / (size.width / 2) - 1,
          size.height == 0 ? 0 : center.dy / (size.height / 2) - 1,
        );

        return ClipPath(
          clipper: _CircleRevealClipper(center: center, radius: radius),
          child: Transform.scale(
            scale: scale,
            alignment: alignment,
            child: child,
          ),
        );
      },
    );
  }
}

/// 以 [center] 为圆心、[radius] 为半径的圆形裁剪。
class _CircleRevealClipper extends CustomClipper<Path> {
  const _CircleRevealClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    if (radius <= 0) return Path();
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.center != center;
}
