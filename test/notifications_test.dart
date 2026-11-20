import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// 应用仍跑在 MaterialApp 里（迁移期），但 prism 组件要的只是这一层壳：
// 主题 / 表面层级 / ViewScope / BannerHost 全由 PrismHost 提供。
import 'package:material_ui/material_ui.dart' show MaterialApp;
// 断言的是 **prism_ui** 的 SelectableText（同名但来自另一个库）：
// Material 的那个已经不在这条链路上了，所以这里显式只导入 prism 的。
import 'package:prism_ui/prism_ui.dart' show SelectableText;
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/data/models.dart';
import 'package:flutterjm/screens/notifications_screen.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/prism_host.dart';

import 'support/fake_gateway.dart';

/// 线上真实形态：正文是 `<p>` + `\r\n` 混排的 HTML。
const String _realContent =
    '<p>亲爱的用户您好：</p>\r\n\r\n<p>禁漫广告现已新增「信用卡支付」渠道，'
    '您可于付款页面选择使用。</p>\r\n\r\n<p><strong>提醒：需额外负担 8% 手续费'
    '</strong></p>';

/// prism 的组件要从 [PrismHost] 取运行环境（ViewScope / MeasureScope /
/// BannerHost / prism 主题），`showSnapSheet` 还要 `JmUiLocalizations`。
Widget _app(AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JmUiLocalizations.delegate,
      ],
      builder: (context, child) => PrismHost(
        brightness: Brightness.light,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const NotificationsScreen(),
    ),
  );
}

void main() {
  test('htmlToPlainText 去掉 CR，只留可读正文', () {
    final text = htmlToPlainText(_realContent);

    expect(text, contains('亲爱的用户您好：'));
    expect(text, contains('信用卡支付'));
    expect(text, isNot(contains('<')));
    expect(text, isNot(contains('\r')), reason: '剩余 \\r 会在 Text 里画成空行');
  });

  testWidgets('通知列表显示正文，点开可看全文', (tester) async {
    final app = AppState(
      client: GatewayClient(
        client: fakeGateway(
          responses: <String, dynamic>{
            'notifications': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': '21537413',
                'type': 'site_notice',
                'title': '禁漫广告新增信用卡支付',
                'content': _realContent,
                'date': '2026-10-21',
                'read': true,
              },
            ],
          },
        ),
      ),
    );

    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();

    // 标题 + 正文摘要都在
    expect(find.text('禁漫广告新增信用卡支付'), findsOneWidget);
    expect(find.textContaining('亲爱的用户您好'), findsOneWidget);
    expect(find.text('2026-10-21'), findsOneWidget);

    // 点开看全文（prism 的可拖拽 sheet）
    await tester.tap(find.text('禁漫广告新增信用卡支付'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
