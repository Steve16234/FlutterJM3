import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/album_detail_screen.dart';

/// 没有卡片可飞时的打开方式（例如搜索框输入 JM 号直达）。
///
/// 用 M3E 的 [M3ECardContainerTransform]：从一个虚拟的"居中卡片"矩形
/// 做容器变换展开到整屏，弹簧物理用的是 `M3EMotion.expressiveSpatialDefault`。
/// 有卡片的场景请用 [OpenableAlbumCard] 等（`M3ECard.openBuilder`）。
Future<void> openAlbumPreviewFromCenter(
  BuildContext context, {
  required String albumId,
}) async {
  final size = MediaQuery.sizeOf(context);
  final scheme = Theme.of(context).colorScheme;

  M3ECardContainerTransform.show<void>(
    context: context,
    origin: Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.3,
      height: size.width * 0.3 * 4 / 3,
    ),
    originRadius: 12,
    originColor: scheme.surfaceContainerLow,
    builder: (_) => AlbumDetailScreen(albumId: albumId),
  );
}
