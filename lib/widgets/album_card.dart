import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import 'common.dart';

/// 网格卡片的**内容**（封面 + 标题 + 作者）。
///
/// 卡片外壳（底色、圆角、按压反馈、容器变换）由 `material_3_expressive` 的
/// `M3ECard` 提供，见 `openable_album.dart`。这里只画内容，所以外层务必传
/// `padding: EdgeInsets.zero`，由内容自己控制内边距。
class AlbumCardContent extends StatelessWidget {
  const AlbumCardContent({
    super.key,
    required this.album,
    required this.imgHost,
  });

  final AlbumSummary album;
  final String imgHost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CoverImage(url: album.coverUrl(imgHost)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                ),
                const Spacer(),
                if (album.author.isNotEmpty)
                  Text(
                    album.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 横滑小卡片的内容。
class AlbumTileCompactContent extends StatelessWidget {
  const AlbumTileCompactContent({
    super.key,
    required this.album,
    required this.imgHost,
  });

  final AlbumSummary album;
  final String imgHost;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CoverImage(url: album.coverUrl(imgHost)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            album.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

/// 列表行内容（搜索结果 / 分类列表）。
class AlbumListTileContent extends StatelessWidget {
  const AlbumListTileContent({
    super.key,
    required this.album,
    required this.imgHost,
  });

  final AlbumSummary album;
  final String imgHost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: CoverImage(url: album.coverUrl(imgHost)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 6),
                if (album.author.isNotEmpty)
                  Text(
                    album.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    if (album.categoryTitle.isNotEmpty)
                      _Tag(text: album.categoryTitle),
                    if (album.categorySubTitle.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6),
                      _Tag(text: album.categorySubTitle),
                    ],
                    const Spacer(),
                    if (album.updateAt > 0)
                      Text(
                        relativeTime(album.updateAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
      ),
    );
  }
}
