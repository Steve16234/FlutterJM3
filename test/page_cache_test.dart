import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/page_cache.dart';

/// 直接画出来的 1x1 图，避免依赖外部图片资源。
Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xFF3366FF),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory cacheDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jm_page_cache_test');
    cacheDir = Directory('${tmp.path}/jm_pages');
    await cacheDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('磁盘层：第二个实例（模拟重启）仍能命中', () async {
    final first = PageCache(directory: cacheDir);
    await first.writeBytes('u1', Uint8List.fromList(<int>[1, 2, 3, 4]));

    final second = PageCache(
      directory: cacheDir,
      byteBudgetBytes: 0, // 内存层放不下，只能读磁盘
    );
    expect(await second.readBytes('u1'), <int>[1, 2, 3, 4]);
  });

  test('内存字节层：超出预算淘汰最久未用', () async {
    final cache = PageCache(
      directory: Directory('${tmp.path}/missing'), // 磁盘不可用
      byteBudgetBytes: 6,
    );
    await cache.writeBytes('a', Uint8List(4));
    await cache.writeBytes('b', Uint8List(4));
    expect(await cache.readBytes('a'), isNull, reason: 'a 应已被淘汰');
    expect(await cache.readBytes('b'), isNotNull);
  });

  test('解码图：被引用时淘汰不会释放，归还后才释放', () async {
    final cache = PageCache(imageBudgetBytes: 4); // 只放得下 1 张 1x1
    final imageA = await _tinyImage();
    cache.putImage('a', imageA);
    expect(cache.hasImage('a'), isTrue);
    expect(cache.obtainImage('a'), same(imageA)); // refs = 1

    final imageB = await _tinyImage();
    cache.putImage('b', imageB); // 超预算，a 被钉住

    expect(imageA.debugDisposed, isFalse, reason: '显示中的图被释放会导致崩溃');

    cache.releaseImage('a');
    expect(imageA.debugDisposed, isTrue, reason: '归还引用后应释放');
  });

  test('解码图：淘汰后重新 obtain 会复活，不会被误释放', () async {
    final cache = PageCache(imageBudgetBytes: 4);
    final imageA = await _tinyImage();
    cache.putImage('a', imageA);
    cache.obtainImage('a');

    cache.putImage('b', await _tinyImage());
    expect(cache.obtainImage('a'), same(imageA), reason: '淘汰但未释放，仍可复用');

    cache.releaseImage('a');
    cache.releaseImage('a');
    expect(imageA.debugDisposed, isFalse, reason: '复活后应作为普通缓存保留');
    expect(cache.hasImage('a'), isTrue);
  });

  test('解码图：obtain/release 配对后仍留在缓存里', () async {
    final cache = PageCache(imageBudgetBytes: 64 << 20);
    final image = await _tinyImage();
    cache.putImage('a', image);

    expect(cache.obtainImage('a'), same(image));
    cache.releaseImage('a');

    expect(cache.hasImage('a'), isTrue);
    expect(image.debugDisposed, isFalse);
    expect(cache.obtainImage('a'), same(image));
  });

  test('usage() 统计磁盘/内存占用，clear() 后归零', () async {
    final cache = PageCache(directory: cacheDir);
    await cache.writeBytes('a', Uint8List(100));
    await cache.writeBytes('b', Uint8List(50));

    final usage = await cache.usage();
    expect(usage.diskBytes, 150);
    expect(usage.byteBytes, 150);
    expect(usage.totalBytes, 300);

    await cache.clear();
    final cleared = await cache.usage();
    expect(cleared.diskBytes, 0);
    expect(cleared.totalBytes, 0);
  });

  test('usage() 统计解码图占用', () async {
    final cache = PageCache(imageBudgetBytes: 64 << 20);
    cache.putImage('a', await _tinyImage());
    expect((await cache.usage()).imageBytes, 4);
  });

  test('clear() 不会释放正在显示的图', () async {
    final cache = PageCache(directory: cacheDir);
    final image = await _tinyImage();
    cache.putImage('a', image);
    cache.obtainImage('a');

    await cache.clear();
    expect(image.debugDisposed, isFalse);

    cache.releaseImage('a');
    expect(image.debugDisposed, isTrue);
  });
}
