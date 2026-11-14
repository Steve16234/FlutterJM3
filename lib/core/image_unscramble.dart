import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

/// 图片乱序还原。
///
/// 网关会把页图按「横向长条」竖切后倒序拼接，客户端需按同样规则切分并还原。
/// 规则（与官方实现一致）：
///
/// * `aid < scramble_id`：不打乱（老作品）；
/// * `aid < 268850`：固定 10 段；
/// * 否则 `x = aid < 421926 ? 10 : 8`，
///   `num = (md5("<aid><页号>") 末位字符的 ASCII % x) * 2 + 2`，
///   其中 `<页号>` 是**去掉扩展名**的文件名（`00001.webp` -> `00001`）。
///
/// `.gif` 永远不打乱。
class ImageUnscrambler {
  const ImageUnscrambler._();

  static const int threshold268850 = 268850;
  static const int threshold421926 = 421926;

  /// 计算分割段数，返回 0 表示无需还原。
  static int segmentCount({
    required int scrambleId,
    required int aid,
    required String fileName,
  }) {
    if (fileName.toLowerCase().endsWith('.gif')) return 0;
    if (aid < scrambleId) return 0;
    if (aid < threshold268850) return 10;

    final x = aid < threshold421926 ? 10 : 8;
    final digest = md5.convert(utf8.encode('$aid${pageNumberOf(fileName)}'))
        .toString();
    final num = digest.codeUnitAt(digest.length - 1) % x;
    return num * 2 + 2;
  }

  /// 去掉扩展名后的页号（`00001.webp` -> `00001`）。
  ///
  /// 服务端计算分段数时用的是不带扩展名的文件名，带扩展名会算错段数，
  /// 图片就会呈现「分片错乱」的横向错位。
  static String pageNumberOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// 从 URL 中取文件名（如 `00001.webp`）。
  static String fileNameOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  /// 按 [num] 段还原图片；[num] 为 0 时原样返回。
  static Future<ui.Image> unscramble(ui.Image source, int num) async {
    if (num <= 0) return source;

    final width = source.width;
    final height = source.height;
    if (height < num) return source;

    final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return source;

    final src = raw.buffer.asUint8List();
    final dst = Uint8List(src.length);
    final stride = width * 4;
    final over = height % num;

    for (var i = 0; i < num; i++) {
      var move = height ~/ num;
      final ySrc = height - (move * (i + 1)) - over;
      var yDst = move * i;

      if (i == 0) {
        move += over;
      } else {
        yDst += over;
      }
      if (move <= 0 || ySrc < 0) continue;

      final srcStart = ySrc * stride;
      final dstStart = yDst * stride;
      final length = move * stride;
      if (srcStart + length > src.length) continue;
      if (dstStart + length > dst.length) continue;

      dst.setRange(dstStart, dstStart + length, src, srcStart);
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(dst);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      // 中间产物都及时释放，否则每还原一页都泄漏一份缓冲。
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
