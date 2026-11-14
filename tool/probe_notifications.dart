// 临时探测：用真实客户端拉一次「站内通知」，看 content 到底有没有内容。
// 用法：dart run tool/probe_notifications.dart <settings.json 路径>
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutterjm/core/gateway_client.dart';

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

void main(List<String> argv) async {
  final text = _readText(File(argv.first));
  String field(String name) {
    final match = RegExp('"$name"\\s*:\\s*"([^"]*)"').firstMatch(text);
    return match?.group(1) ?? '';
  }

  final client = GatewayClient();
  client.restoreSession(jwtToken: field('jwtToken'), avs: field('avs'));

  // 1) 原始结构：看字段名
  final raw = await client.get(
    'notifications',
    query: const <String, String>{'page': '1'},
  );
  print('原始类型：${raw.runtimeType}');
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    final firstMap = raw.first as Map;
    print('第一条的字段：${firstMap.keys.join(',')}');
    final rawContent = (firstMap['content'] ?? '').toString();
    print('raw content 长度=${rawContent.length}');
    // 非 ASCII 用 · 替代，避开控制台编码问题，只看 HTML 结构。
    final preview = StringBuffer();
    for (final rune in rawContent.runes) {
      preview.write(rune >= 0x20 && rune < 0x7F
          ? String.fromCharCode(rune)
          : (rune == 0x0D || rune == 0x0A ? '\n' : '·'));
    }
    final text = preview.toString();
    print('raw content 结构：${text.length > 600 ? text.substring(0, 600) : text}');
  }

  // 2) 用模型解析：看 content 是否为空
  final list = await client.notifications();
  print('\n解析出 ${list.length} 条：');
  for (final item in list) {
    final preview = item.content.length > 80
        ? item.content.substring(0, 80)
        : item.content;
    print('- id=${item.id} read=${item.read} time=${item.time} '
        'titleLen=${item.title.length} contentLen=${item.content.length}');
    print('  content=${preview.replaceAll('\n', '⏎')}');
  }

  client.dispose();
}
