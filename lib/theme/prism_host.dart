import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'prism_theme.dart';

/// prism_ui 组件自己会用到的文案。
///
/// `showSheet` / `showFloatingDialog` / `Scaffold` 的返回按钮 / `ContextMenuRegion`
/// 都会调 `UiLocalizations.of(context)`，而它在缺省会直接 assert 失败
/// （`packages/prism_ui/lib/l10n.dart:11`）。所以必须在 App 上注册这个 delegate。
///
/// 应用目前只有中文界面，所以固定返回中文；以后要多语言时，把这里换成
/// 从 ARB 生成的查找表即可。
class JmUiLocalizations extends UiLocalizations {
  JmUiLocalizations();

  static const LocalizationsDelegate<UiLocalizations> delegate =
      _JmUiLocalizationsDelegate();

  @override
  String get back => '返回';

  @override
  String get cancel => '取消';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get close => '关闭';

  @override
  String get copy => '复制';

  @override
  String get cut => '剪切';

  @override
  String get dialog => '对话框';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get more => '更多';

  @override
  String get noSearchResults => '没有搜索结果';

  @override
  String get paste => '粘贴';

  @override
  String get reset => '重置';

  @override
  String get select => '选择';

  @override
  String get search => '搜索';

  @override
  String get selectAll => '全选';

  @override
  String get showLess => '收起';

  @override
  String get showMore => '展开';

  @override
  String get showPassword => '显示密码';

  @override
  String get sort => '排序';

  @override
  String get submit => '确定';
}

/// PrismApp 自己会建 Theme / MeasureScope / BannerHost，但**不**建 ViewScope
/// （`packages/prism_ui/lib/view_scope.dart:25` 缺了会 assert 崩）。
/// 这一层补上它，作为 `PrismApp.home` 的包装。
class JmViewScope extends StatelessWidget {
  const JmViewScope({super.key, required this.child});

  final Widget child;

  /// 宽度超过这个逻辑像素就切到桌面布局（和迁移期 PrismHost 的断点一致）。
  static const double desktopBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? constraints.biggest
            : MediaQuery.sizeOf(context);
        return ViewScope(
          size: size,
          isMobile: size.width < desktopBreakpoint,
          windowControls: Size.zero,
          child: child,
        );
      },
    );
  }
}

class _JmUiLocalizationsDelegate
    extends LocalizationsDelegate<UiLocalizations> {
  const _JmUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<UiLocalizations> load(Locale locale) =>
      SynchronousFuture<UiLocalizations>(JmUiLocalizations());

  @override
  bool shouldReload(_JmUiLocalizationsDelegate old) => false;
}

/// prism 组件需要的运行环境。
///
/// 说明：最终形态是整个 App 都跑在 `PrismApp` 里（它自带 Theme / MeasureScope /
/// BannerHost）。迁移期还不能这么做——旧页面仍然是 Material 组件，脱离
/// `MaterialApp` 会因为没有 `Material` 祖先而崩。所以这一层在迁移阶段塞进
/// `MaterialApp.builder` 里，等所有页面都搬完，再把根换成 `PrismApp` 并删掉它。
///
/// 它补齐 prism 组件**必需但不会被自动提供**的三样东西：
/// 1. [ViewScope]：`AppBar` / `ScaffoldBar` / `showSheet` 都会读它，
///    缺了直接 assert 崩（`packages/prism_ui/lib/view_scope.dart:25`）。
/// 2. [MeasureScope]：`AppBar` / `ListRow` / `ListHeader` 的高度计算依赖它
///    （`packages/prism_ui/lib/measure.dart:99`）。
/// 3. [BannerHost]：它就是 prism 的 Toast/SnackBar 替代品。
class PrismHost extends StatelessWidget {
  const PrismHost({super.key, required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  /// 宽度超过这个逻辑像素就切到桌面布局。
  static const double _desktopBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    // PrismApp 内部也是这么取缩放比的：系统缩放因子，而不是 MediaQuery 的
    // 非线性 TextScaler，因为 Measure 只接受一个线性倍数。
    final factor = WidgetsBinding.instance.platformDispatcher.textScaleFactor;
    // Measure 构造时会读 Localizations.localeOf，必须在 Localizations 之下建。
    final measure = Measure.of(context, factor);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? constraints.biggest
            : MediaQuery.sizeOf(context);
        return ViewScope(
          size: size,
          isMobile: size.width < _desktopBreakpoint,
          child: MeasureScope(
            measure: measure,
            child: Theme(
              data: PrismTheme.of(brightness),
              // 内容默认坐落于 page 层级；卡片 / 块 / 内嵌由组件自己向下取一层。
              child: SurfaceScope(
                level: SurfaceLevel.page,
                child: BannerHost(
                  stacked: false,
                  topInset: 0,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
