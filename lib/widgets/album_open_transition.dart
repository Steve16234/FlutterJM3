import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../screens/album_detail_screen.dart';

/// 没有卡片可飞时的打开方式（例如搜索框输入 JM 号直达、点子分类 chip）。
///
/// 关键点：**起点必须是用户真正点到的那个控件**。
/// 传 [originKey]（绑在按钮 / 条目上的 [GlobalKey]），转场就从它的实际矩形
/// 长出来；拿不到时才退回一个居中矩形。
///
/// 早期版本固定用一个「屏幕中上方」的虚拟矩形，结果转场开始的位置和手指
/// 点下去的位置对不上，看起来像凭空冒出一张卡片 —— 和点击行为是割裂的。
///
/// 为什么不是 prism 的 `OpenContainer`：它的 `zoom` 变换量的是**关闭态子组件**
/// 在当前 widget 树里的矩形，要求那个子组件就长在起始控件的位置上。这里的调用点
/// （首页搜索栏 / 搜索面板）不在本文件的作用域里，无法把起始控件包进
/// `OpenContainer`，所以保留「自定义 [PageRouteBuilder] + 矩形到全屏的形变」这一
/// 纯表现层实现，只把颜色 / 圆角 / 时长换成 prism 的令牌。锚点语义（从被点控件
/// 的 `RenderBox` 矩形出发）与旧实现完全一致。
Future<void> openAlbumPreviewFromCenter(
  BuildContext context, {
  required String albumId,
  GlobalKey? originKey,
}) async {
  final size = MediaQuery.sizeOf(context);
  final scheme = context.colorScheme;

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

  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      // 形变过程中要能看见下面的页面，所以不是 opaque 路由；
      // 形变走完之后矩形已经铺满全屏。
      opaque: false,
      barrierColor: null,
      barrierDismissible: false,
      transitionDuration: commonDuration,
      reverseTransitionDuration: commonDuration,
      transitionsBuilder: (_, _, _, child) => child,
      pageBuilder: (context, animation, secondaryAnimation) => _ContainerMorph(
        animation: animation,
        origin: origin,
        // 从条目 / 按钮长出来时贴合它自己的圆角（小控件 → `sm`；
        // 兜底矩形 → `md`）。旧实现用的是 10 / 12 两个裸数字。
        originRadius: rectFromKey == null ? AppCorner.md : AppCorner.sm,
        // 起点填色取「卡片」层：被点的控件（chip / 搜索栏）本身就是一层卡片表面。
        originColor: SurfaceLevel.card.colorOf(scheme),
        // 终点填色 = 页面层的颜色，也就是详情页自己的底色。
        openColor: SurfaceLevel.page.colorOf(scheme),
        // 铺满全屏时的圆角跟随屏幕圆角（Android 12+ / iOS 上报了才有，否则为 0）。
        endRadius: displayRadiusOf(context).topLeft.x,
        child: AlbumDetailScreen(albumId: albumId),
      ),
    ),
  );
}

/// 一个矩形从被点控件长成整页的形变。
///
/// 和 prism 自己的容器变换（`open_container.dart` 的 `_RenderContainerTransition`）
/// 同一套做法：**页面按最终尺寸布局一次，之后只靠「矩形 + 裁剪 + 缩放」绘制**，
/// 形变期间不重建、也不重新布局详情页。旧实现每帧按当前矩形重新布局，
/// 详情页里的 `SliverAppBar` / 网格会跟着抖动；这里换成了 prism 的做法，
/// 到 `t == 1` 时缩放为 1、矩形铺满全屏，静态结果完全一致。
class _ContainerMorph extends StatelessWidget {
  const _ContainerMorph({
    required this.animation,
    required this.origin,
    required this.originRadius,
    required this.originColor,
    required this.openColor,
    required this.endRadius,
    required this.child,
  });

  final Animation<double> animation;
  final Rect origin;
  final double originRadius;
  final Color originColor;
  final Color openColor;
  final double endRadius;
  final Widget child;

  /// 页面开始淡入的进度；旧实现是 `contentFadeStart = 0.4`，保持一致。
  static const double _contentFadeStart = 0.4;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedBuilder(
          animation: animation,
          // 详情页只建一次，形变里每帧只改绘制参数。
          child: child,
          builder: (context, child) {
            final t = animation.value.clamp(0.0, 1.0);
            // 矩形的位置/大小先快后慢地长开；圆角、填色、内容淡入用更缓的曲线，
            // 避免前半程就看出「一张缩小的页面」。
            final stretch = Curves.easeOutCubic.transform(t);
            final rect = Rect.lerp(origin, Offset.zero & size, stretch)!;
            final radius = BorderRadius.all(
              Radius.circular(
                lerpDouble(originRadius, endRadius, stretch)!,
              ),
            );
            final fill =
                Color.lerp(originColor, openColor, Curves.easeOut.transform(t))!;
            final span = 1 - _contentFadeStart;
            final opacity = Curves.easeOut.transform(
              ((t - _contentFadeStart) / span).clamp(0.0, 1.0),
            );
            return Positioned.fromRect(
              rect: rect,
              child: ClipRSuperellipse(
                borderRadius: radius,
                child: ColoredBox(
                  color: fill,
                  child: OverflowBox(
                    // 页面按整屏尺寸布局，再整体缩放进当前矩形。
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: Transform.scale(
                      scale: rect.width / size.width,
                      alignment: Alignment.topLeft,
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
