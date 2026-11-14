import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/data/models.dart';
import 'package:flutterjm/screens/album_detail_screen.dart';
import 'package:flutterjm/state/app_state.dart';
import 'package:flutterjm/theme/m3e_bridge.dart';
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

Widget _wrap(AppState app, Widget child) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      // M3ECard 依赖 M3ETheme.of(context)，和真实 App 一样这里桥接一层。
      builder: (context, inner) =>
          M3EBridge(child: inner ?? const SizedBox.shrink()),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('M3ECard：点卡片用容器变换打开作品页', (tester) async {
    final app = _app();

    await tester.pumpWidget(
      _wrap(
        app,
        SizedBox(
          width: 120,
          height: 220,
          child: OpenableAlbumCard(
            album: _album,
            imgHost: 'https://img.example',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(M3ECard), findsOneWidget);

    await tester.tap(find.byType(M3ECard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('没有卡片可飞时（JM 号直达）用 ContainerTransform 打开', (tester) async {
    final app = _app();

    await tester.pumpWidget(
      _wrap(
        app,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => openAlbumPreviewFromCenter(
              context,
              albumId: '1488098',
            ),
            child: const Text('直达'),
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
