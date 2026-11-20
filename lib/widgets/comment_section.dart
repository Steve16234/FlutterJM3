// `TextInputAction` 在 services 层（不是 material），评论框要显式声明回车换行。
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/section.dart';
// 只借这个纯函数（1.2万 这样的数字缩写）；三态 / 分组标题都已换成 prism 组件。
import '../core/format.dart' show compactNumber;

/// 漫画详情页的评论区。
///
/// 数据来自 `forum?mode=manhua&aid=<id>&page=<n>`，返回 `{list, total}`，
/// 每页 10 条，按时间倒序。
///
/// 它是详情页里的一个**普通子节点**（没有自己的 `Scaffold`，也没有自己的滚动
/// 容器），滚动由外层 `CustomScrollView` 提供 —— 换布局时别把它改成独立可滚组件。
class CommentSection extends StatefulWidget {
  const CommentSection({
    super.key,
    required this.albumId,
    this.totalHint = 0,
  });

  final String albumId;

  /// 详情接口给出的评论总数，用于列表未加载完时先显示数字。
  final int totalHint;

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final List<Comment> _items = <Comment>[];

  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  /// 发评论面板是否展开。
  bool _composerOpen = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// 打开写评论面板。未登录直接给出登录引导。
  Future<void> _openComposer() async {
    if (!context.read<AppState>().loggedIn) {
      BannerHost.maybeOf(context)?.show('请先在底栏「登录」页登录');
      return;
    }
    setState(() => _composerOpen = true);
  }

  /// 发送成功后把「加载过的页」整体重拉一次。
  ///
  /// 新评论出现在首页顶部，逐页 append 的话会把旧的第 1 页顶掉，
  /// 这里干脆从 0 重来，页码与 `_total` 都能保持自洽。
  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _total = 0;
      _loadedOnce = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = context.read<AppState>().client;
      final next = _page + 1;
      final json = await client.forum(aid: widget.albumId, page: next);
      final paged = PagedComments.fromJson(json, page: next);
      if (!mounted) return;
      setState(() {
        _page = next;
        _total = paged.total;
        _items.addAll(paged.items);
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadedOnce = true;
      });
    }
  }

  bool get _hasMore => _items.length < _total;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final imgHost = context.watch<AppState>().imgHost;
    final count = _total > 0 ? _total : widget.totalHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 写评论面板（默认收起，不占位；展开 / 收起走同一条 AnimatedSize）。
        AnimatedSize(
          duration: commonDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _composerOpen
              ? _CommentComposer(
                  albumId: widget.albumId,
                  onCancel: () => setState(() => _composerOpen = false),
                  onSent: () {
                    setState(() => _composerOpen = false);
                    _reload();
                  },
                )
              : const SizedBox(width: double.infinity),
        ),
        SectionHeader(
          title: '评论',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: <Widget>[
              if (count > 0) MetaChip(label: compactNumber(count)),
              TextButton.icon(
                onPressed: _openComposer,
                icon: const GlyphIcon(AppGlyphs.compose, size: 16),
                label: const Text('写评论'),
              ),
            ],
          ),
        ),
        if (!_loadedOnce && _loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: ActivityIndicator(size: 22)),
          )
        else if (_items.isEmpty && _error != null)
          // 局部失败：在行内给错误与重试，不把整页换成错误态。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: <Widget>[
                GlyphIcon(AppGlyphs.error, size: 18, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppTextStyle.footnote.of(context).copyWith(
                          color: scheme.error,
                        ),
                  ),
                ),
                TextButton(onPressed: _loadMore, child: const Text('重试')),
              ],
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '还没有评论',
              style: AppTextStyle.footnote.of(context).copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == _items.length - 1 ? 0 : 8,
                    ),
                    child: _CommentTile(
                      key: ValueKey<String>(_items[i].id),
                      comment: _items[i],
                      albumId: widget.albumId,
                      imgHost: imgHost,
                    ),
                  ),
              ],
            ),
          ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: _hasMore
                ? SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _loading ? null : _loadMore,
                      child: _loading
                          ? const ActivityIndicator(size: 18)
                          : Text('查看更多评论（${_items.length}/$_total）'),
                    ),
                  )
                : Center(
                    child: Text(
                      '没有更多评论了',
                      style: AppTextStyle.caption1.of(context).copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 写评论面板：正文输入 + 剧透开关 + 发表。
///
/// 默认收起，点标题行的「写评论」展开。正文上限 200 字（与服务端一致），
/// 剧透开关打开后以 `spoiler=2` 提交，列表里对应的评论会自动折叠。
class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    required this.albumId,
    required this.onCancel,
    required this.onSent,
  });

  final String albumId;
  final VoidCallback onCancel;

  /// 发表成功后回调，由父级收起面板并重拉列表。
  final VoidCallback onSent;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  static const int _maxLength = 200;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _spoiler = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 展开后自动聚焦，少点一下。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final banners = BannerHost.maybeOf(context);
    try {
      final result = await context.read<AppState>().client.sendComment(
            aid: widget.albumId,
            content: text,
            spoiler: _spoiler,
          );
      if (!mounted) return;
      setState(() => _sending = false);

      banners?.show(
        result.message,
        level: result.ok ? BannerLevel.success : BannerLevel.error,
      );
      if (result.ok) {
        // 成功后立刻清空并收起，避免用户再点一次撞上限流。
        _controller.clear();
        widget.onSent();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      banners?.show('$e', level: BannerLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final length = _controller.text.characters.length;
    final canSend = _controller.text.trim().isNotEmpty && !_sending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Card(
        // 面板本身是一张卡；里面的字段再降一级，靠的是 Card 的 SurfaceScope。
        inert: true,
        radius: AppCorner.xl,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 卡片里的评论框用填充式（无描边，只有键盘 / 遥控器把焦点移上来时才描边）。
            FilledInputTheme(
              borderRadius: AppRadius.md,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 3,
                maxLines: 8,
                maxLength: _maxLength,
                textInputAction: TextInputAction.newline,
                enabled: !_sending,
                // prism 自带计数器，这里自己画（第一行的 n/200）。
                buildCounter: (
                  context, {
                  required currentLength,
                  required maxLength,
                  required isFocused,
                }) =>
                    null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _spoiler ? '剧透内容会被折叠，需点击才显示' : '说点什么吧…',
                ),
                style: AppTextStyle.subheadline.of(context),
              ),
            ),
            const SizedBox(height: 8),
            // 第一行：剧透开关 + 自绘的 0/200 计数。
            Row(
              children: <Widget>[
                // 剧透开关：用可选择的 chip，点击区域比开关大、语义更直白。
                Chip(
                  label: '剧透',
                  selected: _spoiler,
                  onPressed:
                      _sending ? null : () => setState(() => _spoiler = !_spoiler),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$length/$_maxLength',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption2.of(context).copyWith(
                          color: length >= _maxLength
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            // 第二行：取消 / 发表靠右。窄屏下两行各占一行，不会挤成溢出。
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: _sending ? null : widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: canSend ? _send : null,
                  child: _sending
                      ? const ActivityIndicator(size: 16)
                      : const Text('发表'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条评论。剧透内容默认折叠，点击展开。
class _CommentTile extends StatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.albumId,
    required this.imgHost,
  });

  final Comment comment;

  /// 当前漫画号，标在每条评论右侧。
  final String albumId;
  final String imgHost;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final comment = widget.comment;
    final avatar = comment.avatarUrl(widget.imgHost);
    final hidden = comment.isSpoiler && !_revealed;

    return Card(
      // 评论行不可点（点击只发生在剧透提示块上），`inert` 让它保持正常配色。
      inert: true,
      radius: AppCorner.xl,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(url: avatar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      flex: 3,
                      child: Text(
                        comment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    if (comment.level > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      MetaChip(label: 'Lv${comment.level}'),
                    ],
                    const SizedBox(width: 8),
                    // 窄屏（或超长日期文案）时先省略时间，不让整行溢出。
                    Flexible(
                      flex: 2,
                      child: Text(
                        comment.addTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption2.of(context).copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (hidden)
                  SizedBox(width: double.infinity, child: _spoilerBlock(context))
                else
                  Text(
                    comment.content,
                    style: AppTextStyle.subheadline.of(context),
                  ),
                if (comment.likes > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      GlyphIcon(
                        AppGlyphs.heart,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${comment.likes}',
                        style: AppTextStyle.caption2.of(context).copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 每条评论右侧标上漫画号，字号比正文小一号。
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'JM${widget.albumId}',
              style: AppTextStyle.caption2.of(context).copyWith(
                    color: scheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// 剧透提示块：本身是能「吃」按压的表面，所以不会连带整张卡亮起来。
  Widget _spoilerBlock(BuildContext context) {
    final scheme = context.colorScheme;
    return PressSurface(
      fill: context.raisedSurfaceLevel.colorOf(scheme),
      shape: AppShape.md,
      childFills: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onPressed: () => setState(() => _revealed = true),
      child: Row(
        children: <Widget>[
          GlyphIcon(
            AppGlyphs.eyeOff,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '包含剧透，点击查看',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote.of(context).copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆形头像，加载中 / 失败时回退到占位图标。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    final Widget fallback = ColoredBox(
      color: context.raisedSurfaceLevel.colorOf(scheme),
      child: Center(
        child: GlyphIcon(
          AppGlyphs.account,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    // 头像不走页图管线（页图管线带 Referer / 乱序还原，头像不需要），
    // 也没有 CDN 前缀的那一半 URL 直接当失败处理，测试里不会真联网。
    final loadable = url.isNotEmpty && url.startsWith('http');

    return ClipOval(
      child: SizedBox(
        width: _size,
        height: _size,
        child: loadable
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              )
            : fallback,
      ),
    );
  }
}
