import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'common.dart';

/// 漫画详情页的评论区。
///
/// 数据来自 `forum?mode=manhua&aid=<id>&page=<n>`，返回 `{list, total}`，
/// 每页 10 条，按时间倒序。
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

  /// 发评论弹层是否展开。
  bool _composerOpen = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// 打开写评论弹层。未登录直接引导到登录页。
  Future<void> _openComposer() async {
    if (!context.read<AppState>().loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在底栏「登录」页登录')),
      );
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
    final scheme = Theme.of(context).colorScheme;
    final imgHost = context.watch<AppState>().imgHost;
    final count = _total > 0 ? _total : widget.totalHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 写评论面板（默认收起，不占位）。
        AnimatedSize(
          duration: Durations.medium2,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            children: <Widget>[
              Text(
                '评论',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    compactNumber(count),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              const Spacer(),
              // 写评论入口：做成一眼可点的小按钮，长按区域足够。
              TextButton.icon(
                onPressed: _openComposer,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('写评论'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ),
        if (!_loadedOnce && _loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (_items.isEmpty && _error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ),
                TextButton(onPressed: _loadMore, child: const Text('重试')),
              ],
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              '还没有评论',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          ..._items.map(
            (c) => _CommentTile(
              key: ValueKey<String>(c.id),
              comment: c,
              albumId: widget.albumId,
              imgHost: imgHost,
            ),
          ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: _hasMore
                ? OutlinedButton(
                    onPressed: _loading ? null : _loadMore,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('查看更多评论（${_items.length}/$_total）'),
                  )
                : Center(
                    child: Text(
                      '没有更多评论了',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context.read<AppState>().client.sendComment(
            aid: widget.albumId,
            content: text,
            spoiler: _spoiler,
          );
      if (!mounted) return;
      setState(() => _sending = false);

      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (result.ok) {
        // 成功后立刻清空并收起，避免用户再点一次撞上限流。
        _controller.clear();
        widget.onSent();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final length = _controller.text.characters.length;
    final canSend = _controller.text.trim().isNotEmpty && !_sending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 3,
              maxLines: 8,
              maxLength: _maxLength,
              textInputAction: TextInputAction.newline,
              enabled: !_sending,
              // `maxLength` 自带的计数器吃掉不少高度，这里自己画。
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) =>
                  null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _spoiler ? '剧透内容会被折叠，需点击才显示' : '说点什么吧…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              style: textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                // 剧透开关：用 FilterChip 而不是 Switch，点击区域更大、语义更直白。
                FilterChip(
                  selected: _spoiler,
                  onSelected: _sending
                      ? null
                      : (v) => setState(() => _spoiler = v),
                  avatar: Icon(
                    Icons.visibility_off_outlined,
                    size: 16,
                    color: _spoiler
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  label: const Text('剧透'),
                  labelStyle: textTheme.labelMedium,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Spacer(),
                Text(
                  '$length/$_maxLength',
                  style: textTheme.labelSmall?.copyWith(
                    color: length >= _maxLength
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _sending ? null : widget.onCancel,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: canSend ? _send : null,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 36),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
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
    final scheme = Theme.of(context).colorScheme;
    final comment = widget.comment;
    final avatar = comment.avatarUrl(widget.imgHost);
    final hidden = comment.isSpoiler && !_revealed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                      child: Text(
                        comment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (comment.level > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      _LevelBadge(level: comment.level),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      comment.addTime,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (hidden)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _revealed = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.visibility_off_outlined,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '包含剧透，点击查看',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    comment.content,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.45),
                  ),
                if (comment.likes > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.favorite_border,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${comment.likes}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: scheme.outline,
                    fontWeight: FontWeight.w500,
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
    final scheme = Theme.of(context).colorScheme;

    final Widget fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.person_outline,
        size: 18,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: _size,
        height: _size,
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

/// 用户等级小徽标。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Lv$level',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
