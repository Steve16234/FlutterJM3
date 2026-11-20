import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/scroll_behavior.dart';
import 'package:prism_ui/shape.dart';

import 'inherited.dart';
import 'liquid_glass.dart';
import 'sheet_navigator.dart';
import 'package:prism_ui/surface.dart';

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  static const height = _topPadding + _thickness;

  static const _topPadding = 6.0;
  static const _thickness = 4.0;
  static const _width = 28.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _topPadding),
      child: Container(
        alignment: Alignment.center,
        height: _thickness,
        width: _width,
        decoration: ShapeDecoration(
          color: context.colorScheme.onSurfaceVariant,
          shape: AppShape.all(_thickness / 2),
        ),
      ),
    );
  }
}

/// A drag handle, or its space, over [appBar], together exactly
/// [sheetAppBarHeight] tall.
class SheetToolBar extends StatelessWidget {
  const SheetToolBar({super.key, required this.appBar, this.dragHandle = true});

  static const _trailing =
      sheetAppBarHeight - SheetDragHandle.height - sheetToolbarHeight;

  final Widget appBar;
  final bool dragHandle;

  @override
  Widget build(BuildContext context) {
    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A paged sheet holds its handle still over the pages it moves.
        dragHandle && !isSheetPage(context)
            ? const SheetDragHandle()
            : const SizedBox(height: SheetDragHandle.height),
        appBar,
        const SizedBox(height: _trailing),
      ],
    );
    return dragHandle
        ? GestureDetector(behavior: HitTestBehavior.opaque, child: bar)
        : bar;
  }
}

/// Fades the surface behind [child] toward its foot so content reads through,
/// easing out over [overhang] past the foot so the fade shows no edge.
///
/// With [LiquidGlassScope] enabled the header instead stands on a glass pane
/// whose bottom corners round off into the page and whose optics taper out
/// toward that same foot: the bar no longer ends on the flat, hard edge of a
/// scrim, but dissolves into the glass already used by the dock and controls.
class FloatingHeader extends StatelessWidget {
  const FloatingHeader({
    super.key,
    required this.backgroundColor,
    this.fadeStart = 0.5,
    this.overhang = 0,
    required this.child,
  });

  static const _alpha = 0.9;
  static const _fadeSteps = 8;

  final Color backgroundColor;
  final double fadeStart;
  final double overhang;
  final Widget child;

  Gradient _scrimOf(double height) {
    // The old gradient ended at full alpha one pixel above its foot, which
    // read as a hard edge. Finish fully transparent and ease the last leg so
    // the non-glass path fades out just as quietly.
    final start = (height - overhang) * fadeStart / height;
    final stops = <double>[0];
    final colors = <Color>[backgroundColor.withValues(alpha: _alpha)];
    for (var i = 0; i <= _fadeSteps; i++) {
      final t = i / _fadeSteps;
      stops.add(start + (1 - start) * t);
      // A slightly softer curve than the old easeInOut: most of the leg is
      // already see-through, leaving no visible cut at the foot.
      colors.add(
        backgroundColor.withValues(
          alpha: _alpha * (1 - Curves.ease.transform(t)),
        ),
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: stops,
      colors: colors,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (LiquidGlassScope.of(context)) {
      return _GlassHeader(
        backgroundColor: backgroundColor,
        overhang: overhang,
        child: child,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: -overhang,
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (_, constraints) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _scrimOf(constraints.maxHeight),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The glass counterpart of the header scrim.
///
/// A bar is much wider than it is tall, so using the shader's default pill
/// would end it on a straight, hard edge. The pane instead rounds only its
/// bottom corners and keeps its top flush with the screen edge, so it reads
/// as a surface that grows out of the status bar and dissolves into the page
/// — the same glass the dock and controls already use. No shadow is cast:
/// a full-width bar has no outside to shadow into.
class _GlassHeader extends StatelessWidget {
  const _GlassHeader({
    required this.backgroundColor,
    required this.overhang,
    required this.child,
  });

  final Color backgroundColor;
  final double overhang;
  final Widget child;

  static const _corner = 28.0;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // Start from the pill optics already used by search fields, but keep the
    // bar quieter: a full-strength lens would magnify content the whole width.
    final style = LiquidGlassStyle.pill(scheme).copyWith(
      blur: 0,
      hazeBlur: 12,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: -overhang,
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (_, constraints) {
                if (constraints.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                return LiquidGlass(
                  style: style,
                  clipper: const _BarGlassClipper(_corner),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Rounds only the bar's bottom corners, leaving its top flush with the
/// screen edge. The pane is intentionally shorter than the scrim's overhang
/// so its rim dissolves just above the body.
class _BarGlassClipper extends CustomClipper<Path> {
  const _BarGlassClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) {
    final r = radius.clamp(0.0, size.shortestSide / 2).toDouble();
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - r)
      ..quadraticBezierTo(size.width, size.height, size.width - r, size.height)
      ..lineTo(r, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - r)
      ..close();
  }

  @override
  bool shouldReclip(_BarGlassClipper oldDelegate) =>
      oldDelegate.radius != radius;
}

/// Floats [header] over [body], fading it out so content reads through it
/// as it scrolls past; [footer] sits on its own surface.
class FloatingHeaderBody extends StatelessWidget {
  const FloatingHeaderBody({
    super.key,
    required this.backgroundColor,
    required this.header,
    required this.body,
    this.footer,
  });

  final Color backgroundColor;
  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: const ShowBarScrollBehavior(),
          child: body,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FloatingHeader(
            backgroundColor: backgroundColor,
            child: header,
          ),
        ),
        if (footer != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SheetOverhangLift(
              child: Surface.transparent(child: footer!),
            ),
          ),
      ],
    );
  }
}

/// Holds its child clear of the part of the sheet that hangs below the screen
/// while the sheet is dragged below its shortest detent.
class SheetOverhangLift extends SingleChildRenderObjectWidget {
  const SheetOverhangLift({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSheetOverhangLift(overhang: SheetOverhangScope.of(context));
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSheetOverhangLift).overhang = SheetOverhangScope.of(
      context,
    );
  }
}

class _RenderSheetOverhangLift extends RenderTransform {
  _RenderSheetOverhangLift({required ValueListenable<double>? overhang})
    : _overhang = overhang,
      super(transform: Matrix4.identity(), transformHitTests: true) {
    _overhang?.addListener(_syncTransform);
  }

  ValueListenable<double>? _overhang;

  set overhang(ValueListenable<double>? value) {
    if (_overhang == value) {
      return;
    }
    _overhang?.removeListener(_syncTransform);
    _overhang = value;
    _overhang?.addListener(_syncTransform);
    _syncTransform();
  }

  @override
  void performLayout() {
    super.performLayout();
    _syncTransform();
  }

  @override
  void dispose() {
    _overhang?.removeListener(_syncTransform);
    super.dispose();
  }

  void _syncTransform() {
    transform = Matrix4.translationValues(0, -(_overhang?.value ?? 0), 0);
  }
}
