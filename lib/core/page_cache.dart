import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 阅读器页图缓存，三层：
///
/// * **L1 解码后的 [ui.Image] LRU**（默认 64MB）：再次进入同一章几乎零开销。
///   带引用计数——正在屏幕上显示的图片不会被淘汰释放，避免「已释放的图片被绘制」。
/// * **L2 原始字节 LRU**（默认 32MB）：减少磁盘 IO，也避免重复下载。
/// * **L3 磁盘缓存**（默认 256MB，`<cacheDir>/jm_pages`）：杀掉 App 再进来依然命中。
///
/// 磁盘层拿不到目录（如单元测试、无存储权限）时会自动退化为纯内存缓存。
class PageCache {
  PageCache({
    this._directory,
    int imageBudgetBytes = 64 << 20,
    int byteBudgetBytes = 32 << 20,
    int diskBudgetBytes = 256 << 20,
  })  : _imageBudget = imageBudgetBytes,
        _byteBudget = byteBudgetBytes,
        _diskBudget = diskBudgetBytes;

  /// 全局共享实例，供整个 App 复用。
  static final PageCache instance = PageCache();

  final int _imageBudget;
  final int _byteBudget;
  final int _diskBudget;

  Directory? _directory;
  bool _dirTried = false;
  int _diskBytes = 0;
  bool _pruning = false;

  /// url -> 解码后的图片（含引用计数）。
  final Map<String, _ImageEntry> _images = <String, _ImageEntry>{};

  /// 访问顺序（尾为最近使用）。
  final LinkedHashSet<String> _imageLru = LinkedHashSet<String>();
  int _imageBytes = 0;

  /// 原始字节（访问顺序，尾为最近使用）。
  final LinkedHashMap<String, Uint8List> _bytes =
      LinkedHashMap<String, Uint8List>();
  int _byteTotal = 0;

  /// 已解码图片占用（字节）。
  int get imageBytes => _imageBytes;

  /// 已缓存图片数量。
  int get imageCount => _images.length;

  /// 是否已缓存该页的解码结果。
  bool hasImage(String url) => _images.containsKey(url);

  // ---------------------------------------------------------------- L1 图片

  /// 取已解码图片并把引用计数 +1。**调用方用完必须 [releaseImage]**。
  ui.Image? obtainImage(String url) {
    final entry = _images[url];
    if (entry == null) return null;
    entry.refs++;
    entry.retired = false;
    _touchImage(url);
    return entry.image;
  }

  /// 归还引用；若该图在显示期间已被淘汰，则在最后一个引用释放时真正释放。
  void releaseImage(String url) {
    final entry = _images[url];
    if (entry == null) return;
    if (entry.refs > 0) entry.refs--;
    if (entry.retired && entry.refs == 0) _dropImage(url, entry);
  }

  /// 放入解码结果（引用计数从 0 开始）。
  void putImage(String url, ui.Image image) {
    final existing = _images[url];
    if (existing != null) {
      // 同一 URL 已有缓存：保留旧的那张，新的直接释放，避免替换掉正在显示的图。
      if (!identical(existing.image, image)) image.dispose();
      existing.retired = false;
      _touchImage(url);
      return;
    }

    final entry = _ImageEntry(image);
    _images[url] = entry;
    _imageBytes += entry.bytes;
    _touchImage(url);
    _evictImages(protect: url);
  }

  void _touchImage(String url) {
    _imageLru.remove(url);
    _imageLru.add(url);
  }

  /// 超出预算时从最久未使用的开始释放。
  ///
  /// [protect] 是刚放进来的一页：即使它单页就超预算，也不能刚放就扔，否则
  /// 调用方拿不到图。被引用的图标记为 retired，等引用释放后再释放内存。
  void _evictImages({String? protect}) {
    while (_imageBytes > _imageBudget) {
      String? victim;
      var progressed = false;
      for (final url in _imageLru) {
        final entry = _images[url];
        if (entry == null) {
          _imageLru.remove(url);
          progressed = true;
          break;
        }
        if (entry.refs > 0) {
          // 正在显示：标记待回收，先从 LRU 里摘掉。
          entry.retired = true;
          _imageLru.remove(url);
          progressed = true;
          break;
        }
        if (url == protect) continue;
        victim = url;
        break;
      }
      if (victim != null) {
        _dropImage(victim, _images[victim]!);
        continue;
      }
      // 只剩刚放进来的一页或全部被钉住：允许暂时超标，等引用释放。
      if (!progressed) return;
    }
  }

  void _dropImage(String url, _ImageEntry entry) {
    _images.remove(url);
    _imageLru.remove(url);
    _imageBytes -= entry.bytes;
    if (_imageBytes < 0) _imageBytes = 0;
    entry.dispose();
  }

  // ---------------------------------------------------------------- L2 字节

  /// 取原始图片字节：内存 -> 磁盘。
  Future<Uint8List?> readBytes(String url) async {
    final memory = _bytes.remove(url);
    if (memory != null) {
      _bytes[url] = memory; // 刷新 LRU
      return memory;
    }

    final file = await _fileFor(url);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      if (data.isEmpty) return null;
      _rememberBytes(url, data);
      unawaited(_touchFile(file));
      return data;
    } catch (_) {
      return null;
    }
  }

  /// 写入原始字节（内存 + 磁盘，磁盘失败忽略）。
  Future<void> writeBytes(String url, Uint8List data) async {
    if (data.isEmpty) return;
    _rememberBytes(url, data);

    final file = await _fileFor(url);
    if (file == null) return;
    try {
      await file.writeAsBytes(data, flush: false);
      _diskBytes += data.length;
      if (_diskBytes > _diskBudget) unawaited(_pruneDisk());
    } catch (_) {
      // 磁盘写失败不影响浏览体验。
    }
  }

  void _rememberBytes(String url, Uint8List data) {
    final old = _bytes.remove(url);
    if (old != null) _byteTotal -= old.length;
    _bytes[url] = data;
    _byteTotal += data.length;
    while (_byteTotal > _byteBudget && _bytes.isNotEmpty) {
      final key = _bytes.keys.first;
      final dropped = _bytes.remove(key);
      if (dropped != null) _byteTotal -= dropped.length;
    }
    if (_byteTotal < 0) _byteTotal = 0;
  }

  // ---------------------------------------------------------------- L3 磁盘

  Future<File?> _fileFor(String url) async {
    final dir = await _ensureDirectory();
    if (dir == null) return null;
    final key = md5.convert(utf8.encode(url)).toString();
    return File('${dir.path}${Platform.pathSeparator}$key.bin');
  }

  /// 预热：提前把磁盘缓存目录建好（拿不到就算了），避免第一次进阅读器才初始化。
  Future<void> warmUp() async {
    await _ensureDirectory();
  }

  Future<Directory?> _ensureDirectory() async {
    final ready = _directory;
    if (ready != null) return ready;
    if (_dirTried) return null;
    _dirTried = true;
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}jm_pages');
      if (!await dir.exists()) await dir.create(recursive: true);
      _directory = dir;
      unawaited(_scanDisk(dir));
      return dir;
    } catch (_) {
      return null; // 拿不到目录 -> 只有内存缓存
    }
  }

  Future<void> _scanDisk(Directory dir) async {
    try {
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      _diskBytes = total;
      if (_diskBytes > _diskBudget) await _pruneDisk();
    } catch (_) {
      // 忽略
    }
  }

  /// 超出预算时按修改时间从旧到新删除，降到 80%。
  Future<void> _pruneDisk() async {
    if (_pruning) return;
    final dir = _directory;
    if (dir == null) return;
    _pruning = true;
    try {
      final entries = <MapEntry<File, DateTime>>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          entries.add(MapEntry(entity, (await entity.stat()).modified));
        } catch (_) {}
      }
      entries.sort((a, b) => a.value.compareTo(b.value));

      var total = _diskBytes;
      final target = (_diskBudget * 0.8).round();
      for (final entry in entries) {
        if (total <= target) break;
        try {
          final length = await entry.key.length();
          await entry.key.delete();
          total -= length;
        } catch (_) {}
      }
      _diskBytes = total < 0 ? 0 : total;
    } catch (_) {
      // 忽略
    } finally {
      _pruning = false;
    }
  }

  Future<void> _touchFile(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 维护

  /// 当前占用（设置页展示用）：会重新扫一遍磁盘目录。
  Future<CacheUsage> usage() async {
    final dir = await _ensureDirectory();
    if (dir != null) await _scanDisk(dir);
    return CacheUsage(
      imageBytes: _imageBytes,
      byteBytes: _byteTotal,
      diskBytes: _diskBytes,
    );
  }

  /// 清空所有缓存（含磁盘）。设置页「清理缓存」用。
  Future<void> clear() async {
    for (final url in _images.keys.toList()) {
      final entry = _images[url]!;
      if (entry.refs == 0) {
        _dropImage(url, entry);
      } else {
        // 还显示在屏幕上：等 widget 归还引用时再释放。
        entry.retired = true;
        _imageLru.remove(url);
      }
    }
    _bytes.clear();
    _byteTotal = 0;

    final dir = _directory;
    if (dir == null) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _diskBytes = 0;
  }
}

/// 缓存占用快照。
class CacheUsage {
  const CacheUsage({
    required this.imageBytes,
    required this.byteBytes,
    required this.diskBytes,
  });

  /// 解码后图片占用。
  final int imageBytes;

  /// 原始字节内存缓存占用。
  final int byteBytes;

  /// 磁盘占用。
  final int diskBytes;

  int get memoryBytes => imageBytes + byteBytes;

  int get totalBytes => memoryBytes + diskBytes;

  static const CacheUsage empty =
      CacheUsage(imageBytes: 0, byteBytes: 0, diskBytes: 0);
}

class _ImageEntry {
  _ImageEntry(this.image);

  final ui.Image image;
  int refs = 0;

  /// 已被 LRU 淘汰但因仍被引用而暂未释放。
  bool retired = false;
  bool _disposed = false;

  int get bytes => image.width * image.height * 4;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}
