import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../core/image_loader.dart';
import '../data/models.dart';
import 'icons/icons.dart';

/// 封面图的宽高比（3:4 竖版），和旧 `CoverImage` / 网格 `childAspectRatio` 一致。
const double _coverRatio = 3 / 4;

/// 给整页提供封面 CDN 前缀，省掉每个卡片都写 `imgHost: app.imgHost`。
///
/// ```dart
/// // 页面根部包一次，页面里所有 AlbumCard / AlbumListTile 都不用再传 imgHost。
/// JmImageHost(imgHost: context.watch<AppState>().imgHost, child: body)
/// ```
///
/// 作用域和 `imgHost` 参数二选一即可，显式参数优先。
class JmImageHost extends InheritedWidget {
  const JmImageHost({super.key, required this.imgHost, required super.child});

  /// 图片 CDN 根地址（`AppState.imgHost`）。
  final String imgHost;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JmImageHost>()?.imgHost ?? '';

  @override
  bool updateShouldNotify(JmImageHost oldWidget) =>
      oldWidget.imgHost != imgHost;
}

/// 网格形态的作品卡：3:4 封面 + 两行标题 + 一行作者。
///
/// ```dart
/// SliverGrid(
///   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
///     crossAxisCount: 2,
///     mainAxisSpacing: 12,
///     crossAxisSpacing: 12,
///     childAspectRatio: 0.52,
///   ),
///   delegate: SliverChildBuilderDelegate(
///     (context, i) => AlbumCard(
///       album: items[i],
///       imgHost: app.imgHost,
///       onPressed: () => open(items[i].id),
///     ),
///     childCount: items.length,
///   ),
/// )
/// ```
///
/// **高度**：在网格 / `GridView` / `SizedBox` 里（高度有界）时，作者会被压到卡片底部
/// （和旧 `AlbumCardContent` 的 `Spacer()` 一致）；万一被放进 `ListView` 这种高度
/// 无界的地方，会退化成按内容自适应，而不是抛 `RenderFlex` 异常。
///
/// 圆角：卡片最短边在网格里就是格子的宽度（约 170），落在 `AppCorner` 的
/// 「lg = 64~180 中等卡片」区间，所以默认 `lg`；封面与卡片同边缘（无内边距），
/// 所以封面只给**上面两个角**用同一个半径裁切（嵌套圆角 = 外层半径 − 内边距，
/// 这里内边距为 0，所以两者相等）。
///
/// 什么时候别用：横向一行的「推荐位」用 [AlbumListTile]；要展示阅读进度、
/// 收藏角标等更多信息时另做变体，不要往这张卡里塞第四行文字。
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    this.onPressed,
    this.radius,
    this.imgHost,
  });

  final AlbumSummary album;

  /// `null` = 不可点（整卡降到 38% 透明度，prism 的禁用表达）。
  final VoidCallback? onPressed;

  /// 覆盖默认圆角（`AppCorner.lg`）。确实需要时才传 token 值，别写裸数字。
  final double? radius;

  /// 图片 CDN 前缀；不传就从 [JmImageHost] 作用域取。
  final String? imgHost;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final radius = this.radius ?? AppCorner.lg;
    final host = imgHost ?? JmImageHost.of(context);

    // [pinned] = 高度有界：文字区吃掉剩余高度，作者压到卡片底部（和旧实现的
    // `Spacer()` 一致）；否则按内容排，不依赖任何剩余空间。
    Widget textBlock({required bool pinned}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          mainAxisSize: pinned ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline.of(context, emphasized: true),
            ),
            if (pinned) const Spacer() else const SizedBox(height: 2),
            if (album.author.isNotEmpty)
              Text(
                album.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      );
    }

    return Card(
      onPressed: onPressed,
      radius: radius,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.hasBoundedHeight;
          return Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AspectRatio(
                aspectRatio: _coverRatio,
                child: _AlbumCover(
                  url: album.coverUrl(host),
                  borderRadius: AppRadius.top(radius),
                ),
              ),
              if (bounded)
                Expanded(child: textBlock(pinned: true))
              else
                textBlock(pinned: false),
            ],
          );
        },
      ),
    );
  }
}

/// 横向列表形态：左边 3:4 缩略图，右边标题 / 作者 / 标签 / 一行元信息。
///
/// ```dart
/// ListView.separated // ← 不存在于 prism，用 PrismListView 的 gap:
/// PrismListView(
///   padding: const EdgeInsets.symmetric(horizontal: 16),
///   gap: 8,
///   itemCount: results.length,
///   itemBuilder: (context, i) => AlbumListTile(
///     album: results[i],
///     imgHost: app.imgHost,
///     subtitle: '${compactNumber(results[i].totalViews)} 次浏览',
///     onPressed: () => open(results[i].id),
///   ),
/// )
/// ```
///
/// 圆角：卡片是全宽通栏 → `AppCorner.xl`（24）；卡片内边距 8，
/// 缩略图圆角 = 24 − 8 = `AppCorner.md`（16），嵌套关系是算出来的，不是再加一个 token。
///
/// 什么时候别用：在网格里用 [AlbumCard]；只有一列文字、没有封面的条目用
/// `rows.dart` 里的 `SettingRow` / `NavigationRow`。
class AlbumListTile extends StatelessWidget {
  const AlbumListTile({
    super.key,
    required this.album,
    this.onPressed,
    this.subtitle,
    this.imgHost,
  });

  final AlbumSummary album;
  final VoidCallback? onPressed;

  /// 封面右侧多出来的一行元信息（阅读量、更新时间等），由调用方拼好文案。
  final String? subtitle;

  /// 图片 CDN 前缀；不传就从 [JmImageHost] 作用域取。
  final String? imgHost;

  /// 缩略图宽度；高度由 3:4 比例得出。
  static const double _thumbWidth = 84;

  /// 卡片内边距，同时也是「缩略图圆角 = 卡片圆角 − 它」的那个 inset。
  static const double _inset = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final host = imgHost ?? JmImageHost.of(context);
    final tags = <String>[
      if (album.categoryTitle.isNotEmpty) album.categoryTitle,
      if (album.categorySubTitle.isNotEmpty) album.categorySubTitle,
    ];
    final subtitle = this.subtitle;
    return Card(
      onPressed: onPressed,
      radius: AppCorner.xl,
      padding: const EdgeInsets.all(_inset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _thumbWidth,
            child: AspectRatio(
              aspectRatio: _coverRatio,
              child: _AlbumCover(
                url: album.coverUrl(host),
                borderRadius: AppRadius.all(AppCorner.md),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(
                    context,
                    emphasized: true,
                  ),
                ),
                if (album.author.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    album.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  // 标签：小灰底 chip（block 层级填充）。规范禁止用
                  // primaryContainer 填标签，那会把卡片染成品牌色。
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final tag in tags) MetaChip(label: tag),
                    ],
                  ),
                ],
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面本体：走 `PageImageLoader` 的既有管线（UA / Referer / 三层缓存 / 并发合并）。
///
/// 管线里没有 `ImageProvider`，所以这里自己持有一个 `ui.Image` 引用，并在
/// `dispose` 时归还（`PageImageLoader.release`）——和 `reader_screen` 的
/// `_ReaderPage` 完全一致，漏掉归还那张图就永远淘汰不掉。
///
/// 封面不做乱序还原：`ImageUnscrambler.segmentCount` 只在 `aid < scrambleId`
/// 时返回 0，所以这里固定传 `（aid: 0, scrambleId: 1)`，让管线原样解码。
class _AlbumCover extends StatefulWidget {
  const _AlbumCover({required this.url, this.borderRadius = BorderRadius.zero});

  final String url;
  final BorderRadius borderRadius;

  @override
  State<_AlbumCover> createState() => _AlbumCoverState();
}

class _AlbumCoverState extends State<_AlbumCover> {
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
  void didUpdateWidget(covariant _AlbumCover oldWidget) {
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
    // 空 URL 或没拿到 CDN 前缀的相对地址（以 `/` 开头）当失败处理，
    // 占位块是稳定的，不会出现「空框跳一下」。
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
    // 占位色取「井」层级（`raisedSurfaceLevel` = 卡片里的 block，再下一级 = inset）。
    // 不能只用 block：亮色下 prism 的 `block` 与 `page` 是同一个颜色（都是
    // surfaceContainer），封面与卡片同边（无内边距）时上半张会和页面糊成一片，
    // 卡片轮廓就没了；inset 在亮色下明显更深、暗色下更亮，两种模式都读得出「这里是图」。
    final fill = context.raisedSurfaceLevel.next.colorOf(scheme);
    final image = _image;
    return ClipRSuperellipse(
      borderRadius: widget.borderRadius,
      child: ColoredBox(
        color: fill,
        child: SizedBox.expand(
          child: AnimatedSwitcher(
            duration: _fade,
            switchInCurve: Curves.easeOut,
            child: image == null
                ? SizedBox.expand(
                    key: const ValueKey<String>('placeholder'),
                    child: _placeholder(scheme),
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
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Center(
      child: _failed
          ? GlyphIcon(
              AppGlyphs.photos,
              size: 20,
              color: scheme.onSurfaceVariant.opacity38,
            )
          : null,
    );
  }
}
