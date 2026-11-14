import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 32 位小写 hex MD5。
String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

Uint8List _stripPkcs7(Uint8List data) {
  if (data.isEmpty) return data;
  final pad = data.last;
  if (pad < 1 || pad > 16 || pad > data.length) return data;
  return Uint8List.sublistView(data, 0, data.length - pad);
}

/// AES-256-ECB + PKCS7 解密。
///
/// [key] 直接取 md5 hex 字符串本身（32 个字符 -> 32 字节 UTF-8），这是网关的约定。
/// 密文允许带换行 / BOM，解码前统一清洗。
String aesEcbDecryptBase64(String cipherText, String key) {
  final cleaned = cipherText.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
  if (cleaned.isEmpty) return '';
  final input = base64Decode(cleaned);
  if (input.isEmpty || input.length % 16 != 0) return '';

  final engine = ECBBlockCipher(AESEngine())
    ..init(false, KeyParameter(utf8.encode(key)));

  final out = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    engine.processBlock(input, offset, out, offset);
  }
  return utf8.decode(_stripPkcs7(out), allowMalformed: true);
}
