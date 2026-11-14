import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/screens/album_detail_screen.dart';
import 'package:flutterjm/screens/home_screen.dart';
import 'package:flutterjm/state/app_state.dart';

import 'support/fake_gateway.dart';

void main() {
  testWidgets('点搜索历史里的 JM 号直达作品页', (tester) async {
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
    app.addSearchHistory('JM1488098');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 展开搜索 -> 出现搜索历史 -> 点那条 JM 号
    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('JM1488098'), findsOneWidget);

    await tester.tap(find.text('JM1488098'));
    // 先跑完“文字飞入 → 搜索框铺满”的 morph，再等转场完成
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('点搜索历史里的普通关键词仍然走搜索', (tester) async {
    final app = AppState(client: GatewayClient(client: fakeGateway()));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    app.addSearchHistory('催眠');
    await tester.pump();

    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('催眠'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));

    // 不应跳作品页，而是留在搜索面板里
    expect(find.byType(AlbumDetailScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
