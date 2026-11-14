import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../screens/album_detail_screen.dart';
import 'album_card.dart';

/// M3E 卡片：用 `M3ECard` **自带的 container transform** 打开作品页。
///
/// 相比之前自己拼的 `OpenContainer` 封装，这里的好处是：
/// * 起点矩形、圆角、底色、目标页淡入节奏全由 `M3ECard` 内部计算；
/// * 按压状态层与触觉走 M3E 自带的 `M3ETappable` + `M3EHaptics`；
/// * 动画是 `motor` 的弹簧物理（`M3EMotion.expressiveSpatialDefault`），
///   不是写死的 420ms 曲线。
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
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      haptic: M3EHapticFeedback.light,
      openBuilder: (_) => AlbumDetailScreen(albumId: album.id),
      child: AlbumCardContent(album: album, imgHost: imgHost),
    );
  }
}

/// 横滑小卡的 M3E 版本。
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

  @override
  Widget build(BuildContext context) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      width: width,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      haptic: M3EHapticFeedback.light,
      openBuilder: (_) => AlbumDetailScreen(albumId: album.id),
      child: AlbumTileCompactContent(album: album, imgHost: imgHost),
    );
  }
}

/// 列表行的 M3E 版本。
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
    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      haptic: M3EHapticFeedback.light,
      openBuilder: (_) => AlbumDetailScreen(albumId: album.id),
      child: AlbumListTileContent(album: album, imgHost: imgHost),
    );
  }
}
