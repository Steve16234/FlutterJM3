// 临时验证：把原图与还原图分别存成 PNG，肉眼/像素比对哪个是完整图。用完即删。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterjm/core/image_unscramble.dart';

const aid = 1488098;

Future<void> savePng(ui.Image img, String path) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
}

void main() {
  test('dump raw vs unscrambled', () async {
    final client = http.Client();
    const page = '00001';
    final url =
        'https://cdn-msp.jmdanjonproxy.xyz/media/photos/$aid/$page.webp';
    final res = await client.get(Uri.parse(url), headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      'Referer': 'https://18comic.vip/',
    });
    final codec = await ui.instantiateImageCodec(res.bodyBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    await savePng(img, 'tool/page_raw.png');

    for (final num in <int>[8, 12, 14, 16, 20]) {
      final un = await ImageUnscrambler.unscramble(img, num);
      await savePng(un, 'tool/page_un_$num.png');
    }

    // ignore: avoid_print
    print('saved raw + 5 variants, src=${img.width}x${img.height}');
    client.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
