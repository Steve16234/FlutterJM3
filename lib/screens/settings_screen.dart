import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/page_cache.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 设置页：主题、线路切换、缓存管理、运行信息。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CacheUsage? _usage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final usage = await PageCache.instance.usage();
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  Future<void> _clearCache() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将删除已缓存的页图和章节列表，清理后再进入需要重新下载。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final app = context.read<AppState>();

    await PageCache.instance.clear();
    app.chapters.clear();
    await _refreshUsage();

    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(const SnackBar(content: Text('缓存已清理')));
  }

  String get _usageSubtitle {
    final usage = _usage;
    if (usage == null) return '统计中…';
    if (usage.totalBytes == 0) return '暂无缓存';
    return '磁盘 ${_formatBytes(usage.diskBytes)} · '
        '内存 ${_formatBytes(usage.memoryBytes)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: M3EAppBar.top(titleText: '设置'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          const SectionHeader(title: '外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('跟随系统'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('浅色'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('深色'),
                ),
              ],
              selected: <ThemeMode>{app.themeMode},
              onSelectionChanged: (selection) =>
                  app.setThemeMode(selection.first),
            ),
          ),
          const SectionHeader(title: '线路'),
          if (app.baseUrl != null)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('当前线路'),
              subtitle: Text(
                app.baseUrl!.replaceAll('https://', '').replaceAll('/', ''),
              ),
            ),
          if (app.client.hosts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: app.client.hosts.map((host) {
                  final isCurrent =
                      app.baseUrl != null && app.baseUrl!.contains(host);
                  return ChoiceChip(
                    label: Text(host),
                    selected: isCurrent,
                    onSelected: (_) async {
                      await app.switchHost(host);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已切换到 $host')),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          const SectionHeader(title: '缓存'),
          ListTile(
            leading: const Icon(Icons.cached_outlined),
            title: const Text('页图缓存'),
            subtitle: Text(_usageSubtitle),
            onTap: _busy ? null : _refreshUsage,
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _clearCache,
                    child: const Text('清理'),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '看过的页会缓存在本地，退出阅读器或重启 App 后再进入无需重新下载。',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('图片 CDN'),
            subtitle: Text(app.imgHost),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('渲染引擎'),
            subtitle: Text(
              'Flutter · Material 3 · 预测式返回动画',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: Icon(Icons.warning_amber_outlined, color: scheme.error),
            title: const Text('内容声明'),
            subtitle: Text(
              '本应用仅用于技术演示，数据来自第三方公开网关，'
              '内容版权归原作者所有。',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}
