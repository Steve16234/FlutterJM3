import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// 需要持久化的设置项。
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.searchHistory = const <String>[],
    this.jwtToken,
    this.avs,
    this.memberInfo,
  });

  /// 主题模式（深浅色记忆就靠它）。
  final ThemeMode themeMode;

  /// 搜索历史。
  final List<String> searchHistory;

  /// 登录态：`jwttoken`（请求头 `Authorization: Bearer <jwttoken>`）。
  final String? jwtToken;

  /// 服务端会话串（请求头 `Cookie: AVS=<avs>`），即 `memberInfo.s`。
  final String? avs;

  /// 登录返回的用户信息（含 `id` / `username` / `photo` 等）。
  final Map<String, dynamic>? memberInfo;

  static const AppSettings defaults = AppSettings();

  /// 是否有登录态。
  ///
  /// 只在「服务端明确说失效」时清除，不由客户端定时器决定 —— 官方 App
  /// 能长期保持登录，说明 token 生命周期由服务端控制（见 GatewayClient 的 401 处理）。
  bool get hasSession => jwtToken?.isNotEmpty ?? false;

  AppSettings copyWith({
    ThemeMode? themeMode,
    List<String>? searchHistory,
    String? jwtToken,
    String? avs,
    Map<String, dynamic>? memberInfo,
    bool clearSession = false,
  }) {
    if (clearSession) {
      return AppSettings(
        themeMode: themeMode ?? this.themeMode,
        searchHistory: searchHistory ?? this.searchHistory,
      );
    }
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      searchHistory: searchHistory ?? this.searchHistory,
      jwtToken: jwtToken ?? this.jwtToken,
      avs: avs ?? this.avs,
      memberInfo: memberInfo ?? this.memberInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.jwtToken == jwtToken &&
        other.avs == avs &&
        _sameList(other.searchHistory, searchHistory) &&
        _sameJson(other.memberInfo, memberInfo);
  }

  @override
  int get hashCode => Object.hash(
        themeMode,
        Object.hashAll(searchHistory),
        jwtToken,
        avs,
        memberInfo == null ? null : jsonEncode(memberInfo),
      );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameJson(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return a == b;
    return jsonEncode(a) == jsonEncode(b);
  }
}

/// 轻量设置持久化：写入 `<appSupportDir>/settings.json`。
///
/// 只有很少几个键值，直接用 path_provider（已有依赖）+ JSON 文件，
/// 不再引入 shared_preferences 这类原生插件，改设置逻辑时热重载即可生效。
class SettingsStore {
  SettingsStore({this.directory});

  static const String fileName = 'settings.json';

  /// 存储目录（测试注入用）；为 null 时使用应用的 support 目录。
  final Directory? directory;

  /// 读设置；文件不存在 / 损坏 / 拿不到目录时返回默认值。
  Future<AppSettings> read() async {
    final file = await _file();
    if (file == null) return AppSettings.defaults;
    try {
      if (!await file.exists()) return AppSettings.defaults;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AppSettings.defaults;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AppSettings.defaults;
      final map = decoded.cast<String, dynamic>();
      final member = map['memberInfo'];
      return AppSettings(
        themeMode: _themeModeFrom(map['themeMode']),
        searchHistory: (map['searchHistory'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
        jwtToken: map['jwtToken'] as String?,
        avs: map['avs'] as String?,
        memberInfo: member is Map ? member.cast<String, dynamic>() : null,
      );
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  /// 写设置；失败静默（不因为存档失败打断使用）。
  Future<void> write(AppSettings settings) async {
    final file = await _file();
    if (file == null) return;
    final payload = jsonEncode(<String, dynamic>{
      'themeMode': _themeModeName(settings.themeMode),
      'searchHistory': settings.searchHistory,
      'jwtToken': settings.jwtToken,
      'avs': settings.avs,
      'memberInfo': settings.memberInfo,
    });
    try {
      // 先写临时文件再改名，避免进程被杀时留下半个 JSON。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 忽略
    }
  }

  Future<File?> _file() async {
    final dir = await _ensureDirectory();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  Future<Directory?> _ensureDirectory() async {
    try {
      final dir = directory ?? await getApplicationSupportDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null; // 没有存储目录时退化为纯内存
    }
  }

  static String _themeModeName(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static ThemeMode _themeModeFrom(Object? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
