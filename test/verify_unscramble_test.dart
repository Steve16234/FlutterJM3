// 临时验证：比较两种分段数算法下，还原后图片的接缝质量。
// 接缝比（boundary/intra）越接近 1 说明还原越正确。用完即删。
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterjm/core/image_unscramble.dart';

const aid = 1488098;
const scrambleId = 220980;

String b64(String s) => base64.encode(utf8.encode(s));

/// 现有实现：md5(aid + 完整文件名)
int oldNum(String fileName) {
  final digest = md5.convert(utf8.encode('$aid$fileName')).toString();
  return (digest.codeUnitAt(digest.length - 1) % 8) * 2 + 2;
}

/// 接口清单：md5(btoa(aid) + btoa(page))，page 为不含扩展名的页号
int newNum(String page) {
  final digest =
      md5.convert(utf8.encode(b64('$aid') + b64(page))).toString();
  return (digest.codeUnitAt(digest.length - 1) % 8) * 2 + 2;
}

/// 计算接缝质量：band 边界处的行间差异 与 band 内部行间差异 的比值。
Future<double> seamRatio(ui.Image img, int num) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final w = img.width;
  final h = img.height;
  final rowBytes = w * 4;

  double rowDiff(int y0, int y1) {
    var sum = 0;
    final a = y0 * rowBytes;
    final b = y1 * rowBytes;
    for (var x = 0; x < rowBytes; x += 4) {
      sum += (bytes[a + x] - bytes[b + x]).abs();
      sum += (bytes[a + x + 1] - bytes[b + x + 1]).abs();
      sum += (bytes[a + x + 2] - bytes[b + x + 2]).abs();
    }
    return sum / (w * 3);
  }

  // band 起始行
  final height = h;
  final move = height ~/ num;
  final over = height % num;
  final boundaries = <int>{};
  for (var i = 1; i < num; i++) {
    boundaries.add(move * i + over);
  }

  var boundarySum = 0.0;
  var boundaryCount = 0;
  var intraSum = 0.0;
  var intraCount = 0;

  for (var y = 1; y < h; y++) {
    final d = rowDiff(y - 1, y);
    if (boundaries.contains(y)) {
      boundarySum += d;
      boundaryCount++;
    } else {
      intraSum += d;
      intraCount++;
    }
  }

  final boundaryAvg = boundaryCount == 0 ? 0.0 : boundarySum / boundaryCount;
  final intraAvg = intraCount == 0 ? 1.0 : intraSum / intraCount;
  return intraAvg == 0 ? 0 : boundaryAvg / intraAvg;
}

void main() {
  test('比较分段数算法', () async {
    final client = http.Client();
    for (final page in <String>['00001', '00002']) {
      final url =
          'https://cdn-msp.jmdanjonproxy.xyz/media/photos/$aid/$page.webp';
      final res = await client.get(Uri.parse(url), headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
        'Referer': 'https://18comic.vip/',
      });
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final o = oldNum('$page.webp');
      final n = newNum(page);

      final oldRatio =
          await seamRatio(await ImageUnscrambler.unscramble(img, o), o);
      final newRatio =
          await seamRatio(await ImageUnscrambler.unscramble(img, n), n);
      final rawRatio = await seamRatio(img, n); // 完全没还原的参照

      // ignore: avoid_print
      print('page=$page size=${img.width}x${img.height} '
          'oldNum=$o(old=${oldRatio.toStringAsFixed(2)}) '
          'newNum=$n(new=${newRatio.toStringAsFixed(2)}) '
          'raw=${rawRatio.toStringAsFixed(2)}');
    }
    client.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
