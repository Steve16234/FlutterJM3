import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/album_card.dart';
import '../widgets/common.dart';
import 'album_detail_screen.dart';

/// 每週必看：先选期数，再看该期榜单。
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  Future<List<WeekIssue>>? _issues;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _issues ??= _loadIssues();
  }

  Future<List<WeekIssue>> _loadIssues() async {
    final client = context.read<AppState>().client;
    final raw = await client.week();
    return raw
        .whereType<Map>()
        .map((e) => WeekIssue.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  void _openIssue(WeekIssue issue) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _WeekDetailScreen(issue: issue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每週必看')),
      body: FutureBuilder<List<WeekIssue>>(
        future: _issues,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _issues = _loadIssues()),
            );
          }
          final issues = snapshot.data ?? const <WeekIssue>[];
          if (issues.isEmpty) {
            return const EmptyView(message: '暂无榜单');
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: issues.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final issue = issues[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: Text(
                    issue.id,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                title: Text(issue.time.isEmpty ? '第 ${issue.id} 期' : issue.time),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openIssue(issue),
              );
            },
          );
        },
      ),
    );
  }
}

class _WeekDetailScreen extends StatefulWidget {
  const _WeekDetailScreen({required this.issue});

  final WeekIssue issue;

  @override
  State<_WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends State<_WeekDetailScreen> {
  Future<PagedAlbums>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<PagedAlbums> _load() async {
    final client = context.read<AppState>().client;
    final json = await client.weekFilter(id: widget.issue.id);
    return PagedAlbums.fromJson(json);
  }

  @override
  Widget build(BuildContext context) {
    final imgHost = context.watch<AppState>().imgHost;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.issue.time.isEmpty
            ? '第 ${widget.issue.id} 期'
            : widget.issue.time),
      ),
      body: FutureBuilder<PagedAlbums>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final albums = snapshot.data?.items ?? const <AlbumSummary>[];
          if (albums.isEmpty) {
            return const EmptyView(message: '该期暂无内容');
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return AlbumCard(
                album: album,
                imgHost: imgHost,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlbumDetailScreen(albumId: album.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
