import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
// ViewScope 不在 prism_ui 的 barrel 里，单独引。
import 'package:prism_ui/view_scope.dart' show ViewScope;

import 'package:flutterjm/theme/prism_host.dart';
import 'package:flutterjm/theme/prism_theme.dart';

/// 回归测试：`ViewScope` 必须包住整个 Navigator，而不是只包 home。
///
/// 真机上的崩溃是：
///   `No ViewScope found above RootShell`
/// 原因：`JmViewScope` 曾经写在 `PrismApp.home` 里，而起始页用
/// `pushReplacement` 进入 `RootShell` —— 新路由不在 home 的子树下，拿不到
/// ViewScope。修法是把 `JmViewScope` 放进 `PrismApp.builder`。
///
/// 这个测试复现「pushReplacement 之后的新页面仍要能读到 ViewScope」，
/// 防止有人再把包装挪回 home。

/// 需要 ViewScope 的页面（模拟 RootShell 读 `context.isMobileView`）。
class _NeedsViewScope extends StatelessWidget {
  const _NeedsViewScope();

  @override
  Widget build(BuildContext context) {
    // 这两行都会 assert scope != null。
    final isMobile = context.isMobileView;
    final size = ViewScope.sizeOf(context);
    return Text('mobile=$isMobile size=${size.width.toInt()}');
  }
}

/// 首帧后 pushReplacement 到 [_NeedsViewScope]，模拟起始页 → RootShell。
class _ReplacingHome extends StatefulWidget {
  const _ReplacingHome();

  @override
  State<_ReplacingHome> createState() => _ReplacingHomeState();
}

class _ReplacingHomeState extends State<_ReplacingHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        prism.CardPageRoute<void>(
          settings: const RouteSettings(name: '/root'),
          builder: (_) => const _NeedsViewScope(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _app() => prism.PrismApp(
  theme: PrismTheme.light(),
  darkTheme: PrismTheme.dark(),
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    JmUiLocalizations.delegate,
  ],
  builder: (context, navigator) =>
      JmViewScope(child: navigator ?? const SizedBox.shrink()),
  home: const _ReplacingHome(),
);

void main() {
  testWidgets('pushReplacement 出来的页面仍能读到 ViewScope', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    // 第一帧：home 被替换。
    await tester.pump();
    // 转场。
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('mobile=true size=390'), findsOneWidget);
  });
}
