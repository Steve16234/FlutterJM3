import 'dart:ui' as ui;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../core/image_loader.dart';
import '../data/account_models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/rows.dart';
import '../ui/section.dart';
import 'account_albums_screen.dart';
import 'notifications_screen.dart';

/// 账号页（底栏第三页）。
///
/// 未登录时直接内嵌登录表单；已登录时展示账号信息与退出入口。
/// 登录走 `POST login`（multipart），会话有效期由服务端决定（见 [AppState.login]）。
///
/// 表现层：prism_ui（`JmPage` 骨架 + 分组行）。数据流一行没动：登录 / 登出仍走
/// [AppState]，三个列表页仍由调用方注入 `client.favorites / watchList /
/// trackingList` 的 loader。
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  /// bar 底部那条提交进度条；表单里的转圈由 [_busy] 驱动。
  final ValueNotifier<bool> _submitting = ValueNotifier<bool>(false);

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _submitting.dispose();
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
    _submitting.value = true;

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
    } finally {
      if (mounted) _submitting.value = false;
    }
  }

  void _openAlbums(
    String title,
    Future<AccountAlbumPage> Function(int page) loader,
    String empty,
  ) {
    BaseNavigator.push<void>(
      context,
      AccountAlbumsScreen(title: title, loader: loader, emptyMessage: empty),
    );
  }

  void _openNotifications() {
    BaseNavigator.push<void>(context, const NotificationsScreen());
  }

  /// 退出登录：破坏性动作，先确认再走 [AppState.logout]。
  Future<void> _logout(AppState app) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          title: '退出登录',
          destructive: true,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出'),
            ),
          ],
          child: const Text('退出后收藏、评论等操作需要重新登录。'),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // 登出会先 await 服务端，这里先把提示入口拿在手里。
    final banner = BannerHost.maybeOf(context);
    await app.logout();
    banner?.show('已退出登录');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return JmPage(
      title: app.loggedIn ? '我的' : '登录',
      // 底栏的一级页面，没有上级可返回。
      showBack: false,
      loading: _submitting,
      body: app.loggedIn ? _buildProfile(app) : _buildForm(),
    );
  }

  // ---------------------------------------------------------------- 未登录

  Widget _buildForm() {
    final scheme = context.colorScheme;

    return ListView(
      // 这一页在底栏框架里：底部让开浮动 dock，用 context.bottomInset 取高度。
      padding: EdgeInsets.fromLTRB(16, 32, 16, 24 + context.bottomInset),
      children: <Widget>[
        Center(
          child: GlyphIcon(AppGlyphs.account, size: 64, color: scheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          '禁漫账号',
          textAlign: TextAlign.center,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 6),
        Text(
          '登录后可收藏、评论、同步浏览历史',
          textAlign: TextAlign.center,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        // 登录表单只有两个字段、且是这一页的主体，属于「孤立在页面上的字段」：
        // 描边由 AppInputBorder 自己给，调用点不设 border。
        TextField(
          controller: _account,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: '账号 / 邮箱',
            prefixIcon: GlyphIcon(AppGlyphs.account),
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
            hintText: '密码',
            prefixIcon: const GlyphIcon(AppGlyphs.lock),
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示密码' : '隐藏密码',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: GlyphIcon(_obscure ? AppGlyphs.eyeOff : AppGlyphs.eye),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GlyphIcon(AppGlyphs.warning, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? ActivityIndicator(size: 20, color: scheme.onPrimary)
              : const Text('登录'),
        ),
        const SizedBox(height: 16),
        Text(
          '登录后长期有效，服务端失效时需重新登录',
          textAlign: TextAlign.center,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 已登录

  Widget _buildProfile(AppState app) {
    final scheme = context.colorScheme;
    final meta = app.userId > 0 ? 'UID ${app.userId}' : '';

    return ListView(
      // 同上：底部让开浮动 dock。
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + context.bottomInset),
      children: <Widget>[
        Row(
          children: <Widget>[
            _ProfileAvatar(url: app.avatarUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    app.username.isEmpty ? '已登录' : app.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.title2.of(context, emphasized: true),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: '我的内容'),
        SectionCard(
          children: <Widget>[
            NavigationRow(
              glyph: AppGlyphs.heart,
              title: '我的收藏',
              onPressed: () => _openAlbums(
                '我的收藏',
                (page) => app.client.favorites(page: page),
                '还没有收藏任何作品',
              ),
            ),
            NavigationRow(
              glyph: AppGlyphs.clock,
              title: '浏览历史',
              onPressed: () => _openAlbums(
                '浏览历史',
                (page) => app.client.watchList(page: page),
                '还没有浏览记录',
              ),
            ),
            NavigationRow(
              glyph: AppGlyphs.bookmarks,
              title: '我的关注',
              onPressed: () => _openAlbums(
                '我的关注',
                (page) => app.client.trackingList(page: page),
                '还没有关注的作品',
              ),
            ),
            NavigationRow(
              glyph: AppGlyphs.bell,
              title: '站内通知',
              onPressed: _openNotifications,
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 破坏性动作：`danger` 上 `ColorScheme.destructive`（iOS systemRed），
        // 不用 `error`（那是「出错了」）。
        SettingRow(
          glyph: AppGlyphs.logout,
          title: '退出登录',
          danger: true,
          onPressed: () => _logout(app),
        ),
        const SizedBox(height: 16),
        Text(
          '登录状态长期有效；若服务端判定失效，会自动退出并要求重新登录。',
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 头像：有 `photo` 就走与封面同一条图片管线（UA / Referer / 三层缓存 / 并发合并），
/// 没有或加载失败就显示占位 glyph，不会跳尺寸、不会自己发 http。
class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({required this.url});

  final String url;

  static const double size = 64;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  static const int _avatarAid = 0;
  static const int _avatarScrambleId = 1;

  ui.Image? _image;

  /// 已向缓存借出引用、还没归还的 URL。
  String? _heldUrl;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _release();
      _image = null;
      _start();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    final url = _heldUrl;
    if (url == null) return;
    _heldUrl = null;
    PageImageLoader.shared.release(url);
  }

  void _start() {
    final url = widget.url;
    if (url.isEmpty || !url.startsWith('http')) return;
    _fetch(url);
  }

  Future<void> _fetch(String url) async {
    try {
      final image = await PageImageLoader.shared.load(
        url: url,
        aid: _avatarAid,
        scrambleId: _avatarScrambleId,
      );
      if (!mounted || widget.url != url) {
        PageImageLoader.shared.release(url);
        return;
      }
      _heldUrl = url;
      setState(() => _image = image);
    } catch (_) {
      // 头像拿不到就保持占位，不影响登录态展示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final image = _image;
    final placeholder = ColoredBox(
      color: context.raisedSurfaceLevel.colorOf(scheme),
      child: Center(
        child: GlyphIcon(
          AppGlyphs.account,
          size: 32,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    return SizedBox(
      width: _ProfileAvatar.size,
      height: _ProfileAvatar.size,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.full,
        child: image == null
            ? placeholder
            : RawImage(
                image: image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}
