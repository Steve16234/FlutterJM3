// ignore_for_file: avoid_print
// 临时探测：comic_read 返回的页图地址 / 文件名格式 / scramble_id。用完即删。
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

  for (final id in <String>['1488098', '1141268']) {
    final read = await call(client, 'comic_read', <String, String>{'id': id});
    if (read is! Map) {
      buf.writeln('$id -> not a map');
      continue;
    }
    buf.writeln('===== comic_read $id');
    buf.writeln('  id=${read['id']} scramble_id=${read['scramble_id']} '
        'total_page=${read['total_page']}');
    final images = (read['images'] as List?) ?? const <dynamic>[];
    buf.writeln('  images count=${images.length}');
    for (final img in images.take(3)) {
      buf.writeln('  sample: $img');
    }
  }

  await File('tool/read_dump.txt').writeAsString(buf.toString());
  print('done');
  client.close();
}
