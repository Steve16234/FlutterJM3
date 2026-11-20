import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';

/// 行组件：设置行 / 跳转行 / 只读的值行。
///
/// 三者的几何都来自 `Card` + `ListRow`（prism 的 `ListRow` 只管排布，**不带点击**，
/// 可点击必须由外面的 `Card`/`PressSurface` 提供）。
///
/// ## 单独用 vs 放进分组
///
/// 行是自适应的，调用点不用判断：
///
/// * 直接放在页面上（`SurfaceLevel.page`）→ 每行是一颗独立的圆角 `Card`；
/// * 已经被 `SectionCard` 包进分组（层级已抬到 `card`）→ 行只画按压反馈，
///   填充和圆角交给外层那张卡，行与行之间由 `SectionCard` 画发丝线。
///
/// 这就是「内部行自动降一级」的落点：判断依据是 `context.surfaceLevel`，
/// **不在调用点硬编码层级**。

/// 设置项：左侧可选一个 glyph，标题 + 副标题，右侧控件（开关、按钮、值文字）。
///
/// ```dart
/// SectionCard(children: <Widget>[
///   SettingRow(
///     glyph: AppGlyphs.palette,
///     title: '主题',
///     subtitle: '跟随系统',
///     trailing: Switch(value: dark, onChanged: (v) => setDark(v)),
///   ),
///   SettingRow(
///     glyph: AppGlyphs.delete,
///     title: '退出登录',
///     danger: true,
///     onPressed: () => confirmLogout(context),
///   ),
/// ])
/// ```
///
/// [danger] 用 `ColorScheme.destructive`（iOS 的 systemRed），**不是** `error`：
/// `error` 留给「出错了」，删除类动作一律 destructive。
///
/// 什么时候别用：跳转用 `NavigationRow`（它带 chevron）；纯展示一个「标题 + 值」
/// 用 `ValueRow`；行尾不要放「⋯」按钮，次要动作走 `ContextMenuRegion`。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onPressed,
    this.danger = false,
  });

  /// 左侧图标；`null` 表示不留图标位（标题会贴到行首）。
  final Glyph? glyph;

  final String title;
  final String? subtitle;

  /// 行尾控件。放 `Switch` / `Checkbox` / `IconButton` / 值文字都行。
  final Widget? trailing;

  /// `null` = 不可点，但行仍然用正常颜色显示（不是禁用的灰）。
  final VoidCallback? onPressed;

  /// 危险动作：标题和图标都上 `ColorScheme.destructive`。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final glyph = this.glyph;
    final subtitle = this.subtitle;
    return _rowShell(
      context,
      onPressed: onPressed,
      child: ListRow(
        leading: glyph == null
            ? null
            : GlyphIcon(
                glyph,
                color: danger
                    ? scheme.destructive
                    : scheme.onSurfaceVariant,
              ),
        title: Text(
          title,
          style: danger
              ? context.listTitleStyle.copyWith(color: scheme.destructive)
              : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}

/// 跳转行：标题（+ 副标题），右侧固定一个 chevron。
///
/// ```dart
/// SectionCard(children: <Widget>[
///   NavigationRow(
///     glyph: AppGlyphs.star,
///     title: '我的收藏',
///     subtitle: '共 128 部',
///     onPressed: () => openFavorites(context),
///   ),
/// ])
/// ```
///
/// [trailing] 会排在 chevron 左边（例如一个「未读 3」的小标记）。
/// 什么时候别用：行内动作（开关/按钮）用 `SettingRow`；不跳转、也没有动作的
/// 信息展示不要做成带 chevron 的行，那是在骗点击。
class NavigationRow extends StatelessWidget {
  const NavigationRow({
    super.key,
    this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onPressed,
  });

  final Glyph? glyph;
  final String title;
  final String? subtitle;

  /// chevron 左边的附加内容。
  final Widget? trailing;

  /// 跳转动作；必填——带 chevron 的行永远可点。
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final glyph = this.glyph;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return _rowShell(
      context,
      onPressed: onPressed,
      child: ListRow(
        leading: glyph == null
            ? null
            : GlyphIcon(glyph, color: scheme.onSurfaceVariant),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: <Widget>[?trailing, const DisclosureIndicator()],
        ),
      ),
    );
  }
}

/// 只读行：左边标题，右边值文字（`onSurfaceVariant`）。
///
/// ```dart
/// SectionCard(children: <Widget>[
///   const ValueRow(title: '版本', value: '1.0.0+1'),
///   const ValueRow(title: '当前线路', value: 'https://18comic.vip'),
/// ])
/// ```
///
/// 不可点，所以**不要**给它传 onPressed —— 需要点击用 `SettingRow`。
/// 值很长时会被省略号截断（`ListRow` 的行尾最多占一半宽），需要看全文就让
/// 调用方把它拆成副标题。
class ValueRow extends StatelessWidget {
  const ValueRow({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _rowShell(
      context,
      child: ListRow(
        title: Text(title),
        trailing: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.subheadline
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 行的外壳，按当前表面层级二选一：
///
/// * 页面上 → 独立 `Card`（自带填充 / 圆角 / 按压 / 焦点环 / 语义）；
/// * 分组里 → 透明 `PressSurface` 只提供按压状态层，表面由外层卡负责；
///   不可点（[ValueRow]）时连 PressSurface 都不要，直接就是一行。
Widget _rowShell(
  BuildContext context, {
  required Widget child,
  VoidCallback? onPressed,
}) {
  if (context.surfaceLevel != SurfaceLevel.page) {
    if (onPressed == null) {
      return child;
    }
    return PressSurface(
      // 透明：这一行没有自己的填充，用的是外层卡片的表面。
      fill: Colors.transparent,
      shape: AppShape.none,
      onPressed: onPressed,
      child: child,
    );
  }
  return Card(
    radius: AppCorner.xl,
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    // 不可点时保持正常颜色（inert），否则 Card 会把内容压到 38% 透明。
    inert: onPressed == null,
    child: child,
  );
}
