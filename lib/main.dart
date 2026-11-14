import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/page_cache.dart';
import 'screens/start_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

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
      // 只监听主题字段：线路测速、搜索历史等状态变更不该重建整个 MaterialApp。
      child: Selector<AppState, ThemeMode>(
        selector: (_, app) => app.themeMode,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'JM',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(null),
            darkTheme: AppTheme.dark(null),
            themeMode: themeMode,
            // 起始页：四条线路自动测速，选线路后进入主框架。
            home: const StartScreen(),
          );
        },
      ),
    );
  }
}

