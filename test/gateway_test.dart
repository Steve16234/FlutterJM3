import 'package:flutterjm/core/crypto_utils.dart';
import 'package:flutterjm/core/image_unscramble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('md5Hex', () {
    test('生成 32 位小写 hex', () {
      expect(
        md5Hex('diosfjckwpqpdfjkvnqQjsik'),
        '6ae6b037507edb82ee4699827c4b4066',
      );
      expect(md5Hex('185Hcomic3PAPP7R').length, 32);
    });
  });

  group('aesEcbDecryptBase64', () {
    final key = md5Hex('diosfjckwpqpdfjkvnqQjsik');

    test('空输入与纯空白返回空串', () {
      expect(aesEcbDecryptBase64('', key), '');
      expect(aesEcbDecryptBase64('  \n\t ', key), '');
    });

    test('错误密钥不抛异常（交由 JSON 解析判定失败）', () {
      // 解密本身不校验填充，错密钥会得到乱码；客户端靠 jsonDecode 失败来切换 secret。
      expect(
        () => aesEcbDecryptBase64('YWJjZGVmZ2hpamtsbW5vcA==', key),
        returnsNormally,
      );
    });
  });

  group('ImageUnscrambler.segmentCount', () {
    test('早于 scramble_id 的作品不打乱', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: 220980,
          aid: 1000,
          fileName: '00001.webp',
        ),
        0,
      );
    });

    test('.gif 永远不打乱', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: 0,
          aid: 1490490,
          fileName: '00001.gif',
        ),
        0,
      );
    });

    test('aid < 268850 时固定 10 段', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: 220980,
          aid: 250000,
          fileName: '00001.webp',
        ),
        10,
      );
    });

    test('aid >= 268850 时分段数为 2..20 的偶数', () {
      final num = ImageUnscrambler.segmentCount(
        scrambleId: 220980,
        aid: 300000,
        fileName: '00001.webp',
      );
      expect(num, inInclusiveRange(2, 20));
      expect(num.isEven, isTrue);
    });

    test('fileNameOf 从 URL 取文件名', () {
      expect(
        ImageUnscrambler.fileNameOf(
          'https://cdn.example.com/media/photos/1490490/00003.webp?t=1',
        ),
        '00003.webp',
      );
    });
  });
}
