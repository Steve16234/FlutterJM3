import 'package:ios_liquid_glass/ios_liquid_glass.dart' as ilg;

/// 关闭液态玻璃（低性能模式）时，玻璃控件统一退回的磨砂档。
///
/// 顶栏圆钮、首页搜索胶囊 / 输入框共用这一份配置，保证「关玻璃」后
/// 三者的磨砂观感完全一致：BackdropFilter 模糊 + 跟随应用明暗的淡色。
const ilg.LiquidGlassStyle frostFallbackStyle = ilg.LiquidGlassStyle(
  nativeInterfaceStyle: ilg.LiquidGlassInterfaceStyle.theme,
);
