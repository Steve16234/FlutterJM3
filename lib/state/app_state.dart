import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/chapter_cache.dart';
import '../core/gateway_client.dart';
import '../core/settings_store.dart';

/// 全局状态：网关客户端、线路测速、主题模式、图片 CDN、搜索历史。
class AppState extends ChangeNotifier {
  AppState({GatewayClient? client, SettingsStore? settings})
      : client = client ?? GatewayClient(),
        settings = settings ?? SettingsStore() {
    // 服务端 401：登录态失效，清存档并刷新 UI。
    this.client.onAuthExpired = _onAuthExpired;
  }

  final GatewayClient client;

  /// 设置持久化（主题、搜索历史）。
  final SettingsStore settings;

  /// 章节页列表缓存：重复进入同一章不再等接口。
  late final ChapterCache chapters = ChapterCache(fetch: client.comicRead);

  /// 启动页展示的线路数量。
  static const int lineCount = 4;

  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;
  String? _error;

  List<String> _lines = const <String>[];
  final Map<String, LineProbe> _probes = <String, LineProbe>{};
  bool _probing = false;
  String? _selectedHost;

  final List<String> _searchHistory = <String>[];

  /// 已经读过存档。读完之前不写盘，避免把用户刚改的值覆盖掉。
  bool _restored = false;
  bool _dirty = false;
  bool _writing = false;
  bool _pendingWrite = false;
  bool _disposed = false;



  ThemeMode get themeMode => _themeMode;
  bool get ready => _ready;
  String? get error => _error;

  /// 是否已登录。
  bool get loggedIn => client.loggedIn;

  /// 登录用户名（未登录为空串）。
  String get username {
    final info = client.memberInfo;
    if (info == null) return '';
    return (info['username'] ?? info['email'] ?? '').toString();
  }

  /// 用户 ID（未登录为 0）。
  int get userId => int.tryParse('${client.memberInfo?['id'] ?? ''}') ?? 0;

  /// 头像 URL（无头像时为空串）。「`{img_host}/media/users/{photo}`」
  String get avatarUrl {
    final photo = (client.memberInfo?['photo'] ?? '').toString();
    if (photo.isEmpty ||
        photo == 'default.jpg' ||
        photo == 'nopic.jpg' ||
        photo == 'default.png') {
      return '';
    }
    if (photo.startsWith('http')) return photo;
    return '${client.imgHost}/media/users/$photo';
  }

  /// 四条候选线路（启动页按钮，竖向排列）。
  List<String> get lines => List<String>.unmodifiable(_lines);

  /// 各线路的最新测速结果。
  Map<String, LineProbe> get probes => Map<String, LineProbe>.unmodifiable(_probes);

  /// 是否正在测速。
  bool get probing => _probing;

  /// 当前选中的线路 host。
  String? get selectedHost => _selectedHost;

  /// 最快线路（仅在测速完成后有值）。
  String? get fastestHost {
    LineProbe? best;
    for (final probe in _probes.values) {
      if (!probe.ok) continue;
      if (best == null || probe.latencyMs < best.latencyMs) best = probe;
    }
    return best?.host;
  }

  List<String> get searchHistory => List<String>.unmodifiable(_searchHistory);

  /// 图片 CDN 根地址。
  String get imgHost => client.imgHost;

  String? get baseUrl => client.baseUrl;

  /// 拉线路清单并对前 [lineCount] 条线路并发测速。
  Future<void> refreshLines() async {
    if (_probing) return;
    _probing = true;
    _error = null;
    _probes.clear();
    notifyListeners();

    try {
      final hosts = await client.resolveHosts();
      _lines = hosts.take(lineCount).toList(growable: false);
      for (final host in _lines) {
        _probes[host] = LineProbe(host: host);
      }
      notifyListeners();

      // 并发测速，每完成一条立即刷新 UI。
      await Future.wait<void>(
        _lines.map((host) async {
          final probe = await client.probeHost(host);
          _probes[host] = probe;
          notifyListeners();
        }),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _probing = false;
      notifyListeners();
    }
  }

  /// 使用指定线路进入主界面。
  Future<void> selectLine(String host) async {
    _selectedHost = host;
    _error = null;
    notifyListeners();
    try {
      await client.switchHost(host);
      _ready = true;
    } catch (e) {
      _error = e.toString();
      _ready = false;
    }
    notifyListeners();
  }

  /// 初始化网关：拉线路清单 -> 选线路 -> 拉全局配置。
  Future<void> bootstrap() async {
    _error = null;
    notifyListeners();
    try {
      await client.ensureReady();
      _ready = true;
    } catch (e) {
      _error = e.toString();
      _ready = false;
    }
    notifyListeners();
  }

  /// 换一条线路后重新拉配置。
  Future<void> switchHost(String host) async {
    _selectedHost = host;
    await client.switchHost(host);
    _ready = true;
    notifyListeners();
  }

  /// 从本地读回设置（主题、搜索历史、登录态）。App 启动时调用一次。
  Future<void> restoreSettings() async {
    final saved = await settings.read();
    if (_disposed) return;
    _restored = true;

    // 登录态：只要存过 token 就回填（是否有效由服务端 401 判定）。
    if (saved.hasSession) {
      client.restoreSession(
        jwtToken: saved.jwtToken,
        avs: saved.avs,
        memberInfo: saved.memberInfo,
      );
    } else if (saved.jwtToken != null) {
      client.clearSession();
    }

    if (!_dirty) {
      _themeMode = saved.themeMode;
      _searchHistory
        ..clear()
        ..addAll(saved.searchHistory);
      notifyListeners();
    } else {
      // 读存档期间用户已经改过，以用户当前选择为准，直接回写。
      unawaited(_persist());
    }
  }

  // ---------------------------------------------------------------- 登录

  /// 登录：成功后立即落盘。
  ///
  /// token 不设本地过期时间 —— 官方客户端能长期保持登录，寿命由服务端控制；
  /// 服务端返回 401 时会自动清掉登录态（[client.onAuthExpired]）。
  Future<void> login({
    required String username,
    required String password,
  }) async {
    await client.login(username: username, password: password);
    _dirty = true;
    notifyListeners();
    await _persist();
  }

  /// 登出。[remote] 为 false 时只清本地（服务端已失效 / 主动清除）。
  Future<void> logout({bool remote = true}) async {
    if (remote) {
      await client.logout();
    } else {
      client.clearSession();
    }
    _dirty = true;
    notifyListeners();
    await _persist();
  }

  /// 服务端判定登录失效时的回调：清掉本地存档并通知 UI。
  void _onAuthExpired() {
    if (_disposed) return;
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
  }

  void addSearchHistory(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 12) _searchHistory.removeLast();
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
  }

  void clearSearchHistory() {
    _searchHistory.clear();
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
  }

  /// 写盘：合并短时间内的多次修改，避免重复 IO。
  Future<void> _persist() async {
    if (!_restored) return; // 还没读到存档，等 restoreSettings 里回写
    if (_writing) {
      _pendingWrite = true;
      return;
    }
    _writing = true;
    try {
      do {
        _pendingWrite = false;
        await settings.write(
          AppSettings(
            themeMode: _themeMode,
            searchHistory: List<String>.of(_searchHistory),
            jwtToken: client.jwtToken,
            avs: client.avs,
            memberInfo: client.memberInfo,
          ),
        );
      } while (_pendingWrite && !_disposed);
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    client.onAuthExpired = null;
    client.dispose();
    super.dispose();
  }
}

/// 便捷访问：`context.app`。
extension AppStateContext on BuildContext {
  AppState get app => read<AppState>();
}
