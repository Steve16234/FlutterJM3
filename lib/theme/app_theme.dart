import 'package:material_ui/material_ui.dart';

/// Material 3 主题。使用 Android 12+ 动态取色，回退到品牌种子色。
class AppTheme {
  const AppTheme._();

  /// 品牌种子色（禁漫红）。
  static const Color seed = Color(0xFFE53935);

  /// 缓存好的固定主题。
  ///
  /// `ColorScheme.fromSeed` 要跑一遍 Material 调色算法（实测 ~0.8ms / 次，
  /// 深浅两套 ~1.6ms，debug 模式下更慢）。之前每次 rebuild 都新构建一遍，
  /// 一旦有状态变更（点按钮、切主题、切页签）就会白白吃掉一帧。
  static final ThemeData _light = _build(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  );
  static final ThemeData _dark = _build(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  );

  /// [dynamicScheme] 为空时返回缓存实例（identical）。
  static ThemeData light(ColorScheme? dynamicScheme) =>
      dynamicScheme == null ? _light : _build(dynamicScheme);

  static ThemeData dark(ColorScheme? dynamicScheme) =>
      dynamicScheme == null ? _dark : _build(dynamicScheme);

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Android 原生风格的页面转场：默认使用平台的预测式返回动画。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 3,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surfaceContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
