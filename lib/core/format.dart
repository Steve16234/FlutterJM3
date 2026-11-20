/// 与界面无关的纯格式化工具。
///
/// 放在 core 层是为了让已经迁移到 prism_ui 的页面不必再 import 旧的
/// `widgets/common.dart`（那个文件还带着 Material 的视图组件）。
library;

/// 相对时间：刚刚 / x 分钟前 / x 小时前 / x 天前 / yyyy-MM-dd。
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

/// 数字缩写：1.2万 / 3.4亿。
String compactNumber(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万';
  }
  return '$value';
}
