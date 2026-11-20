/// 主题模式（领域枚举）。
///
/// 为什么不用 UI 库的 `ThemeMode`：Material 和 prism_ui 各导出一个**同名但不同型**
/// 的 `ThemeMode`，状态层、持久化层和页面都不该绑死在其中一个实现上。
/// 所以领域层自己定义一份，只有应用根（`lib/main.dart`）负责把它映射成具体
/// UI 库要求的枚举；设置页直接用这个枚举，页面里不会出现任何 Material 类型。
enum JmThemeMode {
  system,
  light,
  dark;

  /// 持久化用的字符串。
  String get storageName => switch (this) {
    JmThemeMode.system => 'system',
    JmThemeMode.light => 'light',
    JmThemeMode.dark => 'dark',
  };

  static JmThemeMode fromStorage(Object? value) => switch (value) {
    'light' => JmThemeMode.light,
    'dark' => JmThemeMode.dark,
    _ => JmThemeMode.system,
  };

  /// 界面上的中文标签。
  String get label => switch (this) {
    JmThemeMode.system => '跟随系统',
    JmThemeMode.light => '浅色',
    JmThemeMode.dark => '深色',
  };
}
