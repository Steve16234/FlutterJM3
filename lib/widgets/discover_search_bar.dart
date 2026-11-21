import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart' as ilg;
import 'package:prism_ui/prism_ui.dart';

import '../ui/glass_fallback.dart' show frostFallbackStyle;
import '../ui/icons/icons.dart';
import '../ui/search_field.dart';

/// 「发现」页顶部可伸缩搜索栏（prism 版）。
///
/// 收起态：一枚迷你胶囊（放大镜 + 「搜索」），点一下展开；
/// 展开态：胶囊横向拉长铺满可用宽度，内容换成 [JmSearchField]（规范里的填充胶囊），
/// 左侧是返回箭头、右侧是有内容时才出现的清空按钮。
///
/// 展开 / 收起**完全由父级驱动**（`HomeScreen` 持有 `expanded`），本组件只是受控
/// 组件；它自己只做两件事：
///
/// 1. 展开后让 [JmSearchField] 自动聚焦（`autofocus`），等价于旧实现里
///    「等宽度动画起步后再 `requestFocus`」，键盘与展开动画不会互相打断；
/// 2. 输入框失焦（点空白处、系统返回收起键盘）时通知父级收起 —— 靠一层**只观察
///    不参与遍历**的祖先 [Focus] 读 `hasFocus`（含后代）实现，因为 [JmSearchField]
///    自己持有 `FocusNode` 且没有对外暴露，这里不去重写一遍输入框。
///
/// 什么时候别用：需要用户直接输入的表单字段（登录、订阅链接）用 prism 的
/// `TextField` + `ListRow`，不要套这个胶囊。
class DiscoverSearchBar extends StatefulWidget {
  const DiscoverSearchBar({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onSubmitted,
    this.fillWidth = false,
  });

  /// 收起态下搜索框的宽度。
  static const double compactWidth = 148;

  /// 搜索框一行的高度（收起态胶囊与展开态输入框同高，切换时不跳）。
  static const double barHeight = 48;

  final TextEditingController controller;
  final bool expanded;

  /// true 时收起态也铺满父级给的约束宽度（首页顶部 6/9 那种独立胶囊行）。
  /// false 时收起态是固定宽度的迷你胶囊（旧行为）。
  final bool fillWidth;

  /// 展开 / 收起请求（点击收起态胶囊或展开态的返回箭头）。
  final ValueChanged<bool> onExpandedChanged;

  /// 键盘提交搜索；给的是去掉首尾空白的字符串。
  final ValueChanged<String> onSubmitted;

  @override
  State<DiscoverSearchBar> createState() => _DiscoverSearchBarState();
}

class _DiscoverSearchBarState extends State<DiscoverSearchBar> {
  /// 只观察搜索栏子树的焦点：不参与 Tab 遍历、自己也不要焦点。
  /// `hasFocus` 包含后代，所以 [JmSearchField] 里的输入框一失焦它就会变成 false。
  final FocusNode _scope = FocusNode(
    debugLabel: 'discover-search-scope',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _expand() {
    if (widget.expanded) return;
    widget.onExpandedChanged(true);
  }

  void _collapse() {
    _scope.unfocus();
    widget.onExpandedChanged(false);
  }

  /// 提交搜索时会出现一次「程序性失焦」：平台的输入法在 `TextInputAction.search`
  /// 之后由 `EditableText` 自己 `unfocus` 收键盘（框架默认行为）。那不是用户离开
  /// 搜索，不能连带把整个搜索面板收起 —— 否则回车搜出来的结果根本来不及看。
  bool _submitBlur = false;

  /// 失焦即收起（点空白处 / 系统返回收键盘都会走到这里），保留旧手势语义。
  void _onFocusChanged(bool hasFocus) {
    if (hasFocus || !widget.expanded || !mounted) return;
    if (_submitBlur) {
      _submitBlur = false;
      return;
    }
    // 另起一帧再收起：焦点变化可能发生在 build 途中，不能在同一个回调里改父级状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) widget.onExpandedChanged(false);
    });
  }

  void _submit(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    _submitBlur = true;
    // 下一帧无论如何都要放开这个闸门，避免「提交但没失焦」时把后续真实的失焦吃掉。
    WidgetsBinding.instance.addPostFrameCallback((_) => _submitBlur = false);
    widget.onSubmitted(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.expanded;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 展开态铺满可用宽度；收起态默认固定宽度的迷你胶囊，
        // fillWidth 为 true 时（首页顶部独立行）也铺满父级给的约束宽度。
        final width = (expanded || widget.fillWidth)
            ? constraints.maxWidth
            : DiscoverSearchBar.compactWidth;
        return Focus(
          focusNode: _scope,
          skipTraversal: true,
          canRequestFocus: false,
          includeSemantics: false,
          onFocusChange: _onFocusChanged,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AnimatedContainer(
              duration: commonDuration,
              curve: Curves.easeInOutCubic,
              width: width,
              height: DiscoverSearchBar.barHeight,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: midDuration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: expanded ? _field(context) : _pill(context),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 收起态：一枚「看起来像搜索框」的胶囊按钮（不是输入框，点它才展开）。
  ///
  /// 液态玻璃开启时胶囊本体走 prism 的 LiquidGlass（pill 样式），PressSurface
  /// 的填充变透明——实底会把 shader 折射的内容完全盖住。
  /// 关闭时和顶栏圆钮一致，走 ios_liquid_glass 的磨砂 fallback（BackdropFilter），
  /// 而不是实底填充，否则关玻璃后搜索框光秃秃、另外两个钮却有磨砂。
  Widget _pill(BuildContext context) {
    final scheme = context.colorScheme;
    final glass = LiquidGlassScope.of(context);
    final pill = PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.full,
      padding: const EdgeInsets.only(left: 14, right: 12),
      onPressed: _expand,
      child: Row(
        children: <Widget>[
          GlyphIcon(
            AppGlyphs.search,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '搜索',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.body
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    final box = SizedBox(
      key: const ValueKey<String>('collapsed'),
      height: _fieldHeight,
      child: pill,
    );
    if (glass) {
      return LiquidGlass(
        style: LiquidGlassStyle.pill(scheme),
        child: box,
      );
    }
    // 关闭液态玻璃：磨砂 fallback，和顶栏另外两个圆钮同一套观感。
    return ilg.AdaptiveGlassSurface(
      borderRadius: _fieldHeight / 2,
      style: frostFallbackStyle,
      child: box,
    );
  }

  /// 展开态：规范里的填充胶囊输入框，左侧返回箭头（关闭搜索）。
  Widget _field(BuildContext context) {
    return JmSearchField(
      key: const ValueKey<String>('expanded'),
      controller: widget.controller,
      hint: '搜索漫画 / 作者 / 标签，或输入 JM 号直达…',
      autofocus: true,
      leading: Tooltip(
        message: '关闭搜索',
        child: PressRegion(
          onTap: _collapse,
          child: const Center(
            child: GlyphIcon(AppGlyphs.arrowBack, size: 20),
          ),
        ),
      ),
      onSubmitted: _submit,
    );
  }

  /// 与 [JmSearchField] 内部高度一致（44），收起 / 展开切换时不留高度差。
  static const double _fieldHeight = 44;
}
