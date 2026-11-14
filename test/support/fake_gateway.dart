import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';

String md5Of(String input) => md5.convert(utf8.encode(input)).toString();

/// 按网关约定加密响应：AES-256-ECB/PKCS7，key = md5(ts + secret) 的 hex 本身。
String encryptEnvelope(String plain, String key) {
  final input = utf8.encode(plain);
  final pad = 16 - (input.length % 16);
  final padded = Uint8List(input.length + pad)
    ..setRange(0, input.length, input);
  for (var i = input.length; i < padded.length; i++) {
    padded[i] = pad;
  }
  final engine = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(utf8.encode(key)));
  final out = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 16) {
    engine.processBlock(padded, offset, out, offset);
  }
  return base64.encode(out);
}

/// 登录成功时网关返回的 data。
const Map<String, dynamic> loginOk = <String, dynamic>{
  'jwttoken': 'JWT-1',
  's': 'AVS-1',
  'username': 'tester',
  'id': 42,
  'photo': 'abc.jpg',
};

/// 收到的一次请求（用于断言路径 / 方法 / 表单体）。
class SeenRequest {
  const SeenRequest({
    required this.method,
    required this.url,
    required this.body,
    required this.headers,
  });

  final String method;
  final Uri url;
  final String body;
  final Map<String, String> headers;

  String get path => url.path;
}

/// 假网关：主机清单 500（走内置兜底线路），其余按需返回加密信封。
///
/// * [responses]：`路径 -> 明文 data`，命中时加密返回，否则回默认的 `img_host`。
/// * [unauthorized]：返回 true 时除 `login` 外的接口一律 401。
MockClient fakeGateway({
  Map<String, dynamic>? loginData,
  int loginStatus = 200,
  bool Function()? unauthorized,
  List<Map<String, String>>? seenHeaders,
  List<String>? seenBodies,
  Map<String, dynamic>? responses,
  List<SeenRequest>? seen,
}) {
  return MockClient((request) async {
    final url = request.url;
    if (url.toString().contains('newsvr')) return http.Response('', 500);

    seenHeaders?.add(Map<String, String>.from(request.headers));
    seen?.add(
      SeenRequest(
        method: request.method,
        url: url,
        body: request.body,
        headers: Map<String, String>.from(request.headers),
      ),
    );

    final path = url.path.startsWith('/') ? url.path.substring(1) : url.path;

    if ((unauthorized?.call() ?? false) && !path.endsWith('login')) {
      return http.Response('', 401);
    }

    final headers = request.headers;
    final ts = (headers['Tokenparam'] ?? '').split(',').first;
    final key = md5Of('${ts}185Hcomic3PAPP7R');

    if (path == 'login') {
      seenBodies?.add(request.body);
      if (loginStatus != 200) return http.Response('', loginStatus);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'code': 200,
          'data': encryptEnvelope(
            jsonEncode(loginData ?? <String, dynamic>{}),
            key,
          ),
        }),
        200,
      );
    }
    if (path == 'logout') {
      return http.Response(
        jsonEncode(<String, dynamic>{'code': 200, 'data': ''}),
        200,
      );
    }

    final payload = responses?[path] ??
        <String, dynamic>{'img_host': 'https://img.example'};
    return http.Response(
      jsonEncode(<String, dynamic>{
        'code': 200,
        'data': encryptEnvelope(jsonEncode(payload), key),
      }),
      200,
    );
  });
}
