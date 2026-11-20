import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/page_cache.dart';
import '../core/theme_mode.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/rows.dart';
import '../ui/section.dart';

/// 设置页：主题、线路切换、缓存管理、关于信息。
///
/// 表现层按 prism_ui（FlClash）的规范重写：`JmPage` 骨架 + `SectionHeader` /
/// `SectionCard` 的 inset grouped 分组 + `SettingRow` / `ValueRow` 行，
/// 主题三选一用 `SegmentedControl`（连体模式切换才允许实心 primary 填充）。
///
/// **数据流一点没动**（见 `docs/jm_ui_inventory.md` §2.5）：
/// * 进页面就 `PageCache.instance.usage()`，不等转场结束；
/// * 清理必须**同时**清 `PageCache` 与 `app.chapters`（只清一个会让阅读器拿到
///   旧章节列表但图片全丢）；
/// * 切主题立即经 `AppState.setThemeMode` 持久化；换线路走 `AppState.switchHost`。
/// 提示从 `SnackBar` 换成了 prism 的 `BannerHost`，文案不变。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// 版本号：与 `pubspec.yaml` 的 `version:` 逐字一致。
  ///
  /// 项目没有 `package_info_plus` 依赖（加依赖超出本页范围），所以这里只能
  /// 写常量；改版本号时两处一起改。见交付说明「需要补进套件」。
  static const String _appVersion = '1.0.0+1';

  CacheUsage? _usage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  /// 重新统计缓存占用（行点击与清理后各走一次，和旧实现一致）。
  Future<void> _refreshUsage() async {
    final usage = await PageCache.instance.usage();
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  Future<void> _clearCache() async {
    if (_busy) return;
    // 提示条宿主在 await 之后可能已经拿不到了（路由/页面可能已销毁），先握住。
    final banners = BannerHost.maybeOf(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: '清理缓存',
        // 最后一个动作是默认动作（primary 填充），第一个是取消。
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
        child: const Text('将删除已缓存的页图和章节列表，清理后再进入需要重新下载。'),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final app = context.read<AppState>();

    await PageCache.instance.clear();
    app.chapters.clear();
    await _refreshUsage();

    if (!mounted) return;
    setState(() => _busy = false);
    banners?.show('缓存已清理', level: BannerLevel.success);
  }

  /// 换线路：先切网关，再提示（顺序与旧实现一致）。
  Future<void> _switchHost(String host) async {
    final app = context.read<AppState>();
    final banners = BannerHost.maybeOf(context);
    await app.switchHost(host);
    if (!mounted) return;
    banners?.show('已切换到 $host');
  }

  /// 缓存占用的副标题：统计中 / 暂无缓存 / 「磁盘 · 内存」。
  String get _usageSubtitle {
    final usage = _usage;
    if (usage == null) return '统计中…';
    if (usage.totalBytes == 0) return '暂无缓存';
    return '磁盘 ${_formatBytes(usage.diskBytes)} · '
        '内存 ${_formatBytes(usage.memoryBytes)}';
  }

  /// 当前线路：去掉协议与结尾斜杠（旧页面的显示口径）。
  String _lineLabel(String? baseUrl) {
    if (baseUrl == null) return '尚未连接';
    return baseUrl.replaceAll('https://', '').replaceAll('/', '');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final hosts = app.client.hosts;
    final baseUrl = app.baseUrl;

    return JmPage(
      title: '设置',
      // 一级页面（底部导航的第四个页签），没有上级页面可返回。
      showBack: false,
      body: ListView(
        // 顶部留白交给 JmPage；底部让开浮动 dock（不写死数字）。
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + context.bottomInset),
        children: <Widget>[
          const SectionHeader(title: '外观'),
          SectionCard(
            children: <Widget>[
              SettingRow(
                glyph: AppGlyphs.palette,
                title: '主题',
                subtitle: app.themeMode.label,
              ),
              // 模式切换：连体选择组，选中项实心 primary（规范允许的唯一实心填充场景）。
              // 标签与顺序都来自领域枚举自身（跟随系统 / 浅色 / 深色，与旧页面一致）。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedControl<JmThemeMode>(
                  segments: <(JmThemeMode, String)>[
                    for (final mode in JmThemeMode.values) (mode, mode.label),
                  ],
                  value: app.themeMode,
                  onChanged: app.setThemeMode,
                ),
              ),
              SettingRow(
                glyph: AppGlyphs.liquidGlass,
                title: '低性能模式',
                subtitle: '关闭液态玻璃特效；设备不支持 shader 或耗电时可开启',
                trailing: Switch(
                  // 语义反转：开关是「低性能模式」，打开=关闭玻璃。
                  value: !app.liquidGlass,
                  semanticLabel: '低性能模式',
                  onChanged: (value) {
                    // 低性能模式开 → 关玻璃；关 → 开玻璃。
                    app.setLiquidGlass(!value);
                    if (value) {
                      BannerHost.maybeOf(context)?.show(
                        '已开启低性能模式，液态玻璃特效已关闭',
                        level: BannerLevel.info,
                      );
                    }
                  },
                ),
              ),
            ],
          ),

          const SectionHeader(title: '线路'),
          SectionCard(
            children: <Widget>[
              SettingRow(
                glyph: AppGlyphs.dns,
                title: '当前线路',
                subtitle: _lineLabel(baseUrl),
              ),
              if (hosts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final host in hosts)
                        Chip(
                          label: host,
                          // 一排紧凑 choice chip：选中项实心 primary，只允许一个。
                          selected: baseUrl != null && baseUrl.contains(host),
                          onPressed: () => _switchHost(host),
                        ),
                    ],
                  ),
                ),
            ],
          ),

          const SectionHeader(title: '缓存'),
          SectionCard(
            children: <Widget>[
              SettingRow(
                glyph: AppGlyphs.broom,
                title: '页图缓存',
                subtitle: _usageSubtitle,
                // 点行刷新统计（旧行为）；清理入口在行尾。
                onPressed: _busy ? null : _refreshUsage,
                trailing: _busy
                    ? const ActivityIndicator(size: 20)
                    : TextButton(
                        onPressed: _clearCache,
                        child: const Text('清理'),
                      ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '看过的页会缓存在本地，退出阅读器或重启 App 后再进入无需重新下载。',
              // 说明文字：footnote + 次要色，字号/颜色都来自令牌。
              style: context.listCaptionStyle,
            ),
          ),

          const SectionHeader(title: '关于'),
          SectionCard(
            children: <Widget>[
              const ValueRow(title: '版本', value: _appVersion),
              SettingRow(
                glyph: AppGlyphs.link,
                title: '图片 CDN',
                subtitle: app.imgHost,
              ),
              const SettingRow(
                glyph: AppGlyphs.memory,
                title: '渲染引擎',
                subtitle: 'Flutter · prism_ui · 预测式返回动画',
              ),
              const SettingRow(
                glyph: AppGlyphs.warning,
                title: '内容声明',
                subtitle: '本应用仅用于技术演示，数据来自第三方公开网关，'
                    '内容版权归原作者所有。',
              ),
            ],
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
