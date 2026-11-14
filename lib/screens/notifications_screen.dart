import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/account_models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 站内通知（`notifications`）。
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AccountNotification> _items = <AccountNotification>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AppState>().client.notifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 公告正文是 HTML 长文，列表里截断，点开看全文。
  void _showDetail(AccountNotification item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView( 
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: <Widget>[
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (item.time.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  item.time,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              SelectableText(
                item.content.isEmpty ? '（无正文）' : item.content,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('站内通知')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(message: '还没有通知')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            leading: Icon(
                              item.read
                                  ? Icons.mark_email_read_outlined
                                  : Icons.mark_email_unread_outlined,
                              color: item.read
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
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
                            onTap: () => _showDetail(item),
                            trailing: item.time.isEmpty
                                ? null
                                : Text(
                                    item.time,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                          );
                        },
                      ),
                    ),
    );
  }
}
