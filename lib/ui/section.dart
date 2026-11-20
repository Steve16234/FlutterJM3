import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// 分组：把若干行变成 iOS「inset grouped」那样子——一张卡、行间发丝线。

/// 分组标题：小节名 + 可选的右侧动作。
///
/// ```dart
/// SectionHeader(
///   title: '外观',
///   action: TextButton(onPressed: reset, child: const Text('重置')),
/// )
/// ```
///
/// 直接复用 prism 的 `ListHeader`（`AppTextStyle.headline` +
/// `onSurfaceVariant`、上 24 / 下 8 的留白、动作按设计系统对齐），所以它的排版
/// 和设计要求完全一致，不需要自己量字号。
///
/// 注意：`ListHeader` 会读 `MeasureScope`（`PrismApp` / `PrismHost` 已经提供）；
/// 在裸 widget 测试里渲染它要先包一层 `MeasureScope`。
///
/// 什么时候别用：卡片内部的次级小标题用 `AppTextStyle.footnote` 的普通文字就行，
/// 一个页面里这种分组标题不要超过 4 个。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;

  /// 右侧动作（文字按钮 / 图标按钮）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListHeader(title: title, trailing: action);
  }
}

/// 一张把若干行包在一起的分组卡，行间自动加发丝线。
///
/// ```dart
/// SectionCard(children: <Widget>[
///   SettingRow(title: '跟随系统', trailing: Switch(value: v, onChanged: setV)),
///   SettingRow(title: '纯黑', trailing: Switch(value: p, onChanged: setP)),
/// ])
/// ```
///
/// 它自己就是「card 层级」的那张表面：内部用 `SurfaceScope` 把层级往下传给
/// 每一行（`rows.dart` 的行会因此变成透明行，填充/圆角只用这一张卡的），
/// 所以**调用点不要自己再包 Card，也不要在外面写层级的名字**。
///
/// 发丝线用 `Divider`，颜色只来自 `Divider.colorOf(context)`（`onSurface` @14%），
/// 左右内缩 16 与行内容对齐。
///
/// 什么时候别用：一行也用不着分组（单个 `SettingRow` 自己就是一张卡）；
/// 可滚动的长列表（几十行）用 `ListHeader` + `generateGroup` 的 sliver 版本，
/// 这张卡是一次性构建全部子行的 `Column`。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children, this.padding});

  /// 行（`SettingRow` / `NavigationRow` / `ValueRow`）或任何放在行位上的 widget。
  final List<Widget> children;

  /// 卡片内边距；默认 0，行的左右 16 由 `ListRow` 自己给。
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final level = context.raisedSurfaceLevel;
    final scheme = context.colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const _Hairline());
      }
      rows.add(children[i]);
    }
    return PressSurface(
      fill: level.colorOf(scheme),
      shape: AppShape.xl,
      childFills: true,
      // 行在卡内按下时的状态层是方的，必须由这张卡裁成连续圆角。
      clipsChild: true,
      child: SurfaceScope(
        level: level,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }
}

/// 标签云：作品的标签 / 作品 / 角色。
///
/// ```dart
/// TagWrap(tags: detail.tags, onTagPressed: (tag) => search(tag))
/// ```
///
/// 给了 [onTagPressed] → 用 prism 的 `Chip`（36dp 药丸、可按）；
/// 没给 → 用 `MetaChip`（小号灰底标签，纯展示）。
/// 两者都是「block 层级的灰底」，**没有**用 `primaryContainer` 填充
/// （规范禁止用容器色表达标签）。
///
/// 什么时候别用：标签只有一个时直接放 `MetaChip`；需要「选中态」的筛选
/// 用 `Chip(selected: true)`，每组只能有一个选中。
class TagWrap extends StatelessWidget {
  const TagWrap({super.key, required this.tags, this.onTagPressed});

  final List<String> tags;

  /// 非空时标签变成可点的 chip。
  final ValueChanged<String>? onTagPressed;

  @override
  Widget build(BuildContext context) {
    final onTagPressed = this.onTagPressed;
    final visible = tags.where((tag) => tag.isNotEmpty).toList(growable: false);
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final tag in visible)
          if (onTagPressed == null)
            MetaChip(label: tag)
          else
            Chip(label: tag, onPressed: () => onTagPressed(tag)),
      ],
    );
  }
}

/// 行间发丝线。颜色只能来自 [Divider.colorOf]，不用 `outlineVariant`。
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 1),
    );
  }
}
