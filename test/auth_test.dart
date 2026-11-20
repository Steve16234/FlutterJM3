import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/gateway_client.dart';
import 'package:flutterjm/core/settings_store.dart';
import 'package:flutterjm/core/theme_mode.dart';
import 'package:flutterjm/state/app_state.dart';

import 'support/fake_gateway.dart';

void main() {
  group('GatewayClient 登录', () {
    test('成功后解析 jwttoken / AVS，并带上鉴权头', () async {
      final seen = <Map<String, String>>[];
      final bodies = <String>[];
      final client = GatewayClient(
        client: fakeGateway(
          loginData: loginOk,
          seenHeaders: seen,
          seenBodies: bodies,
        ),
      );

      final session = await client.login(username: ' tester ', password: 'p@ss');

      expect(session.jwtToken, 'JWT-1');
      expect(session.avs, 'AVS-1');
      expect(session.username, 'tester');
      expect(session.userId, '42');
      expect(client.loggedIn, isTrue);

      // POST 是 multipart/form-data，账号密码在表单字段里
      expect(bodies.single, contains('name="username"'));
      expect(bodies.single, contains('tester'));
      expect(bodies.single, contains('name="password"'));

      // 之后的业务请求要带 Bearer + AVS Cookie
      seen.clear();
      await client.promote();
      final after = seen.last;
      expect(after['Authorization'], 'Bearer JWT-1');
      expect(after['Cookie'], 'AVS=AVS-1');
    });

    test('未登录时 Authorization 为空串且不带 Cookie', () async {
      final seen = <Map<String, String>>[];
      final client = GatewayClient(client: fakeGateway(seenHeaders: seen));
      await client.promote();
      expect(seen.last['Authorization'], '');
      expect(seen.last.containsKey('Cookie'), isFalse);
    });

    test('响应里没有 jwttoken 视为登录失败', () async {
      final client = GatewayClient(
        client: fakeGateway(loginData: <String, dynamic>{'username': 'tester'}),
      );
      await expectLater(
        client.login(username: 'tester', password: 'bad'),
        throwsA(isA<GatewayException>()),
      );
      expect(client.loggedIn, isFalse);
    });

    test('HTTP 401 直接抛错', () async {
      final client = GatewayClient(client: fakeGateway(loginStatus: 401));
      await expectLater(
        client.login(username: 'tester', password: 'bad'),
        throwsA(isA<GatewayException>()),
      );
      expect(client.loggedIn, isFalse);
    });

    test('logout 会清空本地登录态', () async {
      final client = GatewayClient(client: fakeGateway(loginData: loginOk));
      await client.login(username: 'tester', password: 'ok');
      expect(client.loggedIn, isTrue);

      await client.logout();
      expect(client.loggedIn, isFalse);
      expect(client.memberInfo, isNull);
    });
  });

  group('AppState 登录态持久化', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('jm_auth_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('登录后落盘，重启仍是登录态', () async {
      final first = AppState(
        client: GatewayClient(client: fakeGateway(loginData: loginOk)),
        settings: SettingsStore(directory: tmp),
      );
      await first.restoreSettings();
      await first.login(username: 'tester', password: 'p@ss');

      expect(first.loggedIn, isTrue);
      expect(first.username, 'tester');
      expect(first.userId, 42);
      expect(first.avatarUrl, 'https://img.example/media/users/abc.jpg');

      final saved = await SettingsStore(directory: tmp).read();
      expect(saved.jwtToken, 'JWT-1');
      expect(saved.avs, 'AVS-1');
      expect(saved.memberInfo?['username'], 'tester');
      expect(saved.hasSession, isTrue);
      first.dispose();

      final second = AppState(
        client: GatewayClient(client: fakeGateway()),
        settings: SettingsStore(directory: tmp),
      );
      await second.restoreSettings();
      expect(second.loggedIn, isTrue);
      expect(second.username, 'tester');
      second.dispose();
    });

    test('存过 token 就一直保持登录（不因时间过期）', () async {
      await SettingsStore(directory: tmp).write(
        const AppSettings(
          jwtToken: 'JWT-OLD',
          avs: 'AVS-OLD',
          memberInfo: <String, dynamic>{'username': 'old', 'id': 1},
        ),
      );

      final app = AppState(
        client: GatewayClient(client: fakeGateway()),
        settings: SettingsStore(directory: tmp),
      );
      await app.restoreSettings();
      expect(app.loggedIn, isTrue);
      expect(app.username, 'old');
      app.dispose();
    });

    test('服务端 401 时自动登出，且存档一并清空', () async {
      var unauthorized = false;
      final seen = <Map<String, String>>[];
      final app = AppState(
        client: GatewayClient(
          client: fakeGateway(
            loginData: loginOk,
            unauthorized: () => unauthorized,
            seenHeaders: seen,
          ),
        ),
        settings: SettingsStore(directory: tmp),
      );
      await app.restoreSettings();
      await app.login(username: 'tester', password: 'p@ss');
      expect(app.loggedIn, isTrue);

      // 服务端开始回 401
      unauthorized = true;
      seen.clear();
      await expectLater(
        app.client.promote(),
        throwsA(isA<GatewayException>()),
      );

      // 第一次带 Bearer，清掉会话后立刻以未登录身份重试
      expect(seen.first['Authorization'], 'Bearer JWT-1');
      expect(seen.last['Authorization'], '');

      expect(app.loggedIn, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final saved = await SettingsStore(directory: tmp).read();
      expect(saved.jwtToken, isNull);
      app.dispose();
    });

    test('登出后存档里的登录态被清空', () async {
      final app = AppState(
        client: GatewayClient(client: fakeGateway(loginData: loginOk)),
        settings: SettingsStore(directory: tmp),
      );
      await app.restoreSettings();
      await app.login(username: 'tester', password: 'p@ss');
      await app.logout();
      expect(app.loggedIn, isFalse);

      final saved = await SettingsStore(directory: tmp).read();
      expect(saved.jwtToken, isNull);
      expect(saved.hasSession, isFalse);
      app.dispose();
    });

    test('主题与登录态互不影响', () async {
      final app = AppState(
        client: GatewayClient(client: fakeGateway(loginData: loginOk)),
        settings: SettingsStore(directory: tmp),
      );
      await app.restoreSettings();
      app.setThemeMode(JmThemeMode.dark);
      await app.login(username: 'tester', password: 'p@ss');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final saved = await SettingsStore(directory: tmp).read();
      expect(saved.themeMode, JmThemeMode.dark);
      expect(saved.hasSession, isTrue);
      app.dispose();
    });
  });
}
