import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/screens/root_shell.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/prism_host.dart';

import 'support/fake_gateway.dart';

Widget _shell(AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JmUiLocalizations.delegate,
      ],
      builder: (context, inner) => PrismHost(
        brightness: Theme.of(context).brightness,
        child: inner ?? const SizedBox.shrink(),
      ),
      home: const RootShell(),
    ),
  );
}

/// 手机宽度读 NavigationDock，桌面宽度读 NavigationSidebar。
/// 默认测试视口 800 宽会走侧栏，所以这里强制设成手机视口。
List<String> _labels(WidgetTester tester) {
  final dock = tester.widget<prism.NavigationDock>(
    find.byType(prism.NavigationDock),
  );
  return dock.destinations.map((d) => d.label).toList();
}

/// RootShell 用 context.isMobileView（断点 720）决定 dock / 侧栏；
/// 默认测试视口 800 宽会走侧栏，所以每个测试强制设成手机视口。
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('底栏第三页是登录页', (tester) async {
    _phoneView(tester);
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    expect(find.byType(prism.NavigationDock), findsOneWidget);
    expect(_labels(tester), <String>['发现', '书库', '登录', '设置']);

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
    _phoneView(tester);
    final app = AppState(
      client: GatewayClient(client: fakeGateway(loginData: loginOk)),
    );

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // prism 的 TextField 与 material 的同名不同型，用 hint 文案定位更稳。
    await tester.enterText(find.byWidgetPredicate(
      (w) => w is prism.TextField && w.decoration?.hintText == '账号 / 邮箱',
    ), 'tester');
    await tester.enterText(find.byWidgetPredicate(
      (w) => w is prism.TextField && w.decoration?.hintText == '密码',
    ), 'p@ss');
    await tester.tap(find.widgetWithText(prism.FilledButton, '登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(app.loggedIn, isTrue);
    expect(find.text('tester'), findsOneWidget);
    expect(find.textContaining('UID 42'), findsOneWidget);
    // 退出登录现在是危险色的 SettingRow（旧版是 TextButton）。
    expect(find.text('退出登录'), findsOneWidget);

    // 页签文案跟着变成「我的」
    expect(_labels(tester), <String>['发现', '书库', '我的', '设置']);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('设置页不再有账号分组', (tester) async {
    _phoneView(tester);
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
