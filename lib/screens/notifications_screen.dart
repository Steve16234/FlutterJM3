import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/account_models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/states.dart';

/// 站内通知（`notifications`）。
///
/// 表现层：prism_ui。列表刷新改到 bar 的刷新按钮（prism 没有下拉刷新）；
/// 点某一条用 prism 的可拖拽 sheet（`showSnapSheet`）看全文，正文用 prism 的
/// `SelectableText`（同名，来自 prism_ui 而不是 Material）。
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// sheet 的 bar 不需要进度条，给它一个常量监听，避免每次构建都造一个 notifier。
  static final ValueListenable<bool> _idle = ValueNotifier<bool>(false);

  final List<AccountNotification> _items = <AccountNotification>[];

  /// 已有数据时的刷新：只点亮 bar 的进度条，不闪屏。
  final ValueNotifier<bool> _refreshing = ValueNotifier<bool>(false);

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshing.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_items.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _refreshing.value = true;
    }
    try {
      final list = await context.read<AppState>().client.notifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      // 已有数据时保留旧列表，只用提示条报告失败（整页错误只留给空列表）。
      if (_items.isNotEmpty) {
        BannerHost.maybeOf(context)?.show(
          '刷新失败：$e',
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) _refreshing.value = false;
    }
  }

  /// 公告正文是 HTML 长文（已在 `account_models.dart` 折成纯文本），列表里截断，
  /// 点开用可拖拽 sheet 看全文。
  Future<void> _showDetail(AccountNotification item) {
    return showSnapSheet<void>(
      context,
      builder: (sheetContext, controller) {
        final scheme = sheetContext.colorScheme;
        return PrismScaffold(
          bar: ScaffoldBar(
            isCompact: true,
            listenable: Listenable.merge(const <Listenable>[]),
            loading: _idle,
            builder: (context) => AppBar(
              leading: ElasticPress(
                child: AppBarActionButton(
                  data: IconButtonData(
                    glyph: AppGlyphs.close,
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
              title: const Text('通知详情'),
            ),
          ),
          // sheet 的 bar 浮在 body 之上：顶部让开 sheetAppBarHeight，底部让开系统栏。
          body: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
              16,
              sheetContext.contentTopPadding,
              16,
              20 + sheetContext.bottomInset,
            ),
            children: <Widget>[
              Text(
                item.title,
                style: AppTextStyle.title3.of(sheetContext, emphasized: true),
              ),
              if (item.time.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  item.time,
                  style: AppTextStyle.footnote
                      .of(sheetContext)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              SelectableText(
                item.content.isEmpty ? '（无正文）' : item.content,
                style: AppTextStyle.body.of(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return JmPage(
      title: '站内通知',
      loading: _refreshing,
      actions: <JmBarAction>[
        JmBarAction(
          glyph: AppGlyphs.refresh,
          tooltip: '刷新',
          onPressed: _load,
        ),
      ],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      if (_loading) return const JmLoading();
      if (_error != null) return JmError(message: _error!, onRetry: _load);
      return const JmEmpty(message: '还没有通知');
    }

    final scheme = context.colorScheme;
    return PrismListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 20 + context.bottomInset),
      gap: 8,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final time = item.time;
        return Card(
          radius: AppCorner.xl,
          padding: EdgeInsets.zero,
          onPressed: () => _showDetail(item),
          child: ListRow(
            leading: GlyphIcon(
              AppGlyphs.bell,
              color: item.read ? scheme.onSurfaceVariant : scheme.primary,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.content.isEmpty
                ? const Text('无正文')
                : Text(
                    item.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
            // 列表只露前几行，点开看全文。
            trailing: time.isEmpty ? null : Text(time),
          ),
        );
      },
    );
  }
}
