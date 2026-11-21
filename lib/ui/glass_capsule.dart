import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// 悬浮胶囊容器。
///
/// 用来替代「贴屏幕边缘的整条玻璃」：胶囊四周留白、完全圆角、带一点投影，
/// 浮在内容之上，而不是一条横贯屏幕的大玻璃板。
///
/// - 液态玻璃开启：prism 的 [LiquidGlass] 胶囊（弱透镜 + 轻微雾化），
///   和搜索胶囊 / dock 同一套 shader；
/// - 关闭（低性能模式）：实底浮动胶囊（`SurfaceLevel.floatingOf` + 阴影），
///   与普通浮层一致。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.child,
    this.height = 56,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;

  /// 胶囊高度，圆角取它的一半，保证两端是完整的半圆。
  final double height;

  /// 胶囊外留白（由调用方给安全区 + 边距）。
  final EdgeInsetsGeometry margin;

  static const double _elevation = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final radius = height / 2;
    final content = SizedBox(height: height, child: child);

    final Widget surface;
    if (LiquidGlassScope.of(context)) {
      // 和 prism 的 glass header 同一档：弱透镜 + 轻微雾化，整条不放大内容。
      final style = LiquidGlassStyle.pill(
        scheme,
      ).copyWith(blur: 0, hazeBlur: 12);
      surface = LiquidGlass(
        style: style,
        borderRadius: BorderRadius.circular(radius),
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
        child: content,
      );
    } else {
      final level = SurfaceLevel.floatingOf(scheme);
      surface = Surface(
        color: level.colorOf(scheme),
        shape: AppShape.full,
        elevation: _elevation,
        child: SurfaceScope(level: level, child: content),
      );
    }

    return Padding(padding: margin, child: surface);
  }
}
