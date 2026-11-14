import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'image_unscramble.dart';
import 'page_cache.dart';

/// 页图加载器：缓存 -> 下载 -> 解码 -> 必要时还原乱序。
///
/// 缓存策略见 [PageCache]（解码图 / 原始字节 / 磁盘三层），所以退出阅读器
/// 再进来、甚至重启 App，都不会重新下载已经看过的页。
class PageImageLoader {
  PageImageLoader({http.Client? client, PageCache? cache})
      : _client = client ?? http.Client(),
        _cache = cache ?? PageCache.instance;

  /// 全局共享实例：所有阅读器共用一个缓存池。
  static final PageImageLoader shared = PageImageLoader();

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
    'Referer': 'https://18comic.vip/',
    'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
  };

  final http.Client _client;
  final PageCache _cache;

  /// 同一 URL 的并发请求合并成一个。
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};

  /// 加载单页，返回已还原好的图片。
  ///
  /// 返回的 `ui.Image` 已被 `obtain`（引用计数 +1），使用方在销毁时必须调用
  /// [release]，否则该图无法被淘汰释放。
  Future<ui.Image> load({
    required String url,
    required int aid,
    required int scrambleId,
  }) async {
    final cached = _cache.obtainImage(url);
    if (cached != null) return cached;

    await _fetch(url, aid, scrambleId);
    final image = _cache.obtainImage(url);
    if (image != null) return image;

    // 极端情况：刚放进缓存就被淘汰了（单页超出预算），直接同步再取一次。
    await _fetch(url, aid, scrambleId, force: true);
    final retry = _cache.obtainImage(url);
    if (retry == null) throw StateError('图片缓存失败');
    return retry;
  }

  /// 预取：只塞进缓存，不占用引用计数，失败静默。
  Future<void> prefetch({
    required String url,
    required int aid,
    required int scrambleId,
  }) async {
    if (_cache.hasImage(url)) return;
    try {
      await _fetch(url, aid, scrambleId);
    } catch (_) {
      // 预取失败不影响主流程。
    }
  }

  /// 释放 [load] 拿到的引用。
  void release(String url) => _cache.releaseImage(url);

  Future<void> _fetch(
    String url,
    int aid,
    int scrambleId, {
    bool force = false,
  }) {
    if (!force) {
      final running = _inflight[url];
      if (running != null) return running;
    }
    late final Future<void> future;
    future = _download(url, aid, scrambleId).whenComplete(() {
      if (identical(_inflight[url], future)) _inflight.remove(url);
    });
    _inflight[url] = future;
    return future;
  }

  Future<void> _download(String url, int aid, int scrambleId) async {
    final bytes = await _loadBytes(url);

    final num = ImageUnscrambler.segmentCount(
      scrambleId: scrambleId,
      aid: aid,
      fileName: ImageUnscrambler.fileNameOf(url),
    );

    final decoded = await _decode(bytes);
    ui.Image image = decoded;
    if (num > 0) {
      image = await ImageUnscrambler.unscramble(decoded, num);
      // 还原后中间图就没用了，及时释放掉（一页几乎等于 25MB 像素）。
      if (!identical(image, decoded)) decoded.dispose();
    }

    _cache.putImage(url, image);
  }

  Future<Uint8List> _loadBytes(String url) async {
    final cached = await _cache.readBytes(url);
    if (cached != null) return cached;

    final res = await _client
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw StateError('图片加载失败 (${res.statusCode})');
    }

    unawaited(_cache.writeBytes(url, res.bodyBytes));
    return res.bodyBytes;
  }

  static Future<ui.Image> _decode(Uint8List data) async {
    final codec = await ui.instantiateImageCodec(data);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// 关闭网络连接。共享实例不要调用（[shared] 随进程存活）。
  void dispose() {
    _inflight.clear();
    _client.close();
  }
}
