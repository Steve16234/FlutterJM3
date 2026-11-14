import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'album_list_screen.dart';
import 'week_screen.dart';

/// 书库页：分类浏览 + 每周必看入口 + 随机推荐。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  Future<List<Category>>? _categories;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categories ??= _loadCategories();
  }

  Future<List<Category>> _loadCategories() async {
    final client = context.read<AppState>().client;
    final raw = await client.categories();
    return raw
        .whereType<Map>()
        .map((e) => Category.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  void _openCategory(Category category, {SubCategory? sub}) {
    final client = context.read<AppState>().client;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PagedAlbumScreen(
          title: category.name,
          subtitle: sub?.name,
          asGrid: true,
          loader: (page) async {
            final json = await client.categoriesFilter(
              page: page,
              category: sub?.id ?? category.id,
            );
            return PagedAlbums.fromJson(json, page: page);
          },
        ),
      ),
    );
  }

  void _openRandom() {
    final client = context.read<AppState>().client;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PagedAlbumScreen(
          title: '随机推荐',
          asGrid: true,
          loader: (page) async {
            final list = await client.randomRecommend();
            return PagedAlbums(
              items: list
                  .whereType<Map>()
                  .map((e) => AlbumSummary.fromJson(e.cast<String, dynamic>()))
                  .toList(),
              total: 0,
              page: page,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: M3EAppBar.top(titleText: '书库'),
      body: FutureBuilder<List<Category>>(
        future: _categories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _categories = _loadCategories()),
            );
          }

          final categories = snapshot.data ?? const <Category>[];

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _categories = _loadCategories());
              await _categories;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                _quickActions(),
                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyView(message: '没有分类数据'),
                  ),
                for (final category in categories)
                  _categoryTile(category),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ActionCard(
              icon: Icons.leaderboard,
              label: '每周必看',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WeekScreen()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              icon: Icons.shuffle,
              label: '随机推荐',
              onTap: _openRandom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(Category category) {
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Text(
          category.name.characters.first,
          style: TextStyle(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(category.name),
      subtitle: category.totalAlbums > 0
          ? Text('${compactNumber(category.totalAlbums)} 部')
          : null,
      shape: const Border(),
      collapsedShape: const Border(),
      children: <Widget>[
        if (category.subCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: category.subCategories
                    .map((sub) => M3EChip(
                          label: sub.name,
                          type: M3EChipType.suggestion,
                          onPressed: () => _openCategory(category, sub: sub),
                        ))
                    .toList(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _openCategory(category),
              icon: const Icon(Icons.grid_view, size: 18),
              label: const Text('浏览全部'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            children: <Widget>[
              Icon(icon, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
