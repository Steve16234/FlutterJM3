// 临时探测：用设备上已登录的凭据，试出「我的收藏」接口的正确形态。
// 用法：dart run tool/probe_favorite.dart <settings.json 路径>
// 令牌只从文件读，不打印。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:flutterjm/core/crypto_utils.dart';

const String appVersion = '2.0.19';
const String signSalt = '185Hcomic3PAPP7R';
const List<String> secrets = <String>['185Hcomic3PAPP7R', '18comicAPPContent'];
const List<String> hosts = <String>[
  'www.cdnbtd.cc',
  'www.cdnutc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
];

String md5HexLocal(String s) => md5.convert(utf8.encode(s)).toString();

Map<String, dynamic> decode(http.Response res, int ts) {
  try {
    final json = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (json is! Map) return <String, dynamic>{'raw': '$json'};
    final data = json['data'];
    if (data is String && data.isNotEmpty) {
      for (final secret in secrets) {
        final plain = aesEcbDecryptBase64(data, md5HexLocal('$ts$secret'));
        if (plain.isEmpty) continue;
        try {
          final decoded = jsonDecode(plain);
          return <String, dynamic>{
            'code': json['code'],
            'data': _preview(decoded),
          };
        } catch (_) {}
      }
      return <String, dynamic>{'code': json['code'], 'data': '<解密失败>'};
    }
    return <String, dynamic>{
      'code': json['code'],
      'errorMsg': json['errorMsg'],
      'data': data,
    };
  } catch (_) {
    return <String, dynamic>{'raw': utf8.decode(res.bodyBytes, allowMalformed: true)};
  }
}

/// 只预览结构，避免打印整页数据。
String _preview(dynamic data) {
  if (data is Map) {
    final keys = data.keys.take(10).join(',');
    final list = data['list'] ?? data['content'] ?? data['data'];
    final first = list is List && list.isNotEmpty ? list.first : null;
    return 'map{$keys} first=${jsonEncode(first).substring(0, jsonEncode(first).length.clamp(0, 300))}';
  }
  if (data is List) {
    return 'list(${data.length}) first=${jsonEncode(data.isEmpty ? null : data.first)}';
  }
  return '$data';
}

void main(List<String> argv) async {
  // 只抠需要的 ASCII 字段：文件经过 PowerShell 重定向后中文可能已乱码。
  final text = _readText(File(argv.first));
  String field(String name) {
    final match = RegExp('"$name"\\s*:\\s*"([^"]*)"').firstMatch(text);
    return match?.group(1) ?? '';
  }

  final jwt = field('jwtToken');
  final avs = field('avs');
  if (jwt.isEmpty) {
    print('本地没有登录态，先登录再探测');
    return;
  }
  print('已读到登录态：jwt=${jwt.length} 字符, avs=${avs.length} 字符');

  final client = http.Client();

  // 1) 选一台能通的主机
  String? host;
  for (final h in hosts) {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final res = await client
          .get(Uri.parse('https://$h/setting?app_img_shunt=1&express=1&t='), headers: _headers(ts, jwt, avs))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        host = h;
        break;
      }
    } catch (_) {}
  }
  if (host == null) {
    print('所有主机都不通');
    return;
  }
  print('使用主机：$host\n');

  Future<void> probeGet(String path, Map<String, String> query) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse('https://$host/$path').replace(queryParameters: query);
    try {
      final res = await client
          .get(uri, headers: _headers(ts, jwt, avs))
          .timeout(const Duration(seconds: 15));
      print('GET  /$path $query -> ${res.statusCode} ${decode(res, ts)}');
    } catch (e) {
      print('GET  /$path $query -> 异常 $e');
    }
  }

  Future<void> probePost(String path, Map<String, String> fields) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      final request = http.MultipartRequest('POST', Uri.parse('https://$host/$path'))
        ..headers.addAll(_headers(ts, jwt, avs))
        ..fields.addAll(fields);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final res = await http.Response.fromStream(streamed);
      print('POST /$path $fields -> ${res.statusCode} ${decode(res, ts)}');
    } catch (e) {
      print('POST /$path $fields -> 异常 $e');
    }
  }

  print('--- 收藏列表候选形态 ---');
  await probePost('favorite', <String, String>{'page': '1'});
  await probePost('favorite', <String, String>{'page': '1', 'folder_id': '0'});
  await probePost('favorite', <String, String>{'page': '1', 'fid': '0'});
  await probeGet('favorite', <String, String>{'page': '1'});
  await probeGet('favorite', <String, String>{'page': '1', 'folder_id': '0'});

  print('\n--- 收藏夹候选形态 ---');
  await probeGet('favorite_folder', <String, String>{'page': '1'});
  await probePost('favorite_folder', <String, String>{'page': '1'});

  print('\n--- 通知候选形态 ---');
  await probePost('notifications', <String, String>{'page': '1', 'type': '1'});
  await probePost('notifications', <String, String>{'page': '1', 'p': '1'});
  await probePost('notifications',
      <String, String>{'page': '1', 'type': 'site'});
  await probeGet('notifications', <String, String>{'page': '1'});

  print('\n--- 关注列表候选形态 ---');
  await probeGet('album_tracking', <String, String>{'page': '1'});
  await probePost('album_tracking', <String, String>{'page': '1', 'type': '1'});
  await probePost('album_tracking', <String, String>{'p': '1'});

  print('\n--- 其它参考 ---');
  await probeGet('watch_list', <String, String>{'page': '1'});
  await probePost('daily', <String, String>{'user_id': '42'});

  client.close();
}

/// PowerShell 重定向可能写出 UTF-16LE，这里按 BOM 判编码。
String _readText(File file) {
  final raw = file.readAsBytesSync();
  if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < raw.length; i += 2) {
      units.add(raw[i] | (raw[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
    return utf8.decode(raw.sublist(3));
  }
  return utf8.decode(raw, allowMalformed: true);
}

Map<String, String> _headers(int ts, String jwt, String avs) {
  return <String, String>{
    'Tokenparam': '$ts,$appVersion',
    'Token': md5HexLocal('$ts$signSalt'),
    'Accept': 'application/json',
    'User-Agent': 'okhttp/4.9.2',
    'Authorization': jwt.isEmpty ? '' : 'Bearer $jwt',
    if (avs.isNotEmpty) 'Cookie': 'AVS=$avs',
  };
}
