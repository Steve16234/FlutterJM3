import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/data/models.dart';
import 'package:flutterjm/screens/album_detail_screen.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/prism_host.dart';
import 'package:flutterjm/ui/album_card.dart';
import 'package:flutterjm/widgets/album_open_transition.dart';
import 'package:flutterjm/widgets/openable_album.dart';

import 'support/fake_gateway.dart';

AppState _app() => AppState(
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

final AlbumSummary _album = AlbumSummary.fromJson(<String, dynamic>{
  'id': '1488098',
  'name': '测试作品',
  'image': '',
});

/// MaterialApp 只当导航脚手架；prism 运行环境（主题 / 表面 / ViewScope /
/// MeasureScope / BannerHost）由 PrismHost 提供。
///
/// `imgHost` 在用例里传空串，封面走「没拿到 CDN 前缀」的占位分支，不会联网。
Widget _wrap(AppState app, Widget child) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JmUiLocalizations.delegate,
      ],
      builder: (context, inner) => PrismHost(
        brightness: Brightness.light,
        child: inner ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('Card：点卡片用容器变换打开作品页', (tester) async {
    final app = _app();

    await tester.pumpWidget(
      _wrap(
        app,
        SizedBox(
          width: 120,
          height: 220,
          child: OpenableAlbumCard(album: _album, imgHost: ''),
        ),
      ),
    );
    await tester.pump();

    // 卡片壳是 prism 的 `Card`（旧断言是 M3ECard）。
    expect(find.byType(prism.Card), findsOneWidget);
    expect(find.byType(AlbumCard), findsOneWidget);

    await tester.tap(find.byType(prism.Card));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('没有卡片可飞时（JM 号直达）从被点控件的矩形展开', (tester) async {
    final app = _app();
    final originKey = GlobalKey();

    await tester.pumpWidget(
      _wrap(
        app,
        Builder(
          builder: (context) => SizedBox(
            key: originKey,
            width: 120,
            height: 40,
            child: prism.FilledButton(
              onPressed: () => openAlbumPreviewFromCenter(
                context,
                albumId: '1488098',
                originKey: originKey,
              ),
              child: const Text('直达'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('直达'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
