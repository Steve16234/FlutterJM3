// ignore_for_file: avoid_print
// 临时探测：读取封面 JPEG 的真实像素尺寸，判断比例是否真的 3:4。用完即删。
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 从 JPEG 的 SOF 段读出 (width, height)。
(int, int)? jpegSize(Uint8List b) {
  var i = 2;
  while (i < b.length - 9) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    // SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15
    final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return (w, h);
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
  }
  return null;
}

Future<void> main() async {
  final client = http.Client();
  final out = StringBuffer();
  const imgHost = 'https://cdn-msp.jmdanjonproxy.vip';

  for (final id in <String>['1488098', '1141268', '1490489']) {
    for (final suffix in <String>['.jpg', '_3x4.jpg']) {
      final url = '$imgHost/media/albums/$id$suffix';
      try {
        final res = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        final size = jpegSize(res.bodyBytes);
        final ratio = size == null ? '-' : (size.$1 / size.$2).toStringAsFixed(3);
        out.writeln('$id$suffix -> ${res.statusCode} '
            'bytes=${res.bodyBytes.length} wh=$size ratio=$ratio');
      } catch (e) {
        out.writeln('$id$suffix -> $e');
      }
    }
  }

  await File('tool/cover_size.txt').writeAsString(out.toString());
  print('done');
  client.close();
}
