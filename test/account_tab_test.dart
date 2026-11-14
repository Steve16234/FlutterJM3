import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/screens/root_shell.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/m3e_bridge.dart';

import 'support/fake_gateway.dart';

Widget _shell(AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      builder: (context, inner) =>
          M3EBridge(child: inner ?? const SizedBox.shrink()),
      home: const RootShell(),
    ),
  );
}

List<String?> _labels(WidgetTester tester) {
  final bar = tester.widget<M3ENavigationBar>(find.byType(M3ENavigationBar));
  return bar.destinations.map((d) => d.label).toList();
}

void main() {
  testWidgets('底栏第三页是登录页', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    // M3E 导航栏，四个目的页，第三个是「登录」
    expect(find.byType(M3ENavigationBar), findsOneWidget);
    expect(_labels(tester), <String?>['发现', '书库', '登录', '设置']);

    // 点第三页 -> 直接是登录表单（不用再点一次）
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('禁漫账号'), findsOneWidget);
    expect(find.text('账号 / 邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('登录成功后第三页变成「我的」并显示账号', (tester) async {
    final app = AppState(
      client: GatewayClient(client: fakeGateway(loginData: loginOk)),
    );

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.enterText(find.byType(TextField).last, 'p@ss');
    await tester.tap(find.widgetWithText(M3EButton, '登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(app.loggedIn, isTrue);
    expect(find.text('tester'), findsOneWidget);
    expect(find.textContaining('UID 42'), findsOneWidget);
    expect(find.widgetWithText(M3EButton, '退出登录'), findsOneWidget);

    // 页签文案跟着变成「我的」
    expect(_labels(tester), <String?>['发现', '书库', '我的', '设置']);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('设置页不再有账号分组', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('账号'), findsNothing);
    expect(find.text('页图缓存'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
