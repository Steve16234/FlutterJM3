import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutterjm/core/image_loader.dart';
import 'package:flutterjm/core/page_cache.dart';

const String _url = 'https://cdn.example.com/1488098/00001.webp';

/// 现画一张 2x2 PNG 作为网络返回体，保证是合法图片数据。
Future<Uint8List> _pngBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(2, 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List png;

  setUpAll(() async {
    png = await _pngBytes();
  });

  PageImageLoader loaderWith(MockClient client) => PageImageLoader(
        client: client,
        cache: PageCache(imageBudgetBytes: 64 << 20),
      );

  test('同一页第二次加载不再发起网络请求', () async {
    var requests = 0;
    final loader = loaderWith(MockClient((request) async {
      requests++;
      return http.Response.bytes(png, 200);
    }));

    // aid < scramble_id，不做乱序还原
    final image = await loader.load(url: _url, aid: 1000, scrambleId: 220980);
    expect(image.width, 2);
    loader.release(_url);
    expect(requests, 1);

    final cached = await loader.load(url: _url, aid: 1000, scrambleId: 220980);
    expect(cached, same(image));
    expect(requests, 1, reason: '第二次应命中缓存');
    loader.release(_url);
  });

  test('prefetch 之后 load 直接命中，且只请求一次', () async {
    var requests = 0;
    final loader = loaderWith(MockClient((request) async {
      requests++;
      return http.Response.bytes(png, 200);
    }));

    await loader.prefetch(url: _url, aid: 1000, scrambleId: 220980);
    expect(requests, 1);

    await loader.load(url: _url, aid: 1000, scrambleId: 220980);
    loader.release(_url);
    expect(requests, 1);
  });

  test('并发加载同一页只下载一次', () async {
    var requests = 0;
    final loader = loaderWith(MockClient((request) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response.bytes(png, 200);
    }));

    final results = await Future.wait(<Future<ui.Image>>[
      loader.load(url: _url, aid: 1000, scrambleId: 220980),
      loader.load(url: _url, aid: 1000, scrambleId: 220980),
    ]);
    expect(requests, 1);
    expect(results[0], same(results[1]));
    loader.release(_url);
    loader.release(_url);
  });

  test('HTTP 非 200 抛错', () async {
    final loader = loaderWith(
      MockClient((request) async => http.Response('', 404)),
    );
    await expectLater(
      loader.load(url: _url, aid: 1000, scrambleId: 220980),
      throwsA(isA<StateError>()),
    );
  });
}
