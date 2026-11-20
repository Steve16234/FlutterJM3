import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../ui/icons/icons.dart';
import '../ui/page.dart';
import '../ui/rows.dart';
import '../ui/section.dart';
import '../ui/states.dart';
import '../widgets/openable_album.dart';

/// 每週必看：先选期数，再看该期榜单。
///
/// 两级页面（期数列表 → 单期榜单）都在本文件里，表现层换成 prism_ui：
/// 列表用 `SectionCard` + `NavigationRow`（一行一期，右侧 chevron），
/// 榜单用 `AlbumCard`（经由 `OpenableAlbumCard`，卡片长成全页的容器变换保持原样）。
///
/// **数据流没变**：`client.week()` / `client.weekFilter(id:)` 的调用点、参数，
/// 以及「进页面就加载，不等转场结束」（`didChangeDependencies`）都和旧实现一致。
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
      CardPageRoute<void>(builder: (_) => _WeekDetailScreen(issue: issue)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return JmPage(
      title: '每週必看',
      body: FutureBuilder<List<WeekIssue>>(
        future: _issues,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const JmLoading(label: '正在加载期数…');
          }
          if (snapshot.hasError) {
            return JmError(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _issues = _loadIssues()),
            );
          }

          final issues = snapshot.data ?? const <WeekIssue>[];
          if (issues.isEmpty) {
            return const JmEmpty(message: '暂无榜单');
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + context.bottomInset),
            children: <Widget>[
              // 一期一行、行间发丝线由 `SectionCard` 统一画（不用 Divider 手写）。
              SectionCard(
                children: <Widget>[
                  for (final issue in issues)
                    NavigationRow(
                      glyph: AppGlyphs.clock,
                      title: issue.time.isEmpty ? '第 ${issue.id} 期' : issue.time,
                      // 期号：旧列表把它画在左侧头像里，这里放到 chevron 左边。
                      trailing: issue.time.isEmpty
                          ? null
                          : MetaChip(label: issue.id),
                      onPressed: () => _openIssue(issue),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 某一期的榜单（二级页面，保留返回箭头）。
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

    return JmPage(
      title: widget.issue.time.isEmpty
          ? '第 ${widget.issue.id} 期'
          : widget.issue.time,
      body: FutureBuilder<PagedAlbums>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const JmLoading(label: '正在加载榜单…');
          }
          if (snapshot.hasError) {
            return JmError(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final albums = snapshot.data?.items ?? const <AlbumSummary>[];
          if (albums.isEmpty) {
            return const JmEmpty(message: '该期暂无内容');
          }

          return CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  24 + context.bottomInset,
                ),
                sliver: SliverGrid(
                  // 保持旧页面的比例与最大列宽：maxCrossAxisExtent 190、0.52。
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.52,
                      ),
                  delegate: SliverChildBuilderDelegate(
                    // 保留「卡片长成全页」的容器变换（原来就是 OpenableAlbumCard）。
                    (context, index) => OpenableAlbumCard(
                      album: albums[index],
                      imgHost: imgHost,
                    ),
                    childCount: albums.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
