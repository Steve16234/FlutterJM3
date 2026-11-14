import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// 把当前的 Material [ThemeData] 桥接成 M3E 主题。
///
/// `material_3_expressive` 的组件（`M3ECard`、`M3EButton`、`M3ENavigationBar`…）
/// 都通过 `M3ETheme.of(context)` 取色 / 形状 / 字体，因此必须在 `MaterialApp`
/// 之上提供一层 `M3ETheme`。这里用 `M3EThemeData.fromMaterial` 从我们自己的
/// [ThemeData] 派生，保证种子色、明暗、字体与现有 UI 一致；同时按 [ThemeData]
/// 实例做缓存，避免每帧重建主题数据。
class M3EBridge extends StatelessWidget {
  const M3EBridge({super.key, required this.child});

  final Widget child;

  static ThemeData? _source;
  static M3EThemeData? _data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!identical(theme, _source) || _data == null) {
      _source = theme;
      _data = M3EThemeData.fromMaterial(theme);
    }
    return M3ETheme(data: _data!, child: child);
  }
}
