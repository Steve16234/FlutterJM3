import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ViewScope / LiquidGlassScope 不在 prism_ui 的 barrel 里，单独引。
import 'package:prism_ui/liquid_glass.dart'
    show LiquidGlassQuality, LiquidGlassScope;
import 'package:prism_ui/prism_ui.dart' as prism;

import 'package:flutterjm/theme/prism_host.dart';
import 'package:flutterjm/theme/prism_theme.dart';

/// 验证液态玻璃开关确实开启了 LiquidGlassScope。
///
/// PrismApp 不传 liquidGlass 时 scope 为 false（组件退回普通填充）；传了
/// standard/ultra 才为 true（dock / bar 按钮 / 搜索框 / 弹层走 shader）。
void main() {
  Widget app({prism.LiquidGlassQuality? glass, required Widget child}) =>
      prism.PrismApp(
        theme: PrismTheme.light(),
        darkTheme: PrismTheme.dark(),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          JmUiLocalizations.delegate,
        ],
        liquidGlass: glass,
        builder: (context, navigator) =>
            JmViewScope(child: navigator ?? const SizedBox.shrink()),
        home: child,
      );

  testWidgets('开启液态玻璃后 LiquidGlassScope 生效（ultra 完整效果）',
      (tester) async {
    await tester.pumpWidget(app(
      glass: LiquidGlassQuality.ultra,
      child: const _Probe(),
    ));
    await tester.pump();

    expect(find.text('glass=true quality=LiquidGlassQuality.ultra'),
        findsOneWidget);
  });

  testWidgets('不传液态玻璃时 scope 关闭（普通填充）', (tester) async {
    await tester.pumpWidget(app(child: const _Probe()));
    await tester.pump();

    expect(find.text('glass=false'), findsOneWidget);
  });
}

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final on = LiquidGlassScope.of(context);
    final q = on ? LiquidGlassScope.qualityOf(context) : null;
    return Text('glass=$on${q != null ? ' quality=$q' : ''}');
  }
}
