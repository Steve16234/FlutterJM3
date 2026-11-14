import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/screens/settings_screen.dart';
import 'package:flutterjm/state/app_state.dart';

void main() {
  testWidgets('设置页展示缓存占用，并可确认后清理', (tester) async {
    final app = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 缓存分组 + 占位文案（测试环境无磁盘目录，只有内存统计）
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('页图缓存'), findsOneWidget);
    expect(find.textContaining('看过的页会缓存在本地'), findsOneWidget);

    // 打开确认弹窗
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    expect(find.text('将删除已缓存的页图和章节列表，清理后再进入需要重新下载。'), findsOneWidget);

    // 确认清理
    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await tester.pumpAndSettle();
    expect(find.text('缓存已清理'), findsOneWidget);

    // 清理后回到「暂无缓存」
    expect(find.text('暂无缓存'), findsOneWidget);
  });

  testWidgets('取消清理不清空缓存', (tester) async {
    final app = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('缓存已清理'), findsNothing);
  });
}
