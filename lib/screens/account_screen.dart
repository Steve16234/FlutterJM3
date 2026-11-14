import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/account_models.dart';
import '../state/app_state.dart';
import 'account_albums_screen.dart';
import 'notifications_screen.dart';

/// 账号页（底栏第三页）。
///
/// 未登录时直接内嵌登录表单；已登录时展示账号信息与退出入口。
/// 登录走 `POST login`（multipart），会话有效期 1 小时（见 [AppState.login]）。
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final account = _account.text.trim();
    final password = _password.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context
          .read<AppState>()
          .login(username: account, password: password);
      if (!mounted) return;
      _password.clear();
      setState(() => _busy = false);
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  void _openAlbums(
    String title,
    Future<AccountAlbumPage> Function(int page) loader,
    String empty,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountAlbumsScreen(
          title: title,
          loader: loader,
          emptyMessage: empty,
        ),
      ),
    );
  }

  Future<void> _logout(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后收藏、评论等操作需要重新登录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await app.logout();
    messenger.showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: Text(app.loggedIn ? '我的' : '登录')),
      body: app.loggedIn ? _buildProfile(app) : _buildForm(),
    );
  }

  // ---------------------------------------------------------------- 未登录

  Widget _buildForm() {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: <Widget>[
        Icon(Icons.account_circle, size: 72, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          '禁漫账号',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '登录后可收藏、评论、同步浏览历史',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _account,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '账号 / 邮箱',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          enabled: !_busy,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '密码',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示密码' : '隐藏密码',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility,
              ),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
        const SizedBox(height: 16),
        Text(
          '登录后长期有效，服务端失效时需重新登录',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 已登录

  Widget _buildProfile(AppState app) {
    final scheme = Theme.of(context).colorScheme;
    final meta = app.userId > 0 ? 'UID ${app.userId}' : '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            _avatar(app),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    app.username.isEmpty ? '已登录' : app.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: const Text('我的收藏'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAlbums(
            '我的收藏',
            (page) => app.client.favorites(page: page),
            '还没有收藏任何作品',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('浏览历史'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAlbums(
            '浏览历史',
            (page) => app.client.watchList(page: page),
            '还没有浏览记录',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bookmark_border),
          title: const Text('我的关注'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAlbums(
            '我的关注',
            (page) => app.client.trackingList(page: page),
            '还没有关注的作品',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_none),
          title: const Text('站内通知'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
          ),
        ),
        const Divider(),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _logout(app),
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 16),
        Text(
          '登录状态长期有效；若服务端判定失效，会自动退出并要求重新登录。',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _avatar(AppState app) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.person,
      size: 36,
      color: scheme.onSecondaryContainer,
    );
    final url = app.avatarUrl;

    if (url.isEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: scheme.secondaryContainer,
        child: fallback,
      );
    }
    return ClipOval(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ColoredBox(
            color: scheme.secondaryContainer,
            child: Center(child: fallback),
          ),
        ),
      ),
    );
  }
}

