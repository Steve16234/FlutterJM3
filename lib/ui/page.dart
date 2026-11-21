import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';
import 'top_bar.dart';

export 'top_bar.dart' show JmBarAction;

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
///       actions: <JmBarAction>[
///         JmBarAction(
///           glyph: AppGlyphs.refresh,
///           tooltip: '刷新',
///           onPressed: () => reload(),
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
    this.showBar = true,
    this.actions = const <JmBarAction>[],
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

  /// 是否显示默认顶栏。首页把搜索 / 刷新 / 日历做成自己那一行玻璃控件时传 false，
  /// 只留一条 0 高度的占位 bar 给 [PrismScaffold] 拿页面底色 / 键盘让位。
  final bool showBar;

  /// bar 右侧的动作。页面只描述 glyph / 提示 / 回调，由 [JmTopBar]
  /// 统一包成 [LiquidGlassIconButton]（iOS 26 原生玻璃，其他平台磨砂回落）。
  final List<JmBarAction> actions;

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
      bar: showBar
          ? (context.isInCompactSheet
              ? ScaffoldBar(
                  isCompact: true,
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
                    // sheet 里保持 prism 原生动作按钮（sheet bar 有自己的紧凑规范）。
                    actions: <Widget>[
                      for (final action in actions)
                        AppBarActionButton(
                          data: IconButtonData(
                            glyph: action.glyph,
                            tooltip: action.tooltip,
                            onPressed: action.onPressed,
                          ),
                        ),
                    ],
                  ),
                )
              : JmTopBar(
                  title: title,
                  showBack: canPop,
                  actions: actions,
                  loading: loading ?? _idle,
                  onBack: () => Navigator.maybePop(context),
                  backLabel: _backLabel(context),
                ))
          : const _EmptyBar(),
      headerBuilder: bottom == null ? null : (_) => bottom,
      body: _BodyInset(child: body ?? const SizedBox.shrink()),
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

/// 不垫物理 Padding，让 body 从屏幕顶端铺满。
///
/// `PrismScaffold` 会把 bar 高度写进 body 的 `MediaQuery.padding.top`：
/// - 首屏：`ListView(padding: …)` / `CustomScrollView` 会消费它，内容从
///   bar 下方开始，不被遮住；
/// - 滚动：内容从 bar **背后**滑过，配合顶栏的溶解渐变就没有硬切线。
///   液态玻璃需要身后有内容滚过才会实时折射，所以这里绝不能垫物理 padding。
class _BodyInset extends StatelessWidget {
  const _BodyInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 0 高度的占位 bar：[JmPage.showBar] 为 false 时用它替掉真正顶栏。
///
/// [PrismScaffold] 需要一条 bar 来铺设页面底色、键盘让位与 body 的
/// MediaQuery；给一条 0 高度占位就能既去掉可见顶栏，又保留这些语义。
class _EmptyBar extends StatelessWidget implements PreferredSizeWidget {
  const _EmptyBar();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
