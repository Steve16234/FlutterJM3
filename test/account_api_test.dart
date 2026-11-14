import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/gateway_client.dart';

import 'support/fake_gateway.dart';

void main() {
  late List<SeenRequest> seen;

  GatewayClient clientWith(Map<String, dynamic> responses) {
    seen = <SeenRequest>[];
    return GatewayClient(
      client: fakeGateway(responses: responses, seen: seen),
    );
  }

  test('我的收藏：GET favorite（POST 会 400），带 page / folder_id', () async {
    final client = clientWith(<String, dynamic>{
      'favorite': <String, dynamic>{
        'list': <Map<String, dynamic>>[
          <String, dynamic>{'id': '1', 'name': 'A'},
          <String, dynamic>{'album_id': 2, 'title': 'B', 'image': ''},
        ],
        'total': 2,
      },
    });

    final page = await client.favorites(page: 2, folderId: '7');

    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/favorite');
    expect(seen.last.url.queryParameters['page'], '2');
    expect(seen.last.url.queryParameters['folder_id'], '7');
    expect(page.items.map((e) => e.id).toList(), <String>['1', '2']);
    expect(page.items.map((e) => e.name).toList(), <String>['A', 'B']);
    expect(page.total, 2);
    expect(page.hasMore, isTrue);
  });

  test('收藏夹列表来自 favorite 响应的 folder_list', () async {
    final client = clientWith(<String, dynamic>{
      'favorite': <String, dynamic>{
        'list': <dynamic>[],
        'folder_list': <Map<String, dynamic>>[
          <String, dynamic>{'id': '0', 'name': '默认收藏夹', 'count': 12},
        ],
      },
    });

    final folders = await client.favoriteFolders();

    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/favorite');
    expect(folders.single.name, '默认收藏夹');
    expect(folders.single.count, 12);
  });

  test('收藏作品：POST favorite + aid', () async {
    final client = clientWith(const <String, dynamic>{});
    await client.addFavorite('123456');
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/favorite');
    expect(seen.last.body, contains('name="aid"'));
    expect(seen.last.body, contains('123456'));
  });

  test('浏览历史：GET watch_list?page=3', () async {
    final client = clientWith(<String, dynamic>{
      'watch_list': <String, dynamic>{
        'list': <Map<String, dynamic>>[
          <String, dynamic>{'id': '9', 'name': 'H', 'image': 'https://x/y.jpg'},
        ],
      },
    });

    final page = await client.watchList(page: 3);

    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/watch_list');
    expect(seen.last.url.queryParameters['page'], '3');
    expect(page.items.single.id, '9');
    expect(page.items.single.name, 'H');
  });

  test('记录浏览：POST watch_list + id', () async {
    final client = clientWith(const <String, dynamic>{});
    await client.recordWatch('888');
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/watch_list');
    expect(seen.last.body, contains('name="id"'));
    expect(seen.last.body, contains('888'));
  });

  test('我的关注：GET album_tracking（实测只回 totalCnt）', () async {
    final client = clientWith(<String, dynamic>{
      'album_tracking': <String, dynamic>{'totalCnt': 0},
    });

    final page = await client.trackingList(page: 1);
    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/album_tracking');
    expect(seen.last.url.queryParameters['page'], '1');
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);

    await client.toggleTracking('5');
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/album_sertracking');
    expect(seen.last.body, contains('name="id"'));
  });

  test('未读数：site_notice + comic_follow 相加', () async {
    final client = clientWith(<String, dynamic>{
      'notifications/unreadCount': <String, dynamic>{
        'site_notice': 3,
        'comic_follow': 2,
      },
    });
    expect(await client.unreadNotificationCount(), 5);
    expect(seen.last.path, '/notifications/unreadCount');
  });

  test('通知列表：GET notifications，解析标题 / 正文（去 HTML）/ 已读 / date', () async {
    final client = clientWith(<String, dynamic>{
      'notifications': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'n1',
          'type': 'site_notice',
          'title': '新章节',
          'content': '<div>第 2 话<br>已更新</div>',
          'date': '2026-10-21',
          'read': true,
        },
      ],
    });

    final list = await client.notifications();
    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/notifications');
    expect(list.single.title, '新章节');
    expect(list.single.content, contains('第 2 话'));
    expect(list.single.content, isNot(contains('<div>')));
    expect(list.single.read, isTrue);
    expect(list.single.time, '2026-10-21');
  });

  test('用户资料：GET useredit/{uid}', () async {
    final client = clientWith(<String, dynamic>{
      'useredit/42': <String, dynamic>{'username': 'tester', 'coin': 9},
    });

    final profile = await client.userProfile('42');
    expect(seen.last.method, 'GET');
    expect(seen.last.path, '/useredit/42');
    expect(profile['username'], 'tester');
  });

  test('空页视为到底', () async {
    final client = clientWith(<String, dynamic>{
      'favorite': <String, dynamic>{'list': <dynamic>[], 'total': 0},
    });
    final page = await client.favorites();
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });
}
