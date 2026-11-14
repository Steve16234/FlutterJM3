import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/album_detail_screen.dart';

/// 没有卡片可飞时的打开方式（例如搜索框输入 JM 号直达）。
///
/// 关键点：**起点必须是用户真正点到的那个控件**。
/// 传 [originKey]（绑在按钮 / 条目上的 [GlobalKey]），转场就从它的实际矩形
/// 长出来；拿不到时才退回一个居中矩形。
///
/// 早期版本固定用一个「屏幕中上方」的虚拟矩形，结果转场开始的位置和手指
/// 点下去的位置对不上，看起来像凭空冒出一张卡片 —— 和点击行为是割裂的。
Future<void> openAlbumPreviewFromCenter(
  BuildContext context, {
  required String albumId,
  GlobalKey? originKey,
}) async {
  final size = MediaQuery.sizeOf(context);
  final scheme = Theme.of(context).colorScheme;

  Rect? rectFromKey;
  if (originKey != null) {
    final box = originKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      rectFromKey = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  // 兜底：仍取中上方，但尺寸按屏幕宽度的 1/3 收敛，避免在宽屏上张得太大。
  final origin = rectFromKey ??
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.44),
        width: size.width * 0.3,
        height: size.width * 0.3 * 4 / 3,
      );

  M3ECardContainerTransform.show<void>(
    context: context,
    origin: origin,
    // 从条目 / 按钮长出来时贴合它自己的圆角，观感更连续。
    originRadius: rectFromKey == null ? 12 : 10,
    originColor: scheme.surfaceContainerLow,
    builder: (_) => AlbumDetailScreen(albumId: albumId),
  );
}
