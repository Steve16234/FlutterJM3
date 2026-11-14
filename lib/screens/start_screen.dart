import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/gateway_client.dart';
import '../state/app_state.dart';
import 'root_shell.dart';

/// 起始页：四条线路竖向排列，进入页面自动并发测速，最快线路高亮标注。
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
      MaterialPageRoute<void>(builder: (_) => const RootShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final fastest = app.fastestHost;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '选择线路',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.probing ? '正在自动测速…' : '测速完成，已标注最快线路',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: app.error != null && app.lines.isEmpty
                  ? _ErrorState(message: app.error!, onRetry: app.refreshLines)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: app.lines.isEmpty ? AppState.lineCount : app.lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (app.lines.isEmpty) {
                          return const _LineSkeleton();
                        }
                        final host = app.lines[index];
                        final probe = app.probes[host] ??
                            LineProbe(host: host);
                        return _LineButton(
                          index: index,
                          probe: probe,
                          isFastest: !app.probing && host == fastest,
                          entering: _enteringHost == host,
                          blocked: _enteringHost != null &&
                              _enteringHost != host,
                          onTap: () => _enter(host),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.tonalIcon(
                onPressed: app.probing || _enteringHost != null
                    ? null
                    : app.refreshLines,
                icon: app.probing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed),
                label: Text(app.probing ? '测速中…' : '重新测速'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条线路按钮：序号 + 线路域名 + 测速结果，最快的一条带「最快」徽标。
class _LineButton extends StatelessWidget {
  const _LineButton({
    required this.index,
    required this.probe,
    required this.isFastest,
    required this.onTap,
    this.entering = false,
    this.blocked = false,
  });

  final int index;
  final LineProbe probe;
  final bool isFastest;

  /// 正在进入这条线路（显示转圈 + 「正在进入…」）。
  final bool entering;

  /// 正在进入其它线路，这条暂时不可点。
  final bool blocked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = probe.error != null;
    final status = entering ? '正在进入…' : _statusText();

    final Color background;
    final Color border;
    if (isFastest) {
      background = scheme.primaryContainer;
      border = scheme.primary;
    } else if (failed) {
      background = scheme.surfaceContainerLow;
      border = scheme.outlineVariant;
    } else {
      background = scheme.surfaceContainerHigh;
      border = scheme.outlineVariant;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: border,
          width: isFastest ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: blocked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isFastest
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  child: isFastest
                      ? Icon(Icons.bolt, size: 20, color: scheme.onPrimary)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              probe.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (isFastest) ...<Widget>[
                            const SizedBox(width: 8),
                            _FastestBadge(scheme: scheme),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          status,
                          key: ValueKey<String>(status),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: failed
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (entering || probe.pending)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    failed ? Icons.error_outline : Icons.chevron_right,
                    color: failed ? scheme.error : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusText() {
    if (probe.pending) return '测速中…';
    if (probe.error != null) return probe.error!;
    final kb = probe.kbPerSecond;
    final speed = kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB/s'
        : '${kb.toStringAsFixed(0)} KB/s';
    return '${probe.latencyMs} ms · $speed';
  }
}

class _FastestBadge extends StatelessWidget {
  const _FastestBadge({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '最快',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

/// 线路清单加载中的骨架占位。
class _LineSkeleton extends StatelessWidget {
  const _LineSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
