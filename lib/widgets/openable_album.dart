import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../core/image_loader.dart';
import '../data/models.dart';
import '../screens/album_detail_screen.dart';
import '../ui/album_card.dart';
import '../ui/icons/icons.dart';

/// 卡片里的封面比例（3:4 竖版），和网格 / 列表 / 旧 `CoverImage` 一致。
const double _coverRatio = 3 / 4;

/// prism 的卡片 → 页面**容器变换**。
///
/// 旧实现用 `M3ECard(openBuilder:)` 自带的 container transform；prism 的等价能力是
/// `OpenContainer` + [OpenContainerTransition.zoom]：它量出「关闭态子组件」在
/// 屏幕上的真实矩形（就是用户点下去的那张卡片），从那个矩形/圆角长成整页，
/// 页面在路程前 65% 淡入、卡片在后 65% 淡出，弹簧 340ms（iOS 27 的 zoom）。
/// 也就是说**转场锚点仍然是「被点卡片自身的位置与形状」**，只是换成 prism 的实现。
///
/// 注意 `transition: push` 走的是 prism 的卡片推入（`CardPageRoute`），没有
/// 「从卡片长出来」的过程，这里必须用 `zoom`。
class OpenableAlbumCard extends StatelessWidget {
  const OpenableAlbumCard({
    super.key,
    required this.album,
    required this.imgHost,
  });

  final AlbumSummary album;
  final String imgHost;

  @override
  Widget build(BuildContext context) {
    return OpenContainer<void>(
      // 关闭态形状与卡片自己的圆角一致，变换过程中不会被看出两层边。
      closedShape: AppShape.lg,
      transition: OpenContainerTransition.zoom,
      closedBuilder: (context, open) => AlbumCard(
        album: album,
        imgHost: imgHost,
        onPressed: () => _openWithHaptic(open),
      ),
      openBuilder: (context, _) => AlbumDetailScreen(albumId: album.id),
    );
  }
}

/// 横滑小卡（首页推荐位 / 详情页相关推荐）。
///
/// 卡片高度由外层给定（`SizedBox(height: 210)` 里的横向 `ListView`），
/// 所以内容只占「封面 + 两行标题」，标题区用 [LayoutBuilder] 判断有没有确定的
/// 高度可分配，避免换行时把 [Column] 撑出边框。
class OpenableAlbumTileCompact extends StatelessWidget {
  const OpenableAlbumTileCompact({
    super.key,
    required this.album,
    required this.imgHost,
    this.width = 124,
  });

  final AlbumSummary album;
  final String imgHost;
  final double width;

  /// 124 宽落在 `AppCorner` 的「中等卡片」区间（64–180），用 `lg`。
  static const double _radius = AppCorner.lg;

  @override
  Widget build(BuildContext context) {
    return OpenContainer<void>(
      closedShape: AppShape.lg,
      transition: OpenContainerTransition.zoom,
      closedBuilder: (context, open) => SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final title = _title(context);
            return Card(
              onPressed: () => _openWithHaptic(open),
              radius: _radius,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: _coverRatio,
                    child: _CompactCover(
                      url: album.coverUrl(imgHost),
                      borderRadius: AppRadius.top(_radius),
                    ),
                  ),
                  // 高度确定时把剩下的空间给标题（并裁掉可能多出来的一行），
                  // 高度不定时按内容自然排布。
                  if (constraints.hasBoundedHeight)
                    Expanded(child: ClipRect(child: title))
                  else
                    title,
                ],
              ),
            );
          },
        ),
      ),
      openBuilder: (context, _) => AlbumDetailScreen(albumId: album.id),
    );
  }

  Widget _title(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Text(
        album.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.caption1.of(context),
      ),
    );
  }
}

/// 列表行（搜索结果 / 分类列表）。
class OpenableAlbumListTile extends StatelessWidget {
  const OpenableAlbumListTile({
    super.key,
    required this.album,
    required this.imgHost,
  });

  final AlbumSummary album;
  final String imgHost;

  @override
  Widget build(BuildContext context) {
    return OpenContainer<void>(
      // 列表行是通栏 → `xl`，和 `AlbumListTile` 自己的圆角一致。
      closedShape: AppShape.xl,
      transition: OpenContainerTransition.zoom,
      closedBuilder: (context, open) => AlbumListTile(
        album: album,
        imgHost: imgHost,
        onPressed: () => _openWithHaptic(open),
      ),
      openBuilder: (context, _) => AlbumDetailScreen(albumId: album.id),
    );
  }
}

/// 旧 `M3ECard` 每次打开都带一次轻触觉（`M3EHapticFeedback.light`）；prism 的
/// `Card` 只有墨迹 / sparkle，没有触觉，所以在这里补回同样的手感。
void _openWithHaptic(VoidCallback open) {
  HapticFeedback.lightImpact();
  open();
}

/// 横滑小卡的封面：走 `PageImageLoader` 的既有管线（UA / Referer / 三层缓存 /
/// 并发合并），引用计数与 `lib/ui/album_card.dart` 里的封面完全一致 ——
/// `load` 拿到的 `ui.Image` 必须在 dispose 时 `release`，否则那张图永远淘汰不掉。
///
/// 封面不做乱序还原：`ImageUnscrambler.segmentCount` 只在 `aid < scrambleId` 时
/// 返回 0，所以这里固定传 `(aid: 0, scrambleId: 1)` 让管线原样解码。
///
/// 待对齐：`lib/ui/album_card.dart` 目前只有网格 / 列表两种形态，没有小卡形态，
/// 所以这段是本地实现；等它提供 compact 变体后换成那个组件、删掉这里。
class _CompactCover extends StatefulWidget {
  const _CompactCover({required this.url, this.borderRadius = BorderRadius.zero});

  final String url;
  final BorderRadius borderRadius;

  @override
  State<_CompactCover> createState() => _CompactCoverState();
}

class _CompactCoverState extends State<_CompactCover> {
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
  void didUpdateWidget(covariant _CompactCover oldWidget) {
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
    // 空 URL 或没拿到 CDN 前缀的相对地址（以 `/` 开头）当失败处理，占位块是
    // 稳定的，不会出现「空框跳一下」。测试里的 `imgHost` 为空，走这一支，不联网。
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
    // 占位色 = 卡片内的下一级表面（block），所以加载前后都不会跳。
    final fill = context.raisedSurfaceLevel.colorOf(scheme);
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
