import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// 应用的界面规范层，全部建立在 prism_ui（FlClash 的设计系统）之上。
///
/// 这里只做一件事：把「一个种子色 + 明暗 + 配色风格」变成 prism 的
/// [ThemeData]。页面拿到的所有颜色、表面层级、圆角、字号都从这里派生，
/// 任何页面都不应该再自己写颜色常量或圆角数值。
///
/// 规范来源：FlClash 仓库的 `.agents/surfaces.md`（表面层级与状态色）
/// 与 `.agents/skills/ui-work/SKILL.md`（圆角与字体令牌）。
abstract final class PrismTheme {
  const PrismTheme._();

  /// 品牌种子色（禁漫红）。
  ///
  /// prism 的 `vivid` 风格会把它直接当作 primary，和 Apple 的 accent color
  /// 一样：开关、选中的勾、填充按钮都是这个红。
  static const Color seed = Color(0xFFE53935);

  /// 配色风格。`vivid` 是 prism 的默认值：primary 用种子色本身，表面保持近灰。
  static const ColorStyle style = ColorStyle.vivid;

  static final ThemeData _light = _build(Brightness.light);

  static final ThemeData _dark = _build(Brightness.dark);

  static ThemeData light() => _light;

  static ThemeData dark() => _dark;

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static ThemeData _build(Brightness brightness) {
    final scheme = seededColorScheme(
      seedColor: seed,
      brightness: brightness,
      style: style,
    );
    return ThemeData(
      colorScheme: scheme,
      // 纯黑模式：暗色下把表面压到 tone 0，和 FlClash 的设置项一致。
      // 目前跟随系统，不开放给用户，先留出这一层。
      elevatedColorScheme: scheme.elevated,
    );
  }
}

/// 迁移期桥接：在旧的 Material 界面之上提供 prism 的主题与表面层级。
///
/// 现在已经改成 [PrismApp]，这个 widget 只在少数「还没迁移完、但仍被
/// prism 页面包住」的角落用得上；迁移完成后可以删掉。
class PrismBridge extends StatelessWidget {
  const PrismBridge({
    super.key,
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 内容区永远坐落在 page 层级上，卡片 / 块 / 内嵌由组件自己向下取一层。
    return Theme(
      data: PrismTheme.of(brightness),
      child: SurfaceScope(level: SurfaceLevel.page, child: child),
    );
  }
}
