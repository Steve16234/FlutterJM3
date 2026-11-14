/// 网关返回的数据模型。字段命名严格对齐实测报文。
library;

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

List<String> _asStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String && v.isNotEmpty) {
    return v.split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).toList();
  }
  return const <String>[];
}

final RegExp _htmlBr = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _htmlBlockEnd = RegExp(r'</(div|p|li)>', caseSensitive: false);
final RegExp _htmlTag = RegExp(r'<[^>]*>');
final RegExp _htmlBlankLines = RegExp(r'\n{3,}');
final RegExp _htmlNumericEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');

const Map<String, String> _htmlNamedEntities = <String, String>{
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
};

/// 把评论正文的 HTML 片段转成纯文本。
///
/// 网关返回的评论形如 `<div style='...'>正文</div>`，换行用 `<br>`，
/// 表情符直接以 Unicode 字符内联；这里只保留文字并还原常见实体。
String htmlToPlainText(String html) {
  if (html.isEmpty) return '';

  var text = html
      // 网关正文里混着 `\r\n`，不先归一化的话行尾会留 `\r`，
      // 在 Text 里会变成空白行/宽度异常。
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_htmlBr, '\n')
      .replaceAll(_htmlBlockEnd, '\n')
      .replaceAll(_htmlTag, '');

  for (final entry in _htmlNamedEntities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  text = text.replaceAllMapped(_htmlNumericEntity, (match) {
    final isHex = match.group(1) == 'x';
    final code = int.tryParse(match.group(2)!, radix: isHex ? 16 : 10);
    return code == null ? '' : String.fromCharCode(code);
  });

  return text.replaceAll(_htmlBlankLines, '\n\n').trim();
}

/// 分类（`categories`）。
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.totalAlbums,
    required this.subCategories,
  });

  final String id;
  final String name;
  final String slug;
  final int totalAlbums;
  final List<SubCategory> subCategories;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: _asString(json['id']),
      name: _asString(json['name']),
      slug: _asString(json['slug']),
      totalAlbums: _asInt(json['total_albums']),
      subCategories: (json['sub_categories'] as List?)
              ?.whereType<Map>()
              .map((e) => SubCategory.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <SubCategory>[],
    );
  }
}

class SubCategory {
  const SubCategory({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      id: _asString(json['CID'] ?? json['id']),
      name: _asString(json['name']),
      slug: _asString(json['slug']),
    );
  }
}

/// 列表 / 搜索 / 收藏里出现的漫画条目。
class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.image,
    required this.categoryTitle,
    required this.categorySubTitle,
    required this.updateAt,
    required this.addDate,
  });

  final String id;
  final String name;
  final String author;
  final String description;

  /// 网关在多数列表接口里返回空字符串，需要用 [coverUrl] 兜底。
  final String image;
  final String categoryTitle;
  final String categorySubTitle;
  final int updateAt;
  final String addDate;

  factory AlbumSummary.fromJson(Map<String, dynamic> json) {
    String sub(Map<String, dynamic>? m) => _asString(m?['title']);

    return AlbumSummary(
      id: _asString(json['id']),
      name: _asString(json['name']),
      author: _asString(json['author']),
      description: _asString(json['description']),
      image: _asString(json['image']),
      categoryTitle: sub(json['category'] as Map<String, dynamic>?),
      categorySubTitle: sub(json['category_sub'] as Map<String, dynamic>?),
      updateAt: _asInt(json['update_at']),
      addDate: _asString(json['adddate']),
    );
  }

  /// 封面地址：接口给了相对/绝对地址就直接用，否则按 `media/albums/{id}.jpg` 拼。
  String coverUrl(String imgHost) {
    if (image.startsWith('http')) return image;
    if (image.isNotEmpty) {
      return image.startsWith('/') ? '$imgHost$image' : '$imgHost/$image';
    }
    return '$imgHost/media/albums/$id.jpg';
  }
}

/// 首页推荐板块（`promote`）。
class PromoteSection {
  const PromoteSection({
    required this.id,
    required this.title,
    required this.filterValue,
    required this.items,
  });

  final String id;
  final String title;
  final String filterValue;
  final List<AlbumSummary> items;

  factory PromoteSection.fromJson(Map<String, dynamic> json) {
    return PromoteSection(
      id: _asString(json['id']),
      title: _asString(json['title']),
      filterValue: _asString(json['filter_val']),
      items: (json['content'] as List?)
              ?.whereType<Map>()
              .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <AlbumSummary>[],
    );
  }
}

/// 漫画详情（`album`）。
class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.totalViews,
    required this.totalPhotos,
    required this.likes,
    required this.commentTotal,
    required this.addTime,
    required this.authors,
    required this.tags,
    required this.works,
    required this.actors,
    required this.series,
    required this.related,
  });

  final String id;
  final String name;
  final String description;
  final int totalViews;
  final int totalPhotos;
  final int likes;
  final int commentTotal;
  final int addTime;
  final List<String> authors;
  final List<String> tags;
  final List<String> works;
  final List<String> actors;
  final List<AlbumSummary> series;
  final List<AlbumSummary> related;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    List<AlbumSummary> list(String key) =>
        (json[key] as List?)
            ?.whereType<Map>()
            .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const <AlbumSummary>[];

    return AlbumDetail(
      id: _asString(json['id']),
      name: _asString(json['name']),
      description: _asString(json['description']),
      totalViews: _asInt(json['total_views']),
      totalPhotos: _asInt(json['total_photos']),
      likes: _asInt(json['likes']),
      commentTotal: _asInt(json['comment_total']),
      addTime: _asInt(json['addtime']),
      authors: _asStringList(json['author']),
      tags: _asStringList(json['tags']),
      works: _asStringList(json['works']),
      actors: _asStringList(json['actors']),
      series: list('series'),
      related: list('related_list'),
    );
  }
}

/// 阅读页单页。
class ComicPage {
  const ComicPage({required this.page, required this.url});

  final int page;
  final String url;

  factory ComicPage.fromJson(Map<String, dynamic> json) {
    return ComicPage(
      page: _asInt(json['page']),
      url: _asString(json['image']),
    );
  }
}

/// 阅读页数据（`comic_read`）。
class ComicRead {
  const ComicRead({
    required this.id,
    required this.scrambleId,
    required this.name,
    required this.totalPage,
    required this.pages,
  });

  final String id;

  /// 图片乱序种子。早于该 id 的作品（以及 `.gif`）不打乱。
  final int scrambleId;
  final String name;
  final int totalPage;
  final List<ComicPage> pages;

  factory ComicRead.fromJson(Map<String, dynamic> json) {
    return ComicRead(
      id: _asString(json['id']),
      scrambleId: _asInt(json['scramble_id']),
      name: _asString(json['name']),
      totalPage: _asInt(json['total_page']),
      pages: (json['images'] as List?)
              ?.whereType<Map>()
              .map((e) => ComicPage.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <ComicPage>[],
    );
  }
}

/// 分页结果（`search` / `categories/filter` / `videos` / `novels`）。
class PagedAlbums {
  const PagedAlbums({
    required this.items,
    required this.total,
    required this.page,
  });

  final List<AlbumSummary> items;
  final int total;
  final int page;

  bool get hasMore => items.isNotEmpty && page * items.length < total;

  factory PagedAlbums.fromJson(Map<String, dynamic> json, {int page = 1}) {
    return PagedAlbums(
      items: (json['content'] as List? ?? json['list'] as List?)
              ?.whereType<Map>()
              .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <AlbumSummary>[],
      total: _asInt(json['total']),
      page: page,
    );
  }
}

/// 每週必看期数（`week`）。
class WeekIssue {
  const WeekIssue({
    required this.id,
    required this.title,
    required this.time,
  });

  final String id;
  final String title;
  final String time;

  factory WeekIssue.fromJson(Map<String, dynamic> json) {
    return WeekIssue(
      id: _asString(json['id']),
      title: _asString(json['title']),
      time: _asString(json['time']),
    );
  }
}

/// 一条评论（`forum`）。
///
/// 网关字段：`CID` 评论 id、`UID` 作者 id、`parent_CID` 父评论（`0` 为顶层）、
/// `content` 为 HTML 片段、`photo` 为头像文件名、`spoiler` 为剧透标记。
class Comment {
  const Comment({
    required this.id,
    required this.uid,
    required this.username,
    required this.nickname,
    required this.likes,
    required this.content,
    required this.addTime,
    required this.parentId,
    required this.level,
    required this.levelName,
    required this.photo,
    required this.spoiler,
  });

  final String id;
  final String uid;
  final String username;
  final String nickname;

  /// 点赞数。
  final int likes;

  /// 已去掉 HTML 标签的纯文本正文。
  final String content;

  /// 服务端已格式化的时间，形如 `Nov 13, 2026`。
  final String addTime;

  /// 父评论 id，`0` 表示顶层评论。
  final String parentId;

  /// 用户等级。
  final int level;
  final String levelName;

  /// 头像文件名，形如 `1818901.jpg` 或 `nopic-Male.gif`。
  final String photo;

  /// 剧透标记：实测 `1` 普通、`2` 剧透。
  final String spoiler;

  bool get isReply => parentId.isNotEmpty && parentId != '0';

  bool get isSpoiler => spoiler == '2';

  /// 展示名：优先昵称，缺失时回退用户名。
  String get displayName {
    if (nickname.isNotEmpty && nickname != 'null') return nickname;
    return username;
  }

  /// 头像地址，规则为 `<imgHost>/media/users/<photo>`。
  String avatarUrl(String imgHost) {
    if (photo.isEmpty || photo == 'null') return '';
    if (photo.startsWith('http')) return photo;
    return '$imgHost/media/users/$photo';
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    final exp = json['expinfo'];
    return Comment(
      id: _asString(json['CID']),
      uid: _asString(json['UID']),
      username: _asString(json['username']),
      nickname: _asString(json['nickname']),
      likes: _asInt(json['likes']),
      content: htmlToPlainText(_asString(json['content'])),
      addTime: _asString(json['addtime']),
      parentId: _asString(json['parent_CID']),
      level: _asInt(exp is Map ? exp['level'] : null),
      levelName: _asString(exp is Map ? exp['level_name'] : null),
      photo: _asString(json['photo']),
      spoiler: _asString(json['spoiler']),
    );
  }
}

/// 评论分页（`forum` 返回 `{list, total}`，`total` 为字符串）。
class PagedComments {
  const PagedComments({
    required this.items,
    required this.total,
    required this.page,
  });

  final List<Comment> items;
  final int total;
  final int page;

  factory PagedComments.fromJson(Map<String, dynamic> json, {int page = 1}) {
    return PagedComments(
      items: (json['list'] as List?)
              ?.whereType<Map>()
              .map((e) => Comment.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <Comment>[],
      total: _asInt(json['total']),
      page: page,
    );
  }
}

/// 影片条目。
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.photo,
    required this.tags,
  });

  final String id;
  final String title;
  final String photo;
  final List<String> tags;

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: _asString(json['id']),
      title: _asString(json['title']),
      photo: _asString(json['photo'] ?? json['photo_str']),
      tags: _asStringList(json['tags']),
    );
  }

  String coverUrl(String imgHost) {
    if (photo.startsWith('http')) return photo;
    if (photo.isEmpty) return '';
    return photo.startsWith('/') ? '$imgHost$photo' : '$imgHost/$photo';
  }
}
