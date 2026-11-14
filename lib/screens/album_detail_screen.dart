import 'dart:math' as math;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/comment_section.dart';
import '../widgets/common.dart';
import '../widgets/openable_album.dart';
import 'reader_screen.dart';

/// 漫画详情页。
class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  Future<AlbumDetail>? _future;

  /// 「观看漫画」按钮的位置，用于转场时从按钮尺寸放大到全屏。
  final GlobalKey _watchKey = GlobalKey();

  bool _favorited = false;
  bool _tracked = false;
  bool _actionBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在底栏「登录」页登录')),
    );
    return false;
  }

  Future<void> _favorite(String aid) async {
    if (_actionBusy || _favorited || !_requireLogin()) return;
    setState(() => _actionBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().client.addFavorite(aid);
      if (!mounted) return;
      setState(() {
        _favorited = true;
        _actionBusy = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('已加入收藏')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _track(String aid) async {
    if (_actionBusy || !_requireLogin()) return;
    setState(() => _actionBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().client.toggleTracking(aid);
      if (!mounted) return;
      setState(() {
        _tracked = !_tracked;
        _actionBusy = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(_tracked ? '已关注' : '已取消关注')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// 进入阅读器：以按钮为圆心的光圈向四周张开，把阅读页揭示出来。
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
        transitionDuration: Durations.long2,
        reverseTransitionDuration: Durations.long2,
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

    return Scaffold(
      body: FutureBuilder<AlbumDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ScaffoldedLoading();
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: ErrorView(
                message: '${snapshot.error}',
                onRetry: () => setState(() => _future = _load()),
              ),
            );
          }

          final album = snapshot.data!;
          // 封面是 3:4 竖图，预览区高度按宽度算出，避免被 BoxFit.cover 裁掉上下。
          final coverHeight = MediaQuery.sizeOf(context).width * 4 / 3;
          return CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                expandedHeight: coverHeight,
                pinned: true,
                actions: <Widget>[
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    tooltip: _favorited ? '已收藏' : '收藏',
                    haptic: M3EHapticFeedback.light,
                    onPressed: () => _favorite(album.id),
                    icon: Icon(
                      _favorited ? Icons.favorite : Icons.favorite_border,
                    ),
                  ),
                  M3EIconButton(
                    variant: M3EIconButtonVariant.standard,
                    tooltip: _tracked ? '已关注' : '关注',
                    haptic: M3EHapticFeedback.light,
                    onPressed: () => _track(album.id),
                    icon: Icon(
                      _tracked ? Icons.bookmark : Icons.bookmark_border,
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CoverImage(
                        url: '$imgHost/media/albums/${album.id}.jpg',
                        borderRadius: BorderRadius.zero,
                        aspectRatio: 3 / 4,
                      ),
                      // 顶部渐变，保证返回按钮在浅色封面上也可见。
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: <Color>[Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 观看漫画：紧跟在预览图下方、标题上方。
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
              SliverToBoxAdapter(child: _header(album)),
              if (album.tags.isNotEmpty)
                SliverToBoxAdapter(child: _chips('标签', album.tags)),
              if (album.works.isNotEmpty)
                SliverToBoxAdapter(child: _chips('作品', album.works)),
              if (album.actors.isNotEmpty)
                SliverToBoxAdapter(child: _chips('角色', album.actors)),
              if (album.series.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: '系列'),
                ),
                SliverToBoxAdapter(
                  child: _horizontal(album.series, imgHost),
                ),
              ],
              // 评论区：拉 forum 接口分页加载，剧透内容默认折叠。
              SliverToBoxAdapter(
                child: CommentSection(
                  albumId: album.id,
                  totalHint: album.commentTotal,
                ),
              ),
              // 相关推荐放在评论区下面。
              if (album.related.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: '相关推荐'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = album.related[index];
                        return OpenableAlbumCard(
                          album: item,
                          imgHost: imgHost,
                        );
                      },
                      childCount: album.related.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(AlbumDetail album) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            album.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          if (album.authors.isNotEmpty)
            Row(
              children: <Widget>[
                Icon(Icons.person_outline, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    album.authors.join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
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
              _Stat(icon: Icons.remove_red_eye_outlined, value: compactNumber(album.totalViews), label: '浏览'),
              _Stat(icon: Icons.favorite_border, value: compactNumber(album.likes), label: '喜欢'),
              _Stat(icon: Icons.photo_library_outlined, value: '${album.totalPhotos}', label: '页数'),
              _Stat(icon: Icons.forum_outlined, value: '${album.commentTotal}', label: '评论'),
            ],
          ),
          if (album.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              album.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chips(String title, List<String> values) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map((v) => Chip(
                      label: Text(v),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _horizontal(List<AlbumSummary> albums, String imgHost) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final album = albums[index];
          return OpenableAlbumTileCompact(
            album: album,
            imgHost: imgHost,
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ScaffoldedLoading extends StatelessWidget {
  const _ScaffoldedLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView());
  }
}

/// 「观看漫画」主按钮。
///
/// 位于预览图下方、标题上方；[GlobalKey] 由外部持有，
/// 用于转场时把它的位置作为动画起点。
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
    final scheme = Theme.of(context).colorScheme;

    return M3EButton(
      onPressed: onWatch,
      icon: const Icon(Icons.menu_book, size: 22),
      label: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text(
            '观看漫画',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (pageCount > 0) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$pageCount 页',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
