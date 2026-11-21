import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/gateway_client.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/states.dart';
import 'root_shell.dart';

/// 起始页：四条线路竖向排列，进入页面自动并发测速，最快线路高亮标注。
///
/// 表现层换成 prism_ui，**状态机一个字都没改**（`jm_ui_inventory.md` R6）：
///
/// * 测速仍然由 `AppState.refreshLines()` 驱动，它在**每条线路完成时**
///   `notifyListeners`；本页用 `context.watch<AppState>()` 整页重建，所以每完成
///   一条就立刻多一行有延迟数字 —— 没有本地 `Future.wait` 聚合，也没有本地缓存
///   的快照，渐进更新靠的就是「谁变谁重建」。
/// * `_enteringHost` 仍然是唯一防重复进入的闸门：置位期间其它卡片 `onPressed` 为
///   null（prism 的禁用表达），自己那张显示转圈 +「正在进入…」。
/// * `selectLine` 成功且 `app.ready` 为真才 `pushReplacement` 进 [RootShell]；
///   失败只复位闸门，不跳转。
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    // 首帧之后再发起测速，保证 loading 态能立刻渲染出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshLines();
    });
  }

  /// 正在进入的线路（非空时其他按钮禁用）。
  String? _enteringHost;

  Future<void> _enter(String host) async {
    if (_enteringHost != null) return;
    // `switchHost` 需要一次网络往返，先立刻给反馈，否则点上去像卡住。
    setState(() => _enteringHost = host);

    final app = context.read<AppState>();
    await app.selectLine(host);
    if (!mounted) return;

    if (!app.ready) {
      setState(() => _enteringHost = null);
      return;
    }
    Navigator.of(context).pushReplacement(
      CardPageRoute<void>(builder: (_) => const RootShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 整页 watch：`refreshLines` 每完成一条线路就 notify 一次，页面跟着重建，
    // 于是第一条测完就有第一条的延迟数字（渐进更新）。
    final app = context.watch<AppState>();
    final scheme = context.colorScheme;

    return JmPage(
      // 起始页没有 bar 标题（品牌区在 body 里），也不需要返回。
      title: null,
      showBack: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Column 不像 ListView 那样会自动消费顶栏的 MediaQuery.padding.top，
          // 必须显式让开浮动顶栏，否则「选择线路」会贴到状态栏上被遮挡。
          SizedBox(height: context.appBarInset),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '选择线路',
                  style: AppTextStyle.largeTitle.of(context, emphasized: true),
                ),
                const SizedBox(height: 8),
                Text(
                  app.probing ? '正在自动测速…' : '测速完成，已标注最快线路',
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(child: _lines(app)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: app.probing || _enteringHost != null
                  ? null
                  : app.refreshLines,
              icon: app.probing
                  ? const ActivityIndicator(size: 18)
                  : const GlyphIcon(AppGlyphs.speed, size: 20),
              label: Text(app.probing ? '测速中…' : '重新测速'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lines(AppState app) {
    // 整页错误态只留给「连线路清单都没拿到」。
    final error = app.error;
    if (error != null && app.lines.isEmpty) {
      return JmError(message: error, onRetry: app.refreshLines);
    }

    final fastest = app.fastestHost;
    final lines = app.lines;
    // 清单还没回来时先摆 4 条占位，避免「空页 → 突然冒出四张卡」的跳变。
    final placeholder = lines.isEmpty;
    final count = placeholder ? AppState.lineCount : lines.length;

    return PrismListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gap: 12,
      itemCount: count,
      itemBuilder: (context, index) {
        if (placeholder) return const _LineSkeleton();
        final host = lines[index];
        final probe = app.probes[host] ?? LineProbe(host: host);
        return _LineCard(
          index: index,
          probe: probe,
          // 最快只在测速结束后标注（测速中每来一条都会变，标了会跳）。
          isFastest: !app.probing && host == fastest,
          // 「选中」= 用户点下去、正在进入的那条：保留卡片本身填充，只在行尾打勾。
          // 用 `_enteringHost` 而不是 `app.selectedHost`：`selectLine` 失败时
          // `selectedHost` 已经被写进去了（`AppState` 的事，不改），拿它画勾会出现
          // 「明明没进去却打了勾」。
          isSelected: _enteringHost == host,
          entering: _enteringHost == host,
          blocked: _enteringHost != null && _enteringHost != host,
          onPressed: () => _enter(host),
        );
      },
    );
  }
}

/// 单条线路卡：序号 / 线路域名 / 测速结果，最快的一条带「最快」标记。
///
/// 选中态按规范是「保留本身填充 + 打勾」（`SelectionBadge`），**不是**用 primary
/// 把整张卡填满；状态色（成功 / 警告 / 失败）只上文字和图标。
class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.index,
    required this.probe,
    required this.isFastest,
    required this.isSelected,
    required this.onPressed,
    this.entering = false,
    this.blocked = false,
  });

  final int index;
  final LineProbe probe;
  final bool isFastest;

  /// 用户点下去、正在进入的那条：行尾打勾（保留卡片本身填充）。
  final bool isSelected;

  /// 正在进入这条线路（显示转圈 + 「正在进入…」）。
  final bool entering;

  /// 正在进入其它线路，这条暂时不可点（prism 的禁用 = 38% 淡出）。
  final bool blocked;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final failed = probe.error != null;
    final status = entering ? '正在进入…' : _statusText();
    // FlClash 的 `delayColor` 语义：< 600ms 成功、≥ 600ms 警告、失败 error。
    final statusColor = entering || probe.pending
        ? scheme.onSurfaceVariant
        : failed
        ? scheme.delayColor(-1)!
        : scheme.delayColor(probe.latencyMs) ?? scheme.onSurfaceVariant;

    final Widget trailing;
    if (isSelected) {
      // 选中 = 保留本身填充 + 打勾（不是把整张卡染成 primary）。
      trailing = const SelectionBadge();
    } else if (probe.pending) {
      trailing = const ActivityIndicator(size: 18);
    } else if (failed) {
      trailing = GlyphIcon(AppGlyphs.error, size: 20, color: scheme.error);
    } else {
      trailing = GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: scheme.onSurfaceVariant,
      );
    }

    return Card(
      onPressed: blocked ? null : onPressed,
      isSelected: isSelected,
      radius: AppCorner.lg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          _LineIndexBadge(
            index: index,
            isFastest: isFastest,
            entering: entering,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        probe.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    if (isFastest) ...<Widget>[
                      const SizedBox(width: 8),
                      // 状态色只上小 chip，不染整张卡。
                      TonalChip(
                        label: '最快',
                        color: scheme.successContainer,
                        foregroundColor: scheme.onSuccessContainer,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    status,
                    key: ValueKey<String>(status),
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  String _statusText() {
    if (probe.pending) return '测速中…';
    final error = probe.error;
    if (error != null) return error;
    final kb = probe.kbPerSecond;
    final speed = kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB/s'
        : '${kb.toStringAsFixed(0)} KB/s';
    return '${probe.latencyMs} ms · $speed';
  }
}

/// 线路序号：圆形底 + 序号；最快的那条换成闪电 glyph（状态色只上图标）；
/// 正在进入的那条换成转圈（行尾留给选中勾）。
class _LineIndexBadge extends StatelessWidget {
  const _LineIndexBadge({
    required this.index,
    required this.isFastest,
    this.entering = false,
  });

  final int index;
  final bool isFastest;
  final bool entering;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return SizedBox.square(
      dimension: _size,
      child: DecoratedBox(
        // 卡片里的下一级表面（block），和卡片本身分得开。
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(scheme),
          shape: AppShape.circle,
        ),
        child: Center(
          child: entering
              ? const ActivityIndicator(size: 18)
              : isFastest
              ? GlyphIcon(AppGlyphs.bolt, size: 20, color: scheme.success)
              : Text(
                  '${index + 1}',
                  style: AppTextStyle.footnote.of(context, emphasized: true)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
        ),
      ),
    );
  }
}

/// 线路清单加载中的占位卡（清单还没回来时摆 4 条）。
class _LineSkeleton extends StatelessWidget {
  const _LineSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      inert: true,
      radius: AppCorner.lg,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          ActivityIndicator(size: 18),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonPill(width: 132, height: 14),
                SizedBox(height: 6),
                SkeletonPill(width: 88, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// FlClash 的延迟配色（`lib/ui/delay_color.dart`）语义。
///
/// prism_ui 没有导出这个扩展，而迁移边界不允许改 `packages/prism_ui/**` 或
/// `lib/ui/**`，所以按同样的阈值就地定义一份：
///
/// | 延迟 | 颜色 |
/// |---|---|
/// | `null`（还没测） | `null`（调用方自己决定） |
/// | `< 0`（失败） | `ColorScheme.error` |
/// | `< 600ms` | `ColorScheme.success` |
/// | `≥ 600ms` | `ColorScheme.warning` |
extension _DelayColorScheme on ColorScheme {
  Color? delayColor(int? delay) {
    if (delay == null) return null;
    if (delay < 0) return error;
    if (delay < 600) return success;
    return warning;
  }
}
