// 临时验证：穷举分段数，找出让「还原后接缝消失」的正确 num。用完即删。
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterjm/core/image_unscramble.dart';

const aid = 1488098;

/// 按 num 段划分的边界处，相邻行差异 / 段内相邻行差异。
Future<double> boundaryRatio(ui.Image img, int num) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final w = img.width;
  final h = img.height;
  final rowBytes = w * 4;

  double rowDiff(int y0, int y1) {
    var sum = 0;
    final a = y0 * rowBytes;
    final b = y1 * rowBytes;
    for (var x = 0; x < rowBytes; x += 16) {
      sum += (bytes[a + x] - bytes[b + x]).abs();
      sum += (bytes[a + x + 1] - bytes[b + x + 1]).abs();
      sum += (bytes[a + x + 2] - bytes[b + x + 2]).abs();
    }
    return sum / (w / 4 * 3);
  }

  final move = h ~/ num;
  final over = h % num;
  final boundaries = <int>{};
  for (var i = 1; i < num; i++) {
    boundaries.add(move * i + over);
  }

  var bSum = 0.0;
  var bCount = 0;
  var iSum = 0.0;
  var iCount = 0;
  for (var y = 1; y < h; y++) {
    if (y % 3 != 0) continue; // 抽样加速
    final d = rowDiff(y - 1, y);
    if (boundaries.contains(y)) {
      bSum += d;
      bCount++;
    } else {
      iSum += d;
      iCount++;
    }
  }
  final bAvg = bCount == 0 ? 0.0 : bSum / bCount;
  final iAvg = iCount == 0 ? 1.0 : iSum / iCount;
  return iAvg == 0 ? 0 : bAvg / iAvg;
}

void main() {
  test('穷举 num', () async {
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

    for (var num = 2; num <= 20; num += 2) {
      final rawRatio = await boundaryRatio(img, num);
      final un = await ImageUnscrambler.unscramble(img, num);
      final unRatio = await boundaryRatio(un, num);
      // ignore: avoid_print
      print('num=$num  raw=${rawRatio.toStringAsFixed(2)}'
          '  unscrambled=${unRatio.toStringAsFixed(2)}'
          '  improvement=${(rawRatio / (unRatio == 0 ? 0.01 : unRatio)).toStringAsFixed(2)}');
    }
    client.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
