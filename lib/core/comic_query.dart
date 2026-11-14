/// 从搜索框输入里解析出作品号。
///
/// 支持 `1488098`、`JM1488098`、`jm 1488098`、`#1488098` 这几种写法；
/// 至少 4 位数字才当作作品号，避免把「2024」这类关键词误判成 id。
String? albumIdFromQuery(String query) {
  final text = query.trim();
  if (text.isEmpty) return null;

  final match = RegExp(
    r'^(?:jm)?[\s#_-]*(\d{4,})$',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}
