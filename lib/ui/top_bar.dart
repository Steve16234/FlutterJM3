import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart' as ilg;
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';
import 'glass_fallback.dart' show frostFallbackStyle;

/// 顶栏右侧动作的数据描述。页面只描述「图标 + 提示 + 回调」，
/// 由 [JmTopBar] 统一包成玻璃图标按钮。
@immutable
class JmBarAction {
  const JmBarAction({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
}

/// 顶栏玻璃按钮直径。
const double _buttonSize = 44;

/// 独立的 iOS 26 液态玻璃圆形图标按钮。
///
/// 顶栏右侧的动作和首页顶部那种「自己排一行」的玻璃按钮都用它：
/// - 液态玻璃开启（未开低性能模式）：prism 的 [LiquidGlass] 圆形透镜，
///   色散 + 折射 + 磨砂，和搜索胶囊 / dock 是同一套 shader；
/// - 关闭（低性能模式）：ios_liquid_glass 的磨砂按钮，走 BackdropFilter，
///   不吃 shader，性能友好。
///
/// 按钮尺寸 44dp，符合 iOS 26 触控目标。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback onPressed;

  /// 图标着色（收藏 / 关注这类选中态用 primary 高亮）。null 走主题默认色。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    if (LiquidGlassScope.of(context)) {
      return _LiquidIcon(
        glyph: glyph,
        tooltip: tooltip,
        onPressed: onPressed,
        iconColor: iconColor,
      );
    }
    return ilg.LiquidGlassIconButton(
      size: _buttonSize,
      iconSize: 22,
      style: frostFallbackStyle,
      icon: GlyphIcon(glyph, color: iconColor),
      semanticLabel: tooltip,
      onPressed: onPressed,
    );
  }
}

/// 顶栏：大标题 + 按低性能模式切换档位的玻璃控件。
///
/// 档位由全局 [LiquidGlassScope] 决定（设置页「低性能模式」语义反转为
/// `app.liquidGlass`）：
///
/// - **液态玻璃完全体**（未开低性能模式）：用 prism 的 [LiquidGlass]
///   （pill 透镜 + 色散 + 折射 + 磨砂，quality 由 [PrismApp] 的 ultra 档
///   决定），和搜索框、dock 是同一套 shader，真机上有真实折射。
/// - **磨砂玻璃**（开启低性能模式）：用 ios_liquid_glass 的
///   [ilg.LiquidGlassIconButton]，它的 frosted fallback 走 BackdropFilter
///   磨砂，不吃 shader，性能友好。
///
/// header 本体不画整条玻璃板；顶部一层滚动边缘效果让内容从下方滚过时
/// 渐进模糊淡出。实现 [PreferredSizeWidget]，直接作为 [PrismScaffold.bar]。
class JmTopBar extends StatelessWidget implements PreferredSizeWidget {
  const JmTopBar({
    super.key,
    required this.title,
    required this.showBack,
    required this.actions,
    required this.loading,
    required this.onBack,
    required this.backLabel,
  });

  final String? title;
  final bool showBack;
  final List<JmBarAction> actions;
  final ValueListenable<bool> loading;
  final VoidCallback onBack;
  final String backLabel;

  static const Color _brandStart = Color(0xFFE53935);
  static const Color _brandEnd = Color(0xFFFF8A65);

  @override
  Size get preferredSize =>
      Size.fromHeight(pageToolbarHeight + LoadingBar.extent);

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = top + pageToolbarHeight;
    return Semantics(
      container: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // 顶栏背景：只用与页面同色的渐变 scrim，末端完全透明地溶解，
          // 不画全宽玻璃板——大 pane 在深色下显脏，还会和内容出色差硬边。
          // 玻璃质感交给下面的小圆钮；内容从 scrim 背后滑过时渐隐。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: headerHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      SurfaceLevel.page.colorOf(scheme).withValues(alpha: 0.97),
                      SurfaceLevel.page.colorOf(scheme).withValues(alpha: 0.82),
                      SurfaceLevel.page.colorOf(scheme).withValues(alpha: 0),
                    ],
                    stops: const <double>[0, 0.45, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (showBack)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: backLabel,
                        child: _glassIcon(
                          context,
                          glyph: Glyphs.arrowBack,
                          tooltip: backLabel,
                          onPressed: onBack,
                        ),
                      ),
                    ),
                  Expanded(child: _title(context)),
                  const SizedBox(width: 8),
                  ..._actions(context),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: LoadingBar.extent,
            child: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, active, _) => LoadingBar(active: active),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (actions.isEmpty) return const <Widget>[];
    return <Widget>[
      for (final action in actions)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: action.tooltip,
            child: _glassIcon(
              context,
              glyph: action.glyph,
              tooltip: action.tooltip,
              onPressed: action.onPressed,
            ),
          ),
        ),
    ];
  }

  /// 按全局液态玻璃开关选择按钮材质（复用公共 [GlassIconButton]）。
  Widget _glassIcon(
    BuildContext context, {
    required Glyph glyph,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return GlassIconButton(
      glyph: glyph,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _title(BuildContext context) {
    final text = title;
    if (text == null) return const SizedBox.shrink();

    final scheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 5,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[_brandStart, _brandEnd],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.title1.of(context, emphasized: true).copyWith(
                  color: scheme.onSurface,
                  letterSpacing: -0.5,
                ),
          ),
        ),
      ],
    );
  }
}

/// 液态玻璃完全体圆形图标按钮：prism 的 pill 透镜（色散 + 折射 + 磨砂），
/// 圆形 clipper 让它成为一枚独立玻璃圆钮。按压时发光反馈。
class _LiquidIcon extends StatefulWidget {
  const _LiquidIcon({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  State<_LiquidIcon> createState() => _LiquidIconState();
}

class _LiquidIconState extends State<_LiquidIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // pill 本身就是透镜（负 refraction + 色散 + 磨砂），
    // 这里保持默认 full optics，只在按压时提亮，即「完全体」。
    final style = LiquidGlassStyle.pill(scheme);
    // 液态玻璃圆钮：GestureDetector / Listener 必须用 opaque 覆盖整块
    // 44dp 玻璃面。默认 deferToChild 只有中间的 22dp 图标能命中，
    // 就会出现「看到一大圈、只有中间能点」的错觉。
    return GestureDetector(
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          onTap: widget.onPressed,
          child: LiquidGlass(
            style: style,
            pressed: _pressed,
            clipper: const _CircleGlassClipper(),
            child: SizedBox(
              width: _buttonSize,
              height: _buttonSize,
              child: Center(
                child: GlyphIcon(widget.glyph, size: 22, color: widget.iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把玻璃裁成圆形（pill 透镜会沿圆形边缘弯折出高光与色散）。
class _CircleGlassClipper extends CustomClipper<Path> {
  const _CircleGlassClipper();

  @override
  Path getClip(Size size) => Path()..addOval(Offset.zero & size);

  @override
  bool shouldReclip(_CircleGlassClipper oldDelegate) => false;
}
