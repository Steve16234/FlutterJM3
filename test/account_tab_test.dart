import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/screens/root_shell.dart';
import 'package:flutterjm/state/app_state.dart';

import 'support/fake_gateway.dart';

void main() {
  testWidgets('底栏第三页是登录页', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: RootShell()),
      ),
    );
    await tester.pump();

    // 四个页签，第三页是「登录」
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, <String>['发现', '书库', '登录', '设置']);

    // 点第三页 -> 直接是登录表单（不用再点一次）
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('禁漫账号'), findsOneWidget);
    expect(find.text('账号 / 邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('登录成功后第三页变成「我的」并显示账号', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway(loginData: loginOk)));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: RootShell()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('登录'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.enterText(find.byType(TextField).last, 'p@ss');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(app.loggedIn, isTrue);
    expect(find.text('tester'), findsOneWidget);
    expect(find.textContaining('UID 42'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '退出登录'), findsOneWidget);

    // 页签文案跟着变成「我的」
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, <String>['发现', '书库', '我的', '设置']);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('设置页不再有账号分组', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: RootShell()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('账号'), findsNothing);
    expect(find.text('页图缓存'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
