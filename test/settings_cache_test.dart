import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/screens/settings_screen.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/prism_host.dart';

/// 设置页的测试外壳：**和 `main.dart` 一样**的运行时环境。
///
/// prism 的组件依赖 `ViewScope` / `MeasureScope` / `BannerHost` / 本地化，
/// 迁移期这些都由 `PrismHost` 提供（`lib/theme/prism_host.dart`）；
/// `MaterialApp` 只负责 Navigator / Directionality / 系统代理，页面本身
/// 一个 Material 组件都不用。
Widget _shell({required AppState app, Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JmUiLocalizations.delegate,
      ],
      builder: (context, navigator) => PrismHost(
        brightness: brightness,
        child: navigator ?? const SizedBox.shrink(),
      ),
      home: const SettingsScreen(),
    ),
  );
}

/// 竖屏手机宽度；设置页是长列表，窄宽度最容易暴露溢出。
void _phoneSurface(WidgetTester tester, {double width = 390}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// 提示条（`BannerHost`）自带 3~6 秒的自动消失定时器与进出场动画，
/// 断言完之后要把时间推过去，否则测试结束时会留下未完成的定时器。
Future<void> _drainBanners(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 7));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('设置页展示缓存占用，并可确认后清理', (tester) async {
    _phoneSurface(tester);
    final app = AppState();

    await tester.pumpWidget(_shell(app: app));
    await tester.pumpAndSettle();

    // 缓存分组 + 占位文案（测试环境无磁盘目录，只有内存统计）
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('页图缓存'), findsOneWidget);
    expect(find.textContaining('看过的页会缓存在本地'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 打开确认弹窗
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    expect(find.text('将删除已缓存的页图和章节列表，清理后再进入需要重新下载。'), findsOneWidget);

    // 确认清理：prism 的 `AlertDialog` 用 prism 的按钮（`FilledButton` = 默认动作）
    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await tester.pumpAndSettle();
    expect(find.text('缓存已清理'), findsOneWidget);

    // 清理后回到「暂无缓存」
    expect(find.text('暂无缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _drainBanners(tester);
  });

  testWidgets('取消清理不清空缓存', (tester) async {
    _phoneSurface(tester);
    final app = AppState();

    await tester.pumpWidget(_shell(app: app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    // 取消动作 = prism 的 `TextButton`
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('缓存已清理'), findsNothing);
    // 弹窗确实关掉了（不是只把提示藏起来）
    expect(find.text('将删除已缓存的页图和章节列表，清理后再进入需要重新下载。'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
