import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';

/// 每个页面的统一骨架：一条 bar + 一块 body。
///
/// 内部只用 prism 的三件套（`PrismScaffold` + `ScaffoldBar` + `AppBar`），
/// 刻意保持很薄：动作直接进 `AppBar.actions`，超过 3 个要自己收敛
/// （图标按钮 → `PopupAnchor` 溢出菜单）。
///
/// ```dart
/// class SettingsPage extends StatelessWidget {
///   const SettingsPage({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return JmPage(
///       title: '设置',
///       actions: <Widget>[
///         AppBarActionButton(
///           data: IconButtonData(
///             glyph: AppGlyphs.refresh,
///             tooltip: '刷新',
///             onPressed: () => reload(),
///           ),
///         ),
///       ],
///       body: ListView(
///         padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
///         children: <Widget>[
///           const SectionHeader(title: '外观'),
///           SectionCard(children: <Widget>[
///             SettingRow(title: '主题', subtitle: '跟随系统'),
///           ]),
///         ],
///       ),
///     );
///   }
/// }
/// ```
///
/// 什么时候别用：sheet / dialog / 带底栏的主框架（`RootShell` 那种）需要自己的
/// 布局，直接写 `PrismScaffold`；阅读器那种全屏沉浸页也不用它（bar 要自己浮动）。
class JmPage extends StatelessWidget {
  const JmPage({
    super.key,
    this.title,
    this.showBack = true,
    this.actions = const <Widget>[],
    this.bottom,
    this.body,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.loading,
    this.foot,
  });

  /// bar 的标题；`null` 表示这条 bar 不显示标题（阅读器、起始页的那种）。
  final String? title;

  /// 有上级页面时显示返回按钮。只有当 `Navigator` 真的能 pop 时才画，
  /// 所以根页面传 `true` 也不会多出一个按了没反应的箭头。
  final bool showBack;

  /// bar 右侧的动作。约定 2~3 个，用 `AppBarActionButton` +
  /// `IconButtonData(glyph: …)` 构造，这样以后换溢出菜单不用改页面。
  final List<Widget> actions;

  /// 贴在 bar 正下方、body 之上的整条内容（搜索框、tab 条、关键词条）。
  /// 给了它之后 body 不再钻到这条内容下面，但仍从 bar 下面开始。
  final Widget? bottom;

  /// 页面主体。自己决定滚动容器（`ListView` / `CustomScrollView` / `Column`）。
  final Widget? body;

  /// 默认走 `SurfaceLevel.page`（`ThemeData.scaffoldBackgroundColor`）。
  final Color? backgroundColor;

  /// 键盘弹起时是否把 body 缩上去；`null` = prism 的默认（跟 Material 一样为 true）。
  final bool? resizeToAvoidBottomInset;

  /// bar 底部那条 3dp 进度条（prism 的 `LoadingBar`），用来表示「正在刷新」。
  final ValueListenable<bool>? loading;

  /// body 之上悬浮的东西（底部操作条 / 导航 dock）。
  ///
  /// 它不占 body 的空间：要避免内容被盖住，自己在 body 末尾留出等高的空白
  /// （或把 body 包进 `BottomInsetScope`）。
  final Widget? foot;

  /// 没传 [loading] 时用的常量监听，避免每次 build 造一个 `ValueNotifier`。
  static final ValueListenable<bool> _idle = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final actions = this.actions;
    final bottom = this.bottom;
    final canPop =
        showBack && (Navigator.maybeOf(context)?.canPop() ?? false);
    return PrismScaffold(
      bar: ScaffoldBar(
        // 只有 sheet 里才是紧凑 bar；页面永远是 72dp 的常规 bar。
        isCompact: context.isInCompactSheet,
        // 标题/动作都是本 widget 的字段，随 JmPage 重建即可，不需要额外监听。
        listenable: Listenable.merge(const <Listenable>[]),
        loading: loading ?? _idle,
        builder: (context) => AppBar(
          leading: canPop
              ? ElasticPress(
                  child: AppBarActionButton(
                    data: IconButtonData(
                      glyph: Glyphs.arrowBack,
                      tooltip: _backLabel(context),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                )
              : null,
          title: title == null ? null : Text(title),
          actions: <Widget>[
            ...actions,
            // 右侧留出与 bar 左边距一致的呼吸位，页面不用自己补。
            if (actions.isNotEmpty) const SizedBox(width: appBarActionSpace),
          ],
        ),
      ),
      headerBuilder: bottom == null ? null : (_) => bottom,
      body: _BodyInset(
        hasHeader: bottom != null,
        child: body ?? const SizedBox.shrink(),
      ),
      foot: foot,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }

  /// 返回按钮的提示文案：拿得到 prism 的本地化就用它（应用里已注册
  /// `JmUiLocalizations`），拿不到就退回中文，不让一个 tooltip 把页面 assert 掉。
  static String _backLabel(BuildContext context) =>
      Localizations.of<UiLocalizations>(context, UiLocalizations)?.back ?? '返回';
}

/// 把 bar 占掉的高度真正让出来。
///
/// `PrismScaffold` 的 bar 是**浮在 body 之上**的，它只把「bar 有多高」写进 body 的
/// `MediaQuery.padding.top`，指望 body 自己消费。问题是只有「不给 padding 的
/// 可滚动组件」才会自动消费它——`ListView(padding: …)` / `CustomScrollView` 里的
/// `SliverPadding` / 裸 `Column` 都会把这段忽略掉，于是首屏内容被压在 bar 底下。
///
/// 这里改成显式让位：先按当前 MediaQuery 的 top padding 垫一层，再把这段从
/// MediaQuery 里去掉，保证里面再怎么建滚动容器都不会重复计一次。
/// 有 [JmPage.bottom]（条状内容）时 prism 已经把这段去掉了，这里拿到的是 0，不会叠加。
class _BodyInset extends StatelessWidget {
  const _BodyInset({required this.hasHeader, required this.child});

  final bool hasHeader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    if (hasHeader || inset <= 0) {
      return child;
    }
    return Padding(
      padding: EdgeInsets.only(top: inset),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: child,
      ),
    );
  }
}
