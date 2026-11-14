import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

/// 主框架：Material 3 底部导航 + 各页面保留自身状态。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;


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

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.select<AppState, bool>((app) => app.loggedIn);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          for (var i = 0; i < _pages.length; i++)
            _built[i] ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: <Widget>[
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: '书库',
          ),
          // 第三页：未登录时叫「登录」，登录后叫「我的」。
          NavigationDestination(
            icon: Icon(loggedIn ? Icons.person : Icons.login_outlined),
            selectedIcon: Icon(loggedIn ? Icons.person : Icons.login),
            label: loggedIn ? '我的' : '登录',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
