import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

/// 主框架：手机宽度是浮动的 [NavigationDock]，桌面宽度是 [NavigationSidebar]，
/// 四个页面各自保留自己的状态。
///
/// 表现层从 `M3ENavigationBar`（Material 3 Expressive）换成了 prism_ui，但
/// **懒构建**与**状态保活**的语义原样保留（见 [_built]）：这只换了导航的壳，
/// 页面的加载时机、请求数量、页签状态都没变。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  /// 桌面侧栏是否展开：`NavigationSidebar.onToggle` 就地展开/收起它。
  ///
  /// 只在会话内保存（FlClash 把这一位存在设置里）。RootShell 现在没有合适的
  /// 持久化落点，等设置页接管侧栏偏好时再搬过去；不影响页签切换的任何行为。
  bool _sidebarExpanded = true;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    LibraryScreen(),
    AccountScreen(),
    SettingsScreen(),
  ];

  /// 只有访问过的页签才真正构建。
  ///
  /// IndexedStack 会把所有 children 一次性 build：那样进主框架那一帧要同时
  /// 发起首页的 3 个请求、书库请求，以及设置页的缓存目录扫描，push 转场直接掉帧。
  final List<bool> _built = <bool>[true, false, false, false];

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _built[index] = true;
    });
  }

  /// 四个页签的图标与文案；第三页随登录态在「登录 / 我的」之间切换。
  ///
  /// 图标一律取 [AppGlyphs] 里的 glyph：prism_ui 没有图标字体，`Icons.*` 全部作废。
  List<({Glyph glyph, String label})> _tabs(bool loggedIn) {
    return <({Glyph glyph, String label})>[
      (glyph: AppGlyphs.dashboard, label: '发现'),
      (glyph: AppGlyphs.bookmarks, label: '书库'),
      // 未登录时这个页签进去就是登录表单本身，所以文案用「登录」。
      loggedIn
          ? (glyph: AppGlyphs.account, label: '我的')
          : (glyph: AppGlyphs.login, label: '登录'),
      (glyph: AppGlyphs.settings, label: '设置'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.select<AppState, bool>((app) => app.loggedIn);
    final tabs = _tabs(loggedIn);

    final body = IndexedStack(
      index: _index,
      children: <Widget>[
        for (var i = 0; i < _pages.length; i++)
          _built[i] ? _pages[i] : const SizedBox.shrink(),
      ],
    );

    final scheme = context.colorScheme;
    return Surface(
      // 页面底色：明度来自 SurfaceLevel，不写字面颜色。
      color: SurfaceLevel.page.colorOf(scheme),
      // `context.isMobileView` 读 ViewScope（迁移期由 PrismHost 提供，断点 720）。
      child: context.isMobileView
          ? _mobile(context, body, tabs)
          : _desktop(context, body, tabs, scheme),
    );
  }

  /// 手机：浮动 dock 压在 body 上，body 用 [BottomInsetScope] 让出它的高度。
  Widget _mobile(
    BuildContext context,
    Widget body,
    List<({Glyph glyph, String label})> tabs,
  ) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          // dock 自身的底部安全区已经算进 insetOf，所以这里把 body 的
          // MediaQuery 底部内边距去掉，避免让开两次。页面统一用
          // `context.bottomInset` 取这个高度，不写死数字。
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: BottomInsetScope(
              inset: NavigationDock.insetOf(context),
              child: body,
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: NavigationDock(
            destinations: <NavigationDockDestination>[
              for (final tab in tabs)
                NavigationDockDestination(glyph: tab.glyph, label: tab.label),
            ],
            selectedIndex: _index,
            onSelected: _select,
          ),
        ),
      ],
    );
  }

  /// 桌面：窗口左侧的 chrome 侧栏 + 内容区。
  Widget _desktop(
    BuildContext context,
    Widget body,
    List<({Glyph glyph, String label})> tabs,
    ColorScheme scheme,
  ) {
    return Row(
      children: <Widget>[
        Surface(
          // 侧栏是窗口 chrome：用 chromeSurface 和内容区（page）区分层次。
          color: scheme.chromeSurface,
          shape: BorderDirectional(end: Divider.createBorderSide(context)),
          child: NavigationSidebar(
            destinations: <SidebarDestination>[
              for (final tab in tabs)
                SidebarDestination(glyph: tab.glyph, label: tab.label),
            ],
            selectedIndex: _index,
            expanded: _sidebarExpanded,
            onSelected: _select,
            // 传了 onToggle 就是「就地展开」，不传则侧栏收成一条、展开时改开浮层。
            onToggle: _toggleSidebar,
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  void _toggleSidebar() => setState(() => _sidebarExpanded = !_sidebarExpanded);
}
