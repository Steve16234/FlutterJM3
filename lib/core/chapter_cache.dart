import '../data/models.dart';

/// 章节数据（`comic_read`）的内存缓存。
///
/// 进入阅读器时先用缓存立即出图，避免每次都等一次接口往返；超过 [ttl] 后
/// 重新拉取（页数/乱序种子理论上不会变，但线路切换后地址可能会变）。
class ChapterCache {
  ChapterCache({
    required this.fetch,
    this.ttl = const Duration(minutes: 15),
    this.maxEntries = 12,
  });

  /// 真正的数据源，通常是 `GatewayClient#comicRead`。
  final Future<Map<String, dynamic>> Function(String id) fetch;

  /// 缓存有效期。
  final Duration ttl;

  /// 最多缓存几章的页列表。
  final int maxEntries;

  final Map<String, _Entry> _entries = <String, _Entry>{};

  /// 只在缓存有效时返回，不会触发请求。
  ComicRead? cached(String id) {
    final entry = _entries[id];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > ttl) {
      _entries.remove(id);
      return null;
    }
    return entry.read;
  }

  /// 取章节数据：命中缓存直接返回，否则请求并写入缓存。
  Future<ComicRead> load(String id, {bool force = false}) async {
    if (!force) {
      final hit = cached(id);
      if (hit != null) return hit;
    }
    final read = ComicRead.fromJson(await fetch(id));
    _entries.remove(id);
    _entries[id] = _Entry(read, DateTime.now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return read;
  }

  void invalidate(String id) => _entries.remove(id);

  void clear() => _entries.clear();
}

class _Entry {
  _Entry(this.read, this.at);

  final ComicRead read;
  final DateTime at;
}
