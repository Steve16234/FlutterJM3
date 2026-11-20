import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:provider/provider.dart';

import 'package:flutterjm/core/comic_query.dart';
import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/screens/album_detail_screen.dart';
import 'package:flutterjm/screens/home_screen.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/prism_host.dart';

import 'support/fake_gateway.dart';

/// 和 main.dart 一样，给 prism 组件补上 ViewScope / MeasureScope / BannerHost。
Widget _shell(Widget child) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    JmUiLocalizations.delegate,
  ],
  builder: (context, inner) => PrismHost(
    brightness: Theme.of(context).brightness,
    child: inner ?? const SizedBox.shrink(),
  ),
  home: child,
);

void main() {
  group('albumIdFromQuery', () {
    test('纯数字直接当作品号', () {
      expect(albumIdFromQuery('1488098'), '1488098');
      expect(albumIdFromQuery('  1488098  '), '1488098');
    });

    test('支持 JM 前缀与分隔符', () {
      expect(albumIdFromQuery('JM1488098'), '1488098');
      expect(albumIdFromQuery('jm 1488098'), '1488098');
      expect(albumIdFromQuery('jm-1488098'), '1488098');
      expect(albumIdFromQuery('#1488098'), '1488098');
    });

    test('普通关键词不当作作品号', () {
      expect(albumIdFromQuery('黑客'), isNull);
      expect(albumIdFromQuery('123'), isNull, reason: '少于 4 位不当 id');
      expect(albumIdFromQuery('1488098abc'), isNull);
      expect(albumIdFromQuery(''), isNull);
    });
  });

  testWidgets('搜索框输入作品号直达作品页', (tester) async {
    final app = AppState(
      client: GatewayClient(
        client: fakeGateway(
          responses: <String, dynamic>{
            'album': <String, dynamic>{
              'id': '1488098',
              'name': '测试作品',
              'total_photos': 2,
            },
          },
        ),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: _shell(const HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 展开搜索并输入作品号。prism 的 TextField 与 material 的同名不同型，
    // 用「搜索」文案展开，再用 prism 类型定位输入框。
    await tester.tap(find.text('搜索'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(prism.TextField).first, 'JM1488098');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    expect(app.searchHistory.first, 'JM1488098');

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
