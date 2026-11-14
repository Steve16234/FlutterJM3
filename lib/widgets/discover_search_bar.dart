import 'package:material_ui/material_ui.dart';

/// 「发现」页顶部搜索栏。
///
/// 收起态：标题右侧的一枚小搜索框（胶囊）；
/// 展开态：点击后横向拉长，铺满整条 bar。
///
/// 动效保持朴素：统一用 [Durations.medium2] + [Curves.easeInOutCubic]，
/// 展开与收起对称，不做 emphasized 的分段曲线。
class DiscoverSearchBar extends StatefulWidget {
  const DiscoverSearchBar({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onSubmitted,
    required this.onOpenWeek,
  });

  /// 收起态下搜索框的宽度。
  static const double compactWidth = 148;
  static const double barHeight = 48;

  final TextEditingController controller;
  final bool expanded;

  /// 展开 / 收起请求（点击小搜索框或返回箭头）。
  final ValueChanged<bool> onExpandedChanged;

  /// 键盘提交搜索。
  final ValueChanged<String> onSubmitted;

  /// 打开「每周必看」。
  final VoidCallback onOpenWeek;

  @override
  State<DiscoverSearchBar> createState() => _DiscoverSearchBarState();
}

class _DiscoverSearchBarState extends State<DiscoverSearchBar> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(DiscoverSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded && !oldWidget.expanded) {
      // 等宽度动画起步后再聚焦，键盘弹出与展开动画不会互相打断。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } else if (!widget.expanded && oldWidget.expanded) {
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  /// 展开状态下失焦（例如点空白处）即收起，符合 M3 搜索栏行为。
  void _onFocusChanged() {
    if (!_focus.hasFocus && widget.expanded && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) widget.onExpandedChanged(false);
      });
    }
  }

  void _expand() {
    if (widget.expanded) return;
    widget.onExpandedChanged(true);
  }

  void _collapse() {
    _focus.unfocus();
    widget.onExpandedChanged(false);
  }

  void _submit(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    _focus.unfocus();
    widget.onSubmitted(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = widget.expanded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;

        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            // 标题行：展开时淡出并轻微上移，同时让出整条 bar。
            IgnorePointer(
              ignoring: expanded,
              child: AnimatedOpacity(
                opacity: expanded ? 0 : 1,
                duration: Durations.short4,
                curve: Curves.easeInOutCubic,
                child: AnimatedSlide(
                  offset: expanded ? const Offset(0, -0.08) : Offset.zero,
                  duration: Durations.short4,
                  curve: Curves.easeInOutCubic,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '发现',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '每周必看',
                          onPressed: widget.onOpenWeek,
                          icon: const Icon(Icons.leaderboard_outlined),
                        ),
                        const SizedBox(
                          width: DiscoverSearchBar.compactWidth + 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 搜索框本体：宽度 + 圆角 + 外边距一起做插值，视觉上就是「拉长铺满」。
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: Durations.medium2,
                curve: Curves.easeInOutCubic,
                width: expanded ? fullWidth : DiscoverSearchBar.compactWidth,
                height: DiscoverSearchBar.barHeight,
                margin: EdgeInsets.only(right: expanded ? 0 : 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: expanded
                      ? scheme.surfaceContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(expanded ? 0 : 24),
                    bottomLeft: Radius.circular(expanded ? 0 : 24),
                    topRight: Radius.circular(expanded ? 0 : 24),
                    bottomRight: Radius.circular(expanded ? 0 : 24),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: Durations.short4,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: expanded
                            ? IconButton(
                                key: const ValueKey<String>('back'),
                                tooltip: '关闭搜索',
                                onPressed: _collapse,
                                icon: const Icon(Icons.arrow_back),
                              )
                            : const SizedBox(
                                key: ValueKey<String>('search'),
                                width: 44,
                                child: Icon(Icons.search, size: 22),
                              ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focus,
                          readOnly: !expanded,
                          showCursor: expanded,
                          textInputAction: TextInputAction.search,
                          onTap: _expand,
                          onSubmitted: _submit,
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText:
                                expanded ? '搜索漫画 / 作者 / 标签，或输入 JM 号直达…' : '搜索',
                            hintStyle: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      // 有输入时给出清空按钮。
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.controller,
                        builder: (context, value, _) {
                          if (!expanded || value.text.isEmpty) {
                            return const SizedBox(width: 12);
                          }
                          return IconButton(
                            tooltip: '清空',
                            onPressed: () {
                              widget.controller.clear();
                              _focus.requestFocus();
                            },
                            icon: const Icon(Icons.close, size: 20),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
