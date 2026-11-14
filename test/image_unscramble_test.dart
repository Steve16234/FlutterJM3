import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/image_unscramble.dart';

void main() {
  group('segmentCount', () {
    const scrambleId = 220980;

    test('老作品（aid < scramble_id）不打乱', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: scrambleId,
          aid: 1000,
          fileName: '00001.webp',
        ),
        0,
      );
    });

    test('gif 永远不打乱', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: scrambleId,
          aid: 1488098,
          fileName: '00001.gif',
        ),
        0,
      );
    });

    test('aid < 268850 固定 10 段', () {
      expect(
        ImageUnscrambler.segmentCount(
          scrambleId: scrambleId,
          aid: 268849,
          fileName: '00001.webp',
        ),
        10,
      );
    });

    // 以下期望值由接缝比暴力枚举真实分片数得到（aid=1488098）。
    // 注意：哈希用的是「aid + 去扩展名的页号」，带扩展名会算错段数。
    const aid = 1488098;
    const expected = <String, int>{
      '00001.webp': 8,
      '00002.webp': 8,
      '00003.webp': 4,
      '00004.webp': 4,
      '00005.webp': 4,
      '00006.webp': 6,
      '00007.webp': 4,
      '00008.webp': 8,
    };

    for (final entry in expected.entries) {
      test('aid=$aid ${entry.key} -> ${entry.value} 段', () {
        expect(
          ImageUnscrambler.segmentCount(
            scrambleId: scrambleId,
            aid: aid,
            fileName: entry.key,
          ),
          entry.value,
        );
      });
    }

    test('带扩展名与不带扩展名结果不同（回归）', () {
      // 修复前用的是 "148809800001.webp" 的哈希，末位 'f' -> 14 段，图片会错位。
      expect(ImageUnscrambler.pageNumberOf('00001.webp'), '00001');
      expect(ImageUnscrambler.pageNumberOf('00001'), '00001');
      expect(ImageUnscrambler.fileNameOf('https://a.b/c/1488098/00001.webp'),
          '00001.webp');
    });
  });
}
