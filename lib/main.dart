import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
// PrismApp 与 MaterialApp 是两套应用根；prism 自带 ThemeMode / ThemeData，
// 用前缀导入避免和我们的领域枚举 JmThemeMode 混淆。
import 'package:prism_ui/prism_ui.dart' as prism;

import 'core/page_cache.dart';
import 'core/theme_mode.dart';
import 'screens/start_screen.dart';
import 'state/app_state.dart';
import 'theme/prism_host.dart';
import 'theme/prism_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热磁盘缓存目录，省掉第一次进阅读器时的初始化开销。
  unawaited(PageCache.instance.warmUp());
  runApp(const FlutterJMApp());
}

class FlutterJMApp extends StatelessWidget {
  const FlutterJMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) {
        final app = AppState();
        // 读回主题 / 搜索历史等已保存的设置。
        unawaited(app.restoreSettings());
        return app;
      },
      // 只监听影响应用根的两项（主题 + 液态玻璃）：线路测速、搜索历史等
      // 状态变更不该重建整个应用。
      child: Selector<AppState, ({JmThemeMode theme, bool glass})>(
        selector: (_, app) => (theme: app.themeMode, glass: app.liquidGlass),
        builder: (context, settings, _) {
          final themeMode = settings.theme;
          return prism.PrismApp(
            title: 'JM',
            debugShowCheckedModeBanner: false,
            theme: PrismTheme.light(),
            darkTheme: PrismTheme.dark(),
            // 领域枚举 → prism 的 ThemeMode，只在这里映射一次。
            themeMode: switch (themeMode) {
              JmThemeMode.system => prism.ThemeMode.system,
              JmThemeMode.light => prism.ThemeMode.light,
              JmThemeMode.dark => prism.ThemeMode.dark,
            },
            // prism 的组件（sheet / dialog / 右键菜单 / 返回按钮）要从这里取文案。
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              JmUiLocalizations.delegate,
            ],
            // 液态玻璃（FlClash 的 Liquid Glass）：dock、bar 按钮、搜索框、
            // 弹窗菜单与 alert 都会用 shader 折射背后的内容。
            //
            // 由设置页的「低性能模式」控制：默认开启液态玻璃（ultra 档，
            // 完整色散 + 磨砂 + 折射）；不支持 shader / 耗电时打开低性能模式
            // 会把它关掉，liquidGlass 为 null 时整体退回普通填充方案。
            liquidGlass: settings.glass ? prism.LiquidGlassQuality.ultra : null,
            // PrismApp 自带 Theme / MeasureScope / BannerHost，只缺 ViewScope。
            //
            // JmViewScope 必须放在 builder 里包住整个 Navigator，**不能**放在
            // home 里：home 只是 Navigator 的第一个路由，被 pushReplacement /
            // push 出来的新页（例如起始页 → RootShell）是 Navigator 的兄弟路由，
            // 不在 home 的子树下，会报 `No ViewScope found above RootShell`。
            builder: (context, navigator) =>
                JmViewScope(child: navigator ?? const SizedBox.shrink()),
            home: const StartScreen(),
          );
        },
      ),
    );
  }
}
