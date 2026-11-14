import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/account_models.dart';
import '../data/models.dart';
import 'crypto_utils.dart';

class GatewayException implements Exception {
  const GatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 单条线路的测速结果。
///
/// * [pending] 为 true 表示还在测速中；
/// * [ok] 为 true 表示线路可用，[latency] / [bytes] 是实测值；
/// * [error] 非空表示该线路不可用。
class LineProbe {
  const LineProbe({
    required this.host,
    this.latency,
    this.bytes = 0,
    this.error,
  });

  final String host;
  final Duration? latency;
  final int bytes;
  final String? error;

  bool get pending => latency == null && error == null;
  bool get ok => latency != null && error == null;

  /// 往返耗时（毫秒），未完成时返回 -1。
  int get latencyMs => latency?.inMilliseconds ?? -1;

  /// 估算吞吐（KB/s），受响应体大小影响，仅作参考。
  double get kbPerSecond {
    final l = latency;
    if (l == null || l.inMicroseconds <= 0 || bytes <= 0) return 0;
    return bytes / 1024 / (l.inMicroseconds / 1000000);
  }
}

/// 登录会话。
///
/// 报告 §4 里官方客户端的 `authExpiry = now + 36e5`（1 小时）是**本地检查窗口**，
/// 而官方 App 实际能长期保持登录 —— 说明 token 的真实寿命由服务端控制。
/// 因此这里不设本地过期，只有服务端返回 401 才视为失效（见 `_handleUnauthorized`）。
class AuthSession {
  const AuthSession({
    required this.jwtToken,
    required this.avs,
    required this.memberInfo,
  });

  /// 请求头 `Authorization: Bearer <jwtToken>`。
  final String jwtToken;

  /// `memberInfo.s`，即请求头 `Cookie: AVS=<avs>`。
  final String? avs;

  /// 登录接口返回的完整用户信息。
  final Map<String, dynamic> memberInfo;

  String get username =>
      (memberInfo['username'] ?? memberInfo['email'] ?? '').toString();

  String get userId => (memberInfo['id'] ?? '').toString();
}

/// 禁漫网关客户端。
///
/// 接入链路：
/// 1. 拉取线路清单（AES-256-ECB 加密，key = md5("diosfjckwpqpdfjkvnqQjsik")）；
/// 2. 从 `Server[]` 随机取一条线路作为 API 基址；
/// 3. 所有业务接口 = `<线路>/<path>`。
///
/// 协议：
/// * 请求头 `Tokenparam = "<unix秒>,2.0.19"`，`Token = md5(unix秒 + "185Hcomic3PAPP7R")`；
/// * 响应封套 `{"code":200,"data":"<base64 密文>"}`，密文密钥 = `md5(unix秒 + secret)`
///   的 hex 字符串本身；两个候选 secret 依次尝试；
/// * `ad_content_all` / `advertise_all` 例外：密钥为 `md5(secret)`，与时间无关。
class GatewayClient {
  GatewayClient({http.Client? client}) : _client = client ?? http.Client();

  static const String appVersion = '2.0.19';
  static const String _signSalt = '185Hcomic3PAPP7R';
  static const String _hostListSalt = 'diosfjckwpqpdfjkvnqQjsik';

  static const List<String> _contentSecrets = <String>[
    '185Hcomic3PAPP7R',
    '18comicAPPContent',
  ];

  /// 主 / 备线路清单地址。
  static const List<String> _hostListUrls = <String>[
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
  ];

  /// 清单不可用时的兜底线路（取自清单实测值）。
  static const List<String> _fallbackHosts = <String>[
    'www.cdnbtd.cc',
    'www.cdnutc.cc',
    'www.cdngwc.net',
    'www.cdngwc.club',
  ];

  final http.Client _client;
  final Random _random = Random();

  String? _baseUrl;
  Map<String, dynamic> _settings = <String, dynamic>{};
  List<String> _hosts = const <String>[];

  String? _jwtToken;
  String? _avs;
  Map<String, dynamic>? _memberInfo;

  /// 服务端判定登录失效（401）时回调，由 AppState 接管清存档 + 刷新 UI。
  void Function()? onAuthExpired;

  /// 是否已登录（仅看本地是否有 token）。
  bool get loggedIn => _jwtToken != null && _jwtToken!.isNotEmpty;

  String? get jwtToken => _jwtToken;

  /// `memberInfo.s`，即 AVS Cookie 值。
  String? get avs => _avs;

  /// 登录用户信息（未登录为 null）。
  Map<String, dynamic>? get memberInfo => _memberInfo;

  /// 当前生效的 API 基址，形如 `https://www.cdnbtd.cc/`。
  String? get baseUrl => _baseUrl;

  /// 所有可用线路（用于设置页展示 / 手动切换）。
  List<String> get hosts => List<String>.unmodifiable(_hosts);

  /// `setting` 接口的全局配置。
  Map<String, dynamic> get settings => _settings;

  /// `setting.img_host`，封面 / 头像等图片的 CDN 根。
  String get imgHost {
    final host = _settings['img_host'];
    if (host is String && host.isNotEmpty) return host;
    return 'https://cdn-msp.jmdanjonproxy.vip';
  }

  Future<void> ensureReady() async {
    if (_baseUrl != null) return;
    final hosts = await resolveHosts();
    _baseUrl = 'https://${hosts[_random.nextInt(hosts.length)]}/';
    try {
      _settings = await getSetting();
    } catch (_) {
      _settings = <String, dynamic>{};
    }
  }

  /// 线路清单（带缓存），供启动页展示与测速使用。
  Future<List<String>> resolveHosts() async {
    if (_hosts.isEmpty) _hosts = await _resolveHosts();
    return List<String>.unmodifiable(_hosts);
  }

  /// 手动切换到指定线路，并重新拉取该线路的全局配置。
  Future<void> switchHost(String host) async {
    _baseUrl = 'https://$host/';
    _settings = <String, dynamic>{};
    try {
      _settings = await getSetting();
    } catch (_) {
      // 线路可用但配置拉取失败时，保持默认配置继续。
    }
  }

  /// 对单条线路做测速：先预热建立连接，再实测一次真实业务请求。
  Future<LineProbe> probeHost(String host) async {
    Future<int> timed(String path, Map<String, String> query) async {
      final uri = Uri.parse('https://$host/$path')
          .replace(queryParameters: query);
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final res = await _client
          .get(
            uri,
            headers: <String, String>{
              'Tokenparam': '$ts,$appVersion',
              'Token': md5Hex('$ts$_signSalt'),
              'Accept': 'application/json',
              'User-Agent': 'okhttp/4.9.2',
              'Referer': 'https://$host/',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        throw GatewayException('HTTP ${res.statusCode}');
      }
      final dynamic json =
          jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json is! Map) throw const GatewayException('数据格式异常');
      final code = json['code'];
      if (code is int && code != 200) {
        throw GatewayException('线路返回 $code');
      }
      return res.bodyBytes.length;
    }

    const settingQuery = <String, String>{
      'app_img_shunt': '1',
      'express': '1',
      't': '',
    };

    try {
      // 预热：建立连接 + TLS 握手，不计入成绩。
      await timed('setting', settingQuery);

      // 正式测速：拉首页最新列表，兼顾往返延迟与吞吐。
      Duration elapsed;
      int bytes;
      try {
        final sw = Stopwatch()..start();
        bytes = await timed('latest', <String, String>{'page': '1'});
        sw.stop();
        elapsed = sw.elapsed;
      } catch (_) {
        final sw = Stopwatch()..start();
        bytes = await timed('setting', settingQuery);
        sw.stop();
        elapsed = sw.elapsed;
      }
      return LineProbe(host: host, latency: elapsed, bytes: bytes);
    } catch (e) {
      return LineProbe(host: host, error: _describeError(e));
    }
  }

  static String _describeError(Object e) {
    if (e is TimeoutException) return '连接超时';
    if (e is GatewayException) return e.message;
    return '无法连接';
  }

  Future<List<String>> _resolveHosts() async {
    for (final url in _hostListUrls) {
      try {
        final res = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;

        final raw = utf8.decode(res.bodyBytes, allowMalformed: true);
        final plain = aesEcbDecryptBase64(raw, md5Hex(_hostListSalt));
        if (plain.isEmpty) continue;

        final json = jsonDecode(plain);
        if (json is! Map) continue;

        final servers = (json['Server'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        if (servers.isNotEmpty) return servers;
      } catch (_) {
        // 换下一条清单地址。
      }
    }
    return _fallbackHosts;
  }

  /// 发起 GET 请求并解密业务数据，失败自动重试 3 次。
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    await ensureReady();

    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, v)),
    );

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final res = await _client
            .get(uri, headers: _headers(ts))
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 401) {
          // 登录态被服务端判定失效：清掉本地会话，立刻以未登录身份重试（公开接口可用）。
          if (loggedIn) {
            _handleUnauthorized();
            continue;
          }
          throw const GatewayException('HTTP 401');
        }
        if (res.statusCode != 200) {
          throw GatewayException('HTTP ${res.statusCode}');
        }
        return _decodeBody(
          utf8.decode(res.bodyBytes, allowMalformed: true),
          ts,
          path,
        );
      } catch (e) {
        lastError = e;
        if (e is GatewayException && e.message.startsWith('HTTP 4')) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw GatewayException(lastError?.toString() ?? '网络请求失败');
  }

  dynamic _decodeBody(String body, int ts, String path) {
    final dynamic json = jsonDecode(body);
    if (json is! Map) return json;

    final code = json['code'];
    if (code == 401 || code == '401') {
      if (loggedIn) _handleUnauthorized();
      throw const GatewayException('登录已失效，请重新登录');
    }

    final data = json['data'];
    if (data is String && data.isNotEmpty) {
      final usesFixedKey =
          path.contains('ad_content_all') || path.contains('advertise_all');

      for (final secret in _contentSecrets) {
        final key = usesFixedKey ? md5Hex(secret) : md5Hex('$ts$secret');
        try {
          final plain = aesEcbDecryptBase64(data, key);
          if (plain.isNotEmpty) return jsonDecode(plain);
        } catch (_) {
          // 换下一个 secret。
        }
      }
    }

    final errorMsg = json['errorMsg'];
    if (errorMsg is String && errorMsg.isNotEmpty) {
      throw GatewayException(errorMsg);
    }
    return data;
  }

  // ---------------------------------------------------------------- 登录态

  /// 请求头：签名 + 登录态。
  ///
  /// 未登录时 `Authorization` 发空串（与官方实现一致）；
  /// 登录后带 `Bearer <jwttoken>` 与 `Cookie: AVS=<memberInfo.s>`。
  Map<String, String> _headers(int ts) {
    final token = _jwtToken;
    final avs = _avs;
    return <String, String>{
      'Tokenparam': '$ts,$appVersion',
      'Token': md5Hex('$ts$_signSalt'),
      'Accept': 'application/json',
      'User-Agent': 'okhttp/4.9.2',
      'Referer': ?_baseUrl,
      'Authorization': (token == null || token.isEmpty) ? '' : 'Bearer $token',
      if (avs != null && avs.isNotEmpty) 'Cookie': 'AVS=$avs',
    };
  }

  /// 回填持久化的登录态（App 启动时用）。
  void restoreSession({
    String? jwtToken,
    String? avs,
    Map<String, dynamic>? memberInfo,
  }) {
    _jwtToken = (jwtToken == null || jwtToken.isEmpty) ? null : jwtToken;
    _avs = (avs == null || avs.isEmpty) ? null : avs;
    _memberInfo = memberInfo;
  }

  /// 只清本地登录态，不调服务端。
  void clearSession() {
    _jwtToken = null;
    _avs = null;
    _memberInfo = null;
  }

  /// 服务端 401：清本地会话并通知上层（AppState 会落盘 + 刷新 UI）。
  void _handleUnauthorized() {
    clearSession();
    onAuthExpired?.call();
  }

  /// 登录：`POST login`（multipart），返回 `jwttoken` + `memberInfo`。
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final data = await post('login', <String, String>{
      'username': username.trim(),
      'password': password,
    });

    final map =
        data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    final token = (map['jwttoken'] ?? '').toString();
    if (token.isEmpty) {
      throw const GatewayException('登录失败，请检查账号或密码');
    }

    final avs = (map['s'] ?? '').toString();
    _jwtToken = token;
    _avs = avs.isEmpty ? null : avs;
    _memberInfo = map;

    return AuthSession(jwtToken: token, avs: _avs, memberInfo: map);
  }

  /// 注销：调 `logout` 并清本地登录态（失败也照样本地登出）。
  Future<void> logout() async {
    try {
      if (loggedIn) await post('logout', const <String, String>{});
    } catch (_) {
      // 服务端注销失败不影响本地登出。
    } finally {
      clearSession();
    }
  }

  /// 发起 POST（`multipart/form-data`，不是 JSON），失败自动重试 3 次。
  Future<dynamic> post(String path, Map<String, String> fields) async {
    await ensureReady();

    final uri = Uri.parse('$_baseUrl$path');
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers(ts))
          ..fields.addAll(fields);

        final streamed = await _client
            .send(request)
            .timeout(const Duration(seconds: 15));
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode == 401) {
          if (loggedIn) {
            _handleUnauthorized();
            continue;
          }
          throw const GatewayException('HTTP 401');
        }
        if (res.statusCode != 200) {
          throw GatewayException('HTTP ${res.statusCode}');
        }
        return _decodeBody(
          utf8.decode(res.bodyBytes, allowMalformed: true),
          ts,
          path,
        );
      } catch (e) {
        lastError = e;
        if (e is GatewayException && e.message.startsWith('HTTP 4')) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw GatewayException(lastError?.toString() ?? '网络请求失败');
  }

  // ---------------------------------------------------------------- 业务接口

  Future<Map<String, dynamic>> getSetting() async {
    final data = await get('setting', query: <String, String>{
      'app_img_shunt': '1',
      'express': '1',
      't': '',
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 首页推荐位 / 轮播板块。
  Future<List<dynamic>> promote() async => _asList(await get('promote'));

  /// 最新更新。
  Future<List<dynamic>> latest({int page = 1}) async =>
      _asList(await get('latest', query: <String, String>{'page': '$page'}));

  /// 推荐板块「更多」。
  Future<List<dynamic>> promoteList(String id, {int page = 1}) async =>
      _asList(await get('promote_list',
          query: <String, String>{'id': id, 'page': '$page'}));

  /// 每周连载更新。[date] 0 = 完结，1-7 = 周一至周日。
  Future<Map<String, dynamic>> serialization({
    int type = 0,
    int date = 0,
    int page = 1,
  }) async {
    final data = await get('serialization', query: <String, String>{
      'type': '$type',
      'date': '$date',
      'page': '$page',
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 分类树。
  Future<List<dynamic>> categories() async {
    final data = await get('categories');
    if (data is Map && data['categories'] is List) {
      return data['categories'] as List<dynamic>;
    }
    return _asList(data);
  }

  /// 分类筛选列表。
  Future<Map<String, dynamic>> categoriesFilter({
    int page = 1,
    String? order,
    String? category,
  }) async {
    final data = await get('categories/filter', query: <String, String>{
      'page': '$page',
      'o': ?order,
      'c': ?category,
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 每週必看，返回期数列表。
  Future<List<dynamic>> week({String? type}) async {
    final data = await get('week', query: <String, String>{
      'type': ?type,
    });
    if (data is Map && data['categories'] is List) {
      return data['categories'] as List<dynamic>;
    }
    return _asList(data);
  }

  /// 每週必看筛选（某一期）。
  Future<Map<String, dynamic>> weekFilter({
    required String id,
    String? type,
  }) async {
    final data = await get('week/filter', query: <String, String>{
      'id': id,
      'type': ?type,
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 漫画搜索。
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    String? order,
  }) async {
    final data = await get('search', query: <String, String>{
      'search_query': keyword,
      'page': '$page',
      'o': ?order,
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 热门标签。
  Future<List<dynamic>> hotTags() async => _asList(await get('hot_tags'));

  /// 随机推荐。
  Future<List<dynamic>> randomRecommend() async =>
      _asList(await get('random_recommend'));

  /// 漫画详情。
  Future<Map<String, dynamic>> album(String id) async {
    final data = await get('album', query: <String, String>{'id': id});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 阅读页数据（含 `scramble_id`）。
  Future<Map<String, dynamic>> comicRead(String id) async {
    final data = await get('comic_read', query: <String, String>{'id': id});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 章节信息。
  Future<Map<String, dynamic>> chapter(String id) async {
    final data = await get('chapter', query: <String, String>{'id': id});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 评论列表（`forum`）。[mode] 漫画固定为 `manhua`。
  Future<Map<String, dynamic>> forum({
    required String aid,
    int page = 1,
    String mode = 'manhua',
  }) async {
    final data = await get('forum', query: <String, String>{
      'mode': mode,
      'aid': aid,
      'page': '$page',
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 影片列表。
  Future<Map<String, dynamic>> videos({
    int page = 1,
    String? keyword,
    String? type,
  }) async {
    final data = await get('videos', query: <String, String>{
      'page': '$page',
      if (keyword != null && keyword.isNotEmpty) 'search_query': keyword,
      'video_type': ?type,
    });
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 最新里番。
  Future<List<dynamic>> latestHanime() async =>
      _asList(await get('latest_hanime'));

  /// 小说列表。
  Future<Map<String, dynamic>> novels({int page = 1}) async {
    final data = await get('novels', query: <String, String>{'page': '$page'});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 部落格列表。
  Future<Map<String, dynamic>> blogs({int page = 1}) async {
    final data = await get('blogs', query: <String, String>{'page': '$page'});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 创作者（作者）列表。
  Future<Map<String, dynamic>> creatorAuthor({int page = 1}) async {
    final data =
        await get('creator_author', query: <String, String>{'page': '$page'});
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  // ---------------------------------------------------------------- 账号接口

  /// 我的收藏（`favorite`）。[folderId] 为空表示全部收藏。
  ///
  /// 实测列表必须走 **GET**：POST 会被当成“收藏某部作品”，缺 `aid` 直接 400
  /// （`漫畫ID錯誤`）。响应形如 `{list, folder_list, total, count}`。
  Future<AccountAlbumPage> favorites({int page = 1, String? folderId}) async {
    final data = await get('favorite', query: <String, String>{
      'page': '$page',
      if (folderId != null && folderId.isNotEmpty) 'folder_id': folderId,
    });
    return _accountPage(data, page);
  }

  /// 收藏夹列表。
  ///
  /// 实测不在 `favorite_folder`（那个端点 POST 是增删改，返回 `{status,msg}`），
  /// 而是跟着 `favorite` 列表一起下发的 `folder_list`。
  Future<List<FavoriteFolder>> favoriteFolders() async {
    final data = await get('favorite', query: const <String, String>{'page': '1'});
    if (data is! Map) return const <FavoriteFolder>[];
    final folders = data['folder_list'];
    if (folders is! List) return const <FavoriteFolder>[];
    return folders
        .whereType<Map>()
        .map((e) => FavoriteFolder.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 收藏一部作品（`favorite` + `aid`）。
  Future<void> addFavorite(String aid, {String? folderId}) async {
    await post('favorite', <String, String>{
      'aid': aid,
      if (folderId != null && folderId.isNotEmpty) 'folder_id': folderId,
    });
  }

  /// 浏览历史（`watch_list`，GET 分页）。
  Future<AccountAlbumPage> watchList({int page = 1}) async {
    final data =
        await get('watch_list', query: <String, String>{'page': '$page'});
    return _accountPage(data, page);
  }

  /// 记录一次浏览（`watch_list` + `id`）。失败不影响阅读。
  Future<void> recordWatch(String id) async {
    await post('watch_list', <String, String>{'id': id});
  }

  /// 我追踪的作品（`album_tracking`）。
  ///
  /// 实测 GET / POST 都只回 `{totalCnt}`（没关注时无 list 字段），
  /// 所以这里保持 GET 并做宽容解析，有 list 就展示。
  Future<AccountAlbumPage> trackingList({int page = 1}) async {
    final data =
        await get('album_tracking', query: <String, String>{'page': '$page'});
    return _accountPage(data, page);
  }

  /// 订阅 / 取消订阅作品（`album_sertracking` + `id`）。
  Future<void> toggleTracking(String id) async {
    await post('album_sertracking', <String, String>{'id': id});
  }

  /// 站内通知（`notifications`）。
  ///
  /// 实测同样必须 GET：POST 无论带什么参数都回“缺少参数”。
  Future<List<AccountNotification>> notifications({int page = 1}) async {
    final data =
        await get('notifications', query: <String, String>{'page': '$page'});
    return _asList(data)
        .whereType<Map>()
        .map((e) => AccountNotification.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 未读通知数（`notifications/unreadCount`）。
  ///
  /// 实测返回 `{site_notice, comic_follow}`，需要相加。
  Future<int> unreadNotificationCount() async {
    final data = await post(
      'notifications/unreadCount',
      const <String, String>{},
    );
    if (data is int) return data;
    if (data is Map) {
      var sum = 0;
      for (final key in const <String>['site_notice', 'comic_follow']) {
        final value = data[key];
        sum += value is int
            ? value
            : int.tryParse('${value ?? ''}') ?? 0;
      }
      if (sum > 0) return sum;
      for (final key in const <String>['count', 'total', 'unread']) {
        final value = data[key];
        final parsed = value is int
            ? value
            : int.tryParse('${value ?? ''}') ?? 0;
        if (parsed > 0) return parsed;
      }
    }
    return int.tryParse('${data ?? ''}') ?? 0;
  }

  /// 用户资料（`useredit/{uid}`）。
  Future<Map<String, dynamic>> userProfile(String uid) async {
    final data = await get('useredit/$uid');
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 把分页响应归一化成漫画列表。
  ///
  /// 收藏 / 历史 / 关注三种条目的字段名不完全一致（`id` / `album_id` / `aid`，
  /// `name` / `title`，`image` / `cover`），这里先拉齐再交给 [AlbumSummary]。
  AccountAlbumPage _accountPage(dynamic data, int page) {
    final items = <AlbumSummary>[];
    for (final raw in _asList(data)) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      final normalized = <String, dynamic>{...map};
      if ('${normalized['id'] ?? ''}'.isEmpty) {
        normalized['id'] = map['album_id'] ?? map['aid'];
      }
      normalized['name'] ??= map['title'];
      normalized['image'] ??= map['cover'] ?? map['img'];
      final album = AlbumSummary.fromJson(normalized);
      if (album.id.isNotEmpty) items.add(album);
    }

    var total = 0;
    if (data is Map) {
      final raw = data['total'] ?? data['count'];
      total = raw is int ? raw : int.tryParse('${raw ?? ''}') ?? 0;
    }
    return AccountAlbumPage(items: items, page: page, total: total);
  }

  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const <String>['list', 'content', 'data']) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const <dynamic>[];
  }

  void dispose() => _client.close();
}
