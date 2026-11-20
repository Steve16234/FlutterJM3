import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';

/// 页面/列表的三态视图：加载中、空、出错。
///
/// 三者都建立在 prism 自己的 `ActivityIndicator` / `NullStatus` 上，所以颜色、
/// 字号、插图编排、进场动画、深色模式全部由设计系统决定，调用点只给文案。
///
/// ## 高度（很重要）
///
/// 三个组件默认「居中填充父级给的高度」，按下面的规则处理无界高度：
///
/// | 放在哪 | 怎么用 |
/// |---|---|
/// | `Scaffold`/`PrismScaffold` 的 body、`Expanded`、`SizedBox`（高度有界） | 直接当 child，自动垂直居中 |
/// | `ListView` / `Column` 里（高度无界） | 用 `.sliver()` 版本配 `CustomScrollView`，或自己包一层固定高度 |
/// | `CustomScrollView` 的 slivers | `JmLoading.sliver()` / `JmEmpty.sliver()` / `JmError.sliver()` |
///
/// 它们**不会**在无界高度里报错：拿不到有界高度时就按内容自适应（只是不再居中）。

/// 加载中。
///
/// 用 `ActivityIndicator.page()`（prism 的整页转圈），不要用 Material 的
/// `CircularProgressIndicator`（prism_ui 里不存在）。
///
/// ```dart
/// FutureBuilder<AlbumDetail>(
///   builder: (context, snap) =>
///       snap.hasData ? _body(snap.data!) : const JmLoading(label: '正在加载作品…'),
/// )
/// ```
class JmLoading extends StatelessWidget {
  const JmLoading({super.key, this.label}) : _sliver = false;

  /// `CustomScrollView` 里的版本：`SliverFillRemaining(hasScrollBody: false)` 包一层。
  const JmLoading.sliver({super.key, this.label}) : _sliver = true;

  /// 转圈下面的说明文字，`null` 表示只有转圈。
  final String? label;

  final bool _sliver;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final body = _FillHeight(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ActivityIndicator.page(),
            if (label != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
    return _sliver
        ? SliverFillRemaining(hasScrollBody: false, child: body)
        : body;
  }
}

/// 空列表。
///
/// 插图用本应用自己的（相册 glyph），标题是 [message]，说明是 [hint]，
/// [actionLabel] + [onAction] 给一个引导动作（例如「去发现页看看」）。
///
/// ```dart
/// JmEmpty(
///   message: '还没有收藏',
///   hint: '在作品详情页点收藏，就会出现在这里。',
///   actionLabel: '去发现',
///   onAction: () => openDiscover(context),
/// )
/// ```
///
/// 什么时候别用：搜索无结果时不要用它——`NullStatusSwitcher(isSearching: true)`
/// 会用 prism 自带的「没有搜索结果」插图，那一条链路不需要自定义文案。
class JmEmpty extends StatelessWidget {
  const JmEmpty({
    super.key,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  }) : _sliver = false;

  /// `CustomScrollView` 里的版本。
  const JmEmpty.sliver({
    super.key,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  }) : _sliver = true;

  final String message;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  final bool _sliver;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = label == null
        ? null
        : FilledButton(onPressed: onAction, child: Text(label));
    final body = _FillHeight(
      child: NullStatus(
        label: message,
        description: hint,
        action: action,
        illustration: const _EmptyIllustration(),
      ),
    );
    return _sliver
        ? SliverFillRemaining(hasScrollBody: false, child: body)
        : body;
  }
}

/// 出错，可选重试。
///
/// 文案走 [message]（一般直接用 `error.toString()` 之前先剥掉异常前缀），
/// [onRetry] 非空时带一颗「重试」填充按钮。
///
/// ```dart
/// JmError(message: '网络连接失败', onRetry: () => setState(_future = _load()))
/// ```
///
/// 什么时候别用：局部失败（比如列表尾部「加载更多」失败）不要整页报错，
/// 在那一格放一行可点的文字即可；整页态只留给「什么都没有」的场合。
class JmError extends StatelessWidget {
  const JmError({super.key, required this.message, this.onRetry})
    : _sliver = false;

  /// `CustomScrollView` 里的版本。
  const JmError.sliver({super.key, required this.message, this.onRetry})
    : _sliver = true;

  final String message;
  final VoidCallback? onRetry;

  final bool _sliver;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    final body = _FillHeight(
      child: NullStatus(
        label: message,
        description: onRetry == null ? null : '请检查网络或稍后再试。',
        action: onRetry == null
            ? null
            : FilledButton(onPressed: onRetry, child: const Text('重试')),
        illustration: const _ErrorIllustration(),
      ),
    );
    return _sliver
        ? SliverFillRemaining(hasScrollBody: false, child: body)
        : body;
  }
}

/// 空态插图：prism_ui 只公开了 `Illustration.search` 一个插图，其余要自己实现
/// 这个接口（`glyph` + `isError`，见 prism_ui API 速查 §6.7）。
class _EmptyIllustration implements Illustration {
  const _EmptyIllustration();

  @override
  Glyph get glyph => AppGlyphs.photos;

  @override
  bool get isError => false;
}

/// 错误态插图：`isError = true` 让插图整体用 `ColorScheme.error` 上色。
class _ErrorIllustration implements Illustration {
  const _ErrorIllustration();

  @override
  Glyph get glyph => AppGlyphs.warning;

  @override
  bool get isError => true;
}

/// 有界高度时撑满父级（让 `Center` / `NullStatus` 能垂直居中），
/// 无界高度（ListView / Column）时按内容自适应，不抛异常。
class _FillHeight extends StatelessWidget {
  const _FillHeight({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return child;
        }
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        );
      },
    );
  }
}
