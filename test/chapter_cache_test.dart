import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/chapter_cache.dart';

Map<String, dynamic> _json(String id) => <String, dynamic>{
      'id': id,
      'scramble_id': 220980,
      'name': 'name-$id',
      'total_page': 2,
      'images': <Map<String, dynamic>>[
        <String, dynamic>{'page': 1, 'image': 'https://x/$id/00001.webp'},
        <String, dynamic>{'page': 2, 'image': 'https://x/$id/00002.webp'},
      ],
    };

void main() {
  test('第二次 load 命中缓存，不再请求', () async {
    var calls = 0;
    final cache = ChapterCache(fetch: (id) async {
      calls++;
      return _json(id);
    });

    final first = await cache.load('1');
    expect(calls, 1);
    expect(first.pages, hasLength(2));
    expect(first.scrambleId, 220980);

    final second = await cache.load('1');
    expect(calls, 1, reason: '应命中缓存');
    expect(identical(first, second), isTrue);

    await cache.load('1', force: true);
    expect(calls, 2, reason: 'force 应跳过缓存');
  });

  test('超过 ttl 后过期', () async {
    var calls = 0;
    final cache = ChapterCache(
      fetch: (id) async {
        calls++;
        return _json(id);
      },
      ttl: const Duration(milliseconds: 30),
    );

    await cache.load('1');
    expect(cache.cached('1'), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(cache.cached('1'), isNull);
    await cache.load('1');
    expect(calls, 2);
  });

  test('超出 maxEntries 淘汰最旧的章节', () async {
    final cache = ChapterCache(
      fetch: (id) async => _json(id),
      maxEntries: 2,
    );
    await cache.load('1');
    await cache.load('2');
    await cache.load('3');
    expect(cache.cached('1'), isNull);
    expect(cache.cached('2'), isNotNull);
    expect(cache.cached('3'), isNotNull);
  });

  test('invalidate 清除单章', () async {
    var calls = 0;
    final cache = ChapterCache(fetch: (id) async {
      calls++;
      return _json(id);
    });
    await cache.load('9');
    cache.invalidate('9');
    expect(cache.cached('9'), isNull);
    await cache.load('9');
    expect(calls, 2);
  });
}
