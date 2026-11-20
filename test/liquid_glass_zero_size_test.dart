import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

/// 回归：液态玻璃在尺寸过渡态（横竖屏切换、窗口被压到 0）下，玻璃面板的
/// `covered` 矩形会塌缩到 0，`_snapshot` 的 `toImageSync(0, h)` 抛
/// `Invalid image dimensions`（红屏）。
///
/// 修复：
/// * `_place`：`covered.isEmpty` 时跳过该面板；
/// * `_snapshot`：尺寸不足 1px 时不再用 0 调 `toImageSync`。
void main() {
  setUp(() {
    LiquidGlassHost.debugCaptures = 0;
    LiquidGlassHost.debugLastCapture = null;
  });

  Widget app({required Widget child}) => prism.PrismApp(
        theme: prism.ThemeData(brightness: Brightness.light),
        liquidGlass: LiquidGlassQuality.ultra,
        home: child,
      );

  Widget pane(double size) => ColoredBox(
        color: const Color(0xFF336699),
        child: LiquidGlass(
          style: prism.LiquidGlassStyle.regular(
            prism.ThemeData(brightness: Brightness.light).colorScheme,
          ),
          child: SizedBox.square(dimension: size),
        ),
      );

  testWidgets('面板被压到 0 尺寸再恢复，不抛 Invalid image dimensions',
      (tester) async {
    await tester.pumpWidget(app(child: Center(child: pane(200))));
    await tester.pump();
    await tester.pump();

    // 正常尺寸下确实拍过快照，证明场景真的走到了 capture 路径。
    final before = LiquidGlassHost.debugLastCapture;
    expect(before, isNotNull);
    expect(before!.panes, isNotEmpty);
    for (final p in before.panes) {
      expect(p.atlas.width, greaterThan(0));
      expect(p.atlas.height, greaterThan(0));
    }

    // 过渡态：面板压成 0×0（covered 塌缩的瞬间）。
    await tester.pumpWidget(app(child: Center(child: pane(0))));
    await tester.pump();
    await tester.pump();

    // 恢复正常尺寸：清掉退化条目后的下一次 capture 也要正常。
    await tester.pumpWidget(app(child: Center(child: pane(200))));
    await tester.pump();
    await tester.pump();

    final after = LiquidGlassHost.debugLastCapture;
    expect(after, isNotNull);
    for (final p in after!.panes) {
      expect(p.atlas.width, greaterThan(0));
      expect(p.atlas.height, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('主题切换（ThemeCrossFade 的 capture 路径）不抛异常',
      (tester) async {
    var dark = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => prism.PrismApp(
          theme: prism.ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          liquidGlass: LiquidGlassQuality.ultra,
          home: Center(
            child: prism.PressSurface(
              fill: const Color(0x00000000),
              shape: prism.AppShape.full,
              onPressed: () => setState(() => dark = !dark),
              child: const Text('switch'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('switch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
