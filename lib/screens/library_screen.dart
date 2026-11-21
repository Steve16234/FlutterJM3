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
import 'album_list_screen.dart';
import 'week_screen.dart';

/// 书库页：快捷入口（每周必看 / 随机推荐）+ 两级分类浏览。
///
/// 表现层换成 prism_ui，**数据流没变**：`client.categories()` /
/// `client.categoriesFilter()` 的调用点、参数，以及「进页面就加载」的时机
/// （`didChangeDependencies`）都和旧实现一致。
///
/// 三处换法值得记下来：
///
/// * `ExpansionTile` 在 prism_ui 里没有；`SliverCollapsibleSection` 是 sliver +
///   「表头必须显示条目数」的形态（一行一个条目），装不下「表头 + 一整片
///   chip 云 + 浏览全部」这种分组，所以这里用 `Card` + 自己一位展开状态，
///   高度变化交给 `AnimatedSize`（时长取 [midDuration]）。
/// * `RefreshIndicator` 在 prism_ui 里不存在：刷新改成 bar 右侧的动作按钮，
///   「已有数据、正在重拉」时只亮 bar 底部那条 3dp 进度条（`JmPage.loading`）。
/// * 快捷卡原来是 `primaryContainer` 填充——规范禁止用容器色当卡片底色，
///   改成普通 `Card`（层级填充由组件自己取）。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  /// 最近一次成功拉到的分类。刷新失败时**不清空**（保留旧数据 + banner 提示）。
  List<Category> _categories = const <Category>[];

  bool _loading = false;
  String? _error;

  /// 首帧是否已经发过请求：`didChangeDependencies` 会被调多次，只发一次。
  bool _requested = false;

  /// bar 底部那条进度条。只有「已有分类、正在重新拉」时才亮。
  final ValueNotifier<bool> _refreshing = ValueNotifier<bool>(false);

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // 进页面就发请求，不等转场结束（旧实现同样是 didChangeDependencies）。
    _loading = true;
    _load();
  }

  @override
  void dispose() {
    _refreshing.dispose();
    super.dispose();
  }

  /// 拉分类树。[refreshing] = 已经有数据、只是重新拉：不换成整页转圈（会闪）。
  Future<void> _load({bool refreshing = false}) async {
    final client = context.read<AppState>().client;
    if (refreshing) {
      _refreshing.value = true;
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final raw = await client.categories();
      if (!mounted) return;
      final categories = raw
          .whereType<Map>()
          .map((e) => Category.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
      setState(() {
        _categories = categories;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      // 已经有数据时不要让整页变成错误页：保留旧列表，只用 banner 提示。
      if (_categories.isNotEmpty) {
        BannerHost.maybeOf(context)?.show(
          '分类刷新失败',
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) {
        _refreshing.value = false;
      }
    }
  }

  void _reload() => _load(refreshing: _categories.isNotEmpty);

  void _openWeek() {
    Navigator.of(context).push(
      CardPageRoute<void>(builder: (_) => const WeekScreen()),
    );
  }

  void _openRandom() {
    final client = context.read<AppState>().client;
    Navigator.of(context).push(
      CardPageRoute<void>(
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

  void _openCategory(Category category, {SubCategory? sub}) {
    final client = context.read<AppState>().client;
    Navigator.of(context).push(
      CardPageRoute<void>(
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return JmPage(
      // 底部导航的一级页面：没有返回箭头。
      title: '书库',
      showBack: false,
      loading: _refreshing,
      actions: <JmBarAction>[
        JmBarAction(
          glyph: AppGlyphs.refresh,
          tooltip: '刷新',
          onPressed: _reload,
        ),
      ],
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_categories.isEmpty) {
      if (_loading) {
        return const JmLoading(label: '正在加载分类…');
      }
      final error = _error;
      if (error != null) {
        return JmError(message: error, onRetry: () => _load());
      }
      return const JmEmpty(message: '没有分类数据', hint: '点右上角的刷新按钮再试一次。');
    }

    return ListView(
      // 底部让开浮动 dock：用 context.bottomInset，不写死数字。
      padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + context.bottomInset),
      children: <Widget>[
        _quickActions(context),
        const SectionHeader(title: '分类'),
        for (final category in _categories) ...<Widget>[
          _CategoryCard(
            key: ValueKey<String>(category.id),
            category: category,
            onOpenAll: () => _openCategory(category),
            onOpenSub: (sub) => _openCategory(category, sub: sub),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _quickActions(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickAction(
            glyph: AppGlyphs.clock,
            label: '每周必看',
            onPressed: _openWeek,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickAction(
            glyph: AppGlyphs.shuffle,
            label: '随机推荐',
            onPressed: _openRandom,
          ),
        ),
      ],
    );
  }
}

/// 快捷入口卡：glyph + 文案，整卡可点。
///
/// 旧实现是 `primaryContainer` 填充 + `InkWell`；现在填充由 `Card` 按层级自己取，
/// 按压 / 焦点环 / 语义由 `PressSurface` 提供（不需要 `InkWell`）。
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      onPressed: onPressed,
      radius: AppCorner.lg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: <Widget>[
          GlyphIcon(glyph),
          const SizedBox(width: 8),
          // 320 宽下两张卡各约 140：文案允许省略号，绝不溢出。
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个分类 = 一张卡：表头行（可点、chevron 转）+ 展开后的子分类 chip 云。
///
/// 折叠本身用一位本地状态 + `AnimatedSize`：收起时子树根本不建（chip 不参与布局），
/// 展开时按原布局排（`TagWrap` 换行 + 「浏览全部」按钮）。
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    super.key,
    required this.category,
    required this.onOpenAll,
    required this.onOpenSub,
  });

  final Category category;
  final VoidCallback onOpenAll;
  final ValueChanged<SubCategory> onOpenSub;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final subCategories = category.subCategories;
    final duration = context.motionDuration(midDuration);

    return Card(
      padding: EdgeInsets.zero,
      // 可点的只有表头这一行（`SettingRow` 自带按压层）；卡内还有 chip / 按钮，
      // 所以不能给整张卡挂 onPressed，否则点 chip 会连带整卡一起亮。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingRow(
            glyph: AppGlyphs.appsList,
            title: category.name,
            subtitle: category.totalAlbums > 0
                ? '${_compactCount(category.totalAlbums)} 部'
                : null,
            trailing: AnimatedRotation(
              turns: _expanded ? 0 : -0.25,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: GlyphIcon(
                AppGlyphs.chevronDown,
                size: 20,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            onPressed: _toggle,
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _panel(context, subCategories)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, List<SubCategory> subCategories) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (subCategories.isNotEmpty) ...<Widget>[
            // 二级分类：套件的 `TagWrap`（可点 chip，灰底，不用容器色）。
            TagWrap(
              tags: <String>[
                for (final sub in subCategories)
                  if (sub.name.isNotEmpty) sub.name,
              ],
              onTagPressed: (name) {
                for (final sub in subCategories) {
                  if (sub.name == name) {
                    widget.onOpenSub(sub);
                    return;
                  }
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: widget.onOpenAll,
            icon: const GlyphIcon(AppGlyphs.appsList, size: 18),
            label: const Text('浏览全部'),
          ),
        ],
      ),
    );
  }
}

/// 本地版的数字缩写（`widgets/common.dart` 的 `compactNumber` 和 Material 组件
/// 放在同一个文件里，迁移后的页面不引它，这里保留同样的换算规则）。
String _compactCount(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万';
  }
  return '$value';
}
