import 'models.dart';

String _s(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

bool _b(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final text = '${v ?? ''}'.toLowerCase();
  return text == '1' || text == 'true';
}

/// 收藏夹（`favorite_folder`）。
class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;
  final String name;
  final int count;

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) {
    return FavoriteFolder(
      id: _s(json['id'] ?? json['folder_id'] ?? json['FID']),
      name: _s(json['name'] ?? json['folder_name'], '收藏夹'),
      count: _i(json['count'] ?? json['total']),
    );
  }
}

/// 账号相关的一页列表（我的收藏 / 浏览历史 / 我的关注）。
class AccountAlbumPage {
  const AccountAlbumPage({
    required this.items,
    required this.page,
    required this.total,
  });

  final List<AlbumSummary> items;
  final int page;
  final int total;

  /// 是否还有下一页：这一页拿到了内容就继续翻，空页即到底。
  bool get hasMore => items.isNotEmpty;

  static const AccountAlbumPage empty =
      AccountAlbumPage(items: <AlbumSummary>[], page: 1, total: 0);
}

/// 站内通知（`notifications`）。
class AccountNotification {
  const AccountNotification({
    required this.id,
    required this.title,
    required this.content,
    required this.time,
    required this.read,
  });

  final String id;
  final String title;
  final String content;
  final String time;
  final bool read;

  factory AccountNotification.fromJson(Map<String, dynamic> json) {
    return AccountNotification(
      id: _s(json['id'] ?? json['ID']),
      title: _s(json['title'] ?? json['name'], '通知'),
      content: htmlToPlainText(
        _s(json['content'] ?? json['message'] ?? json['text']),
      ),
      // 实测字段是 `date`，兼容 `addtime` / `created_at`。
      time: _s(json['date'] ?? json['addtime'] ?? json['time'] ?? json['created_at']),
      read: _b(json['read'] ?? json['is_read'] ?? json['status']),
    );
  }
}
