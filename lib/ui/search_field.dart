import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'icons/icons.dart';

/// 填充胶囊搜索框（prism 规范里的搜索框形态）。
///
/// 形状是 `AppShape.input` 去掉描边 + `AppRadius.full`（胶囊）；填充取「当前表面
/// 的下一级」，所以在 page / card / sheet 里都不会和背景糊在一起。
///
/// 焦点环只在**键盘或遥控器把焦点移上来时**出现（`FocusMovedByKey` /
/// `RemoteFocusAdapter`）——鼠标点进来是不会有外圈的，这是规范要求的
/// 「触摸/指针不画环」。
///
/// ```dart
/// JmSearchField(
///   controller: _controller,
///   hint: '搜索作品名 / JM 号',
///   onChanged: (value) => setState(() => _query = value),
///   onSubmitted: (value) => _search(value),
///   onClear: () => setState(() => _query = ''),
/// )
/// ```
///
/// 参数说明：
/// * [controller] 不传时组件自己建一个（内部 dispose），传了由调用方负责；
/// * [onSubmitted] 给的是去掉首尾空白的字符串（键盘回车才会触发）；
/// * [onClear] 只在点右侧 × 时触发，用来清搜索结果之类的页面状态；
/// * [leading] 想换成返回箭头 / 分类图标时传，默认是放大镜。
///
/// 什么时候别用：条状 app bar 上那种「收起态的迷你搜索胶囊」需要自己控制宽度和
/// 展开动画（旧 `DiscoverSearchBar` 的逻辑），不要用这个组件硬拼；纯键盘输入框
/// （订阅链接、密码）用 prism 的 `TextField` + `ListRow`，搜索框的胶囊形态不适合表单。
class JmSearchField extends StatefulWidget {
  const JmSearchField({
    super.key,
    this.controller,
    this.hint = '搜索',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.leading,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;
  final Widget? leading;

  @override
  State<JmSearchField> createState() => _JmSearchFieldState();
}

class _JmSearchFieldState extends State<JmSearchField> {
  /// 与 `TonalButtonSize.bar.button` 同高：和 bar 上的按钮对齐。
  static const double _height = 44;
  static const double _glyphInset = 12;
  static const double _glyphSlot = 41;
  static const double _clearSlot = 44;

  TextEditingController? _owned;
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  TextEditingController get _controller =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant JmSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _owned)?.removeListener(_handleTextChanged);
      _hasText = _controller.text.isNotEmpty;
      _controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _owned?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText == _hasText) return;
    setState(() => _hasText = hasText);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final pill = AppShape.input.copyWith(borderRadius: AppRadius.full);
    // 液态玻璃开启时：胶囊本体交给 LiquidGlass（shader 折射背后的内容），
    // TextField 的填充改透明——再画一层实底会把玻璃完全盖住。
    // 关闭时维持原样：「当前表面的下一级」实底填充。
    final glass = LiquidGlassScope.of(context);
    final fill = glass
        ? const Color(0x00000000)
        : context.raisedSurfaceLevel.colorOf(scheme);
    final field = ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_focus, FocusMovedByKey.instance]),
      builder: (context, _) {
        final ringed = _focus.hasFocus &&
            (RemoteFocusAdapter.isEnabledOf(context) ||
                FocusMovedByKey.instance.value);
        return TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          style: AppTextStyle.body.of(context),
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(128),
          ],
          onChanged: widget.onChanged,
          onSubmitted: (value) => widget.onSubmitted?.call(value.trim()),
          decoration: InputDecoration(
            constraints: const BoxConstraints.tightFor(height: _height),
            filled: true,
            fillColor: fill,
            hintText: widget.hint,
            // 胶囊：描边一律去掉，只有「键盘/遥控移上来」时才画焦点环。
            border: pill.copyWith(borderSide: BorderSide.none),
            enabledBorder: pill.copyWith(borderSide: BorderSide.none),
            focusedBorder: pill.copyWith(
              borderSide: ringed ? focusRingSide(scheme) : BorderSide.none,
            ),
            contentPadding: EdgeInsetsDirectional.only(
              end: _hasText ? 0 : 12,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: _glyphInset),
              child: widget.leading ?? const GlyphIcon(Glyphs.search, size: 20),
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: _glyphSlot,
            ),
            suffixIcon: _hasText ? _clearButton(scheme) : null,
            suffixIconConstraints: const BoxConstraints(),
          ),
        );
      },
    );
    if (!glass) return field;
    return LiquidGlass(
      style: LiquidGlassStyle.pill(scheme),
      child: field,
    );
  }

  Widget _clearButton(ColorScheme scheme) {
    return SizedBox(
      width: _clearSlot,
      child: IconButton(
        tooltip: _clearLabel(context),
        onPressed: _clear,
        style: ButtonStyle.from(foregroundColor: scheme.onSurface),
        icon: const GlyphIcon(Glyphs.clearField, size: 24, fill: 1),
      ),
    );
  }

  /// prism 的文案（应用里注册了 `JmUiLocalizations`）；拿不到时退回中文。
  static String _clearLabel(BuildContext context) =>
      Localizations.of<UiLocalizations>(context, UiLocalizations)?.clearSearch ??
      '清空搜索';
}
