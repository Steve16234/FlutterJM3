// ignore_for_file: avoid_print
// 临时探测：确认 album 详情里的封面字段与真实图片尺寸。用完即删。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutterjm/core/crypto_utils.dart';

const appVersion = '2.0.19';
const signSalt = '185Hcomic3PAPP7R';
const secrets = <String>['185Hcomic3PAPP7R', '18comicAPPContent'];
const host = 'www.cdnbtd.cc';

Future<dynamic> call(
  http.Client client,
  String path,
  Map<String, String> query,
) async {
  final uri = Uri.parse('https://$host/$path').replace(queryParameters: query);
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final res = await client.get(uri, headers: <String, String>{
    'Tokenparam': '$ts,$appVersion',
    'Token': md5Hex('$ts$signSalt'),
    'Accept': 'application/json',
    'User-Agent': 'okhttp/4.9.2',
    'Referer': 'https://$host/',
  }).timeout(const Duration(seconds: 15));

  final dynamic json =
      jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  final data = (json as Map)['data'];
  if (data is String && data.isNotEmpty) {
    for (final secret in secrets) {
      try {
        final plain = aesEcbDecryptBase64(data, md5Hex('$ts$secret'));
        if (plain.isEmpty) continue;
        return jsonDecode(plain);
      } catch (_) {}
    }
  }
  return data;
}

Future<void> main() async {
  final client = http.Client();
  final buf = StringBuffer();

  final setting = await call(client, 'setting', <String, String>{
    'app_img_shunt': '1',
    'express': '1',
    't': '',
  });
  final imgHost = setting is Map ? '${setting['img_host']}' : '';
  buf.writeln('img_host = $imgHost');

  for (final id in <String>['1488098', '1141268']) {
    final album = await call(client, 'album', <String, String>{'id': id});
    if (album is! Map) continue;
    buf.writeln('===== album $id');
    for (final k in album.keys) {
      final v = '${album[k]}';
      if (k.toLowerCase().contains('img') ||
          k.toLowerCase().contains('image') ||
          k.toLowerCase().contains('photo') ||
          k.toLowerCase().contains('cover') ||
          k.toLowerCase().contains('series') ||
          k.toLowerCase().contains('thumb')) {
        buf.writeln('  $k = $v');
      }
    }
  }

  // 对比两种封面地址的真实字节数与图片格式
  final candidates = <String>[
    '$imgHost/media/albums/1488098.jpg',
    '$imgHost/media/albums/1488098_3x4.jpg',
    'https://cdn-msp.jmdanjonproxy.xyz/media/albums/1488098.jpg',
  ];
  for (final url in candidates) {
    try {
      final res = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      buf.writeln('$url -> ${res.statusCode} len=${res.bodyBytes.length} '
          'magic=${res.bodyBytes.take(4).toList()}');
      await File('tool/cover_${url.hashCode}.bin')
          .writeAsBytes(res.bodyBytes);
    } catch (e) {
      buf.writeln('$url -> $e');
    }
  }

  await File('tool/album_dump.txt').writeAsString(buf.toString());
  print('done');
  client.close();
}
