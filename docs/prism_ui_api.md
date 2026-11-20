# prism_ui API 速查表

> 目标读者：把现有 Flutter 页面（当前用 `material.dart`）重写为 prism_ui 的开发者。
> 本文所有签名**逐字抄自源码**，不是凭记忆写的。
>
> - 源码：`packages/prism_ui/lib/`（v0.1.3，`pubspec.yaml` 要求 `flutter: '>=3.47.0'`、`sdk: '>=3.10.0'`）
> - 规范：`Q:\ref\FlClash\.agents\surfaces.md`、`Q:\ref\FlClash\.agents\skills\ui-work\SKILL.md`
> - 参考实现：`Q:\ref\FlClash\lib\ui\`、`Q:\ref\FlClash\lib\views\dashboard\`
>
> **约定**：文中「❌ 不存在」= 你列出的名字在 prism_ui 里没有，后面给出真实替代。

---

## 0. 30 秒速览

```dart
// ✅ 只 import 这两个
import 'package:flutter/widgets.dart';       // Text / Column / ListView / GestureDetector… 仍在 widgets 层
import 'package:prism_ui/prism_ui.dart';     // 全部组件

// ❌ 绝对不要
// import 'package:flutter/material.dart';
// import 'package:flutter/cupertino.dart';
```

`prism_ui.dart`（barrel，98 行）已 export 一切，**唯一例外**是 `icons/`：

```dart
import 'package:prism_ui/prism_ui.dart';      // 不含 Glyph / GlyphIcon / Glyphs
import 'package:prism_ui/icons/icons.dart';   // 必须额外 import 才能用 glyph
```

FlClash 的做法是建一个 `lib/ui/icons/icons.dart`：

```dart
export 'package:prism_ui/icons/icons.dart';
export 'app_glyphs.dart';   // AppGlyphs = 应用自己的图标集（见 §8）
```

### 启动模板（可直接复制）

```dart
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  ColorScheme _scheme(Brightness brightness) => seededColorScheme(
        seedColor: const Color(0xFF0B6BCB),
        brightness: brightness,
        style: ColorStyle.vivid,
      );

  ThemeData _theme(Brightness brightness) {
    final scheme = _scheme(brightness);
    return ThemeData(
      colorScheme: scheme,
      // 深色下让所有表面整体抬一级（sheet / 浮层需要），见 §3.4
      elevatedColorScheme: brightness == Brightness.dark ? scheme.elevated : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PrismApp(
      debugShowCheckedModeBanner: false,
      title: 'MyApp',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const ViewportScope(child: HomePage()),   // 必须包一层 ViewScope！
    );
  }
}
```

> `ViewportScope` 不是 prism_ui 的东西，是你自己要写的 3 行包装，见 §10 坑 1。

---

## 1. 入口：PrismApp / Theme / ThemeData

### 1.1 `PrismApp`（**不是** `MaterialApp`）

`lib/app.dart:28`

```dart
class PrismApp extends StatefulWidget {
  const PrismApp({
    super.key,
    this.navigatorKey,
    this.home,
    this.onGenerateRoute,
    this.onNavigationNotification,
    this.builder,
    this.title = '',
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const [Locale('en', 'US')],
    this.textScale,
    this.minTextScale = 0,
    this.maxTextScale = double.infinity,
    this.liquidGlass,
    this.emojiFont,
    this.stackedBanners = false,
    this.bannerTopInset = 0,
    this.remoteFocus = false,
    this.floatingKeyboard,
    this.debugShowCheckedModeBanner = true,
  });
}
```

| 参数 | 类型 | 作用 / 坑 |
|---|---|---|
| `theme` / `darkTheme` / `themeMode` | `ThemeData?` / `ThemeData?` / `ThemeMode` | `ThemeMode` 是 **prism_ui 自己的 enum**（`system/light/dark`，`theme_data.dart:14`），不是 Material 的 |
| `liquidGlass` | `LiquidGlassQuality?` | **null = 完全不开玻璃**。想要 iOS 26/27 玻璃效果传 `LiquidGlassQuality.standard` 或 `.ultra` |
| `stackedBanners` | `bool` | 多条 banner 叠放（桌面）还是单条排队（手机 iOS 行为） |
| `bannerTopInset` | `double` | banner 让开的顶部高度（你自己的窗口标题栏 + app bar） |
| `remoteFocus` | `bool` | TV/遥控器焦点模式（焦点环常显） |
| `floatingKeyboard` | `ValueListenable<bool>?` | 悬浮键盘（平板） |
| `textScale` / `minTextScale` / `maxTextScale` | `double?` / `double` / `double` | 覆盖系统字号缩放 |
| `emojiFont` | `({String family, Pattern pattern})?` | 让 emoji 用指定字体（`EmojiText` 用） |
| `localizationsDelegates` | `Iterable<LocalizationsDelegate<dynamic>>?` | **必须**含一个 `UiLocalizations` 的 delegate，否则 `showSheet` 等直接 assert 崩，见 §10 坑 2 |
| `onGenerateRoute` | `RouteFactory?` | 和 MaterialApp 一样 |
| `debugShowCheckedModeBanner` | `bool` | 同 Material |

**PrismApp 内部替你做了**（`app.dart:113-185`）：`Theme` → `DefaultSelectionStyle`（选中色 = `textSelectionColorOf(scheme)`，光标 = `primary`）→ `ThemeCrossFade`（明暗切换淡入淡出）→ `MeasureScope`（文本测量缓存）→ `LiquidGlassScope` → `BannerHost` → `RemoteFocusAdapter` → `WidgetsApp` + `Overlay`，并且 **所有 pushed route 都是 `CardPageRoute`**（卡片式转场）。

**PrismApp 没有替你做的**：`ViewScope`（→ `AppBar`/`ScaffoldBar`/`showSheet` 全部 assert 失败）、`UiLocalizations`、`GooSurface`。

### 1.2 `Theme` / `ThemeData`（**同名不同库**）

```dart
// lib/theme.dart 只有两个 ButtonTheme 包装类：MinFilledButtonTheme、MinIconButtonTheme
// 真正的 Theme / ThemeData 在 lib/theme_data.dart

class Theme extends StatelessWidget {
  const Theme({super.key, required this.data, required this.child});
  final ThemeData data;
  final Widget child;
  static ThemeData of(BuildContext context);        // 永远不返回 null
  static Brightness brightnessOf(BuildContext context);
}

class ThemeData {
  factory ThemeData({
    ColorScheme? colorScheme,
    Brightness? brightness,                 // 不给 colorScheme 时用它挑默认 scheme（seed 0xFF6750A4 + soft）
    TargetPlatform? platform,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    VisualDensity? visualDensity,           // 桌面默认 compact
    TapTargetSize? tapTargetSize,           // 桌面默认 shrinkWrap
    Color? scaffoldBackgroundColor,         // 默认 SurfaceLevel.page.colorOf(scheme)
    ColorScheme? elevatedColorScheme,       // ★ 只给暗色用：sheet 抬一级
  });

  ThemeData copyWith({...同参数...});

  final ColorScheme colorScheme;
  final TargetPlatform platform;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final VisualDensity visualDensity;
  final TapTargetSize tapTargetSize;
  final Color scaffoldBackgroundColor;
  final ColorScheme? elevatedColorScheme;
  Brightness get brightness;
  IconThemeData get iconTheme;
  TextStyle get displayTextStyle;   // ≥ title3 的基准
  TextStyle get bodyTextStyle;      // < title3 的基准
  static Brightness estimateBrightnessForColor(Color color);
}
```

配套常量 / 工具：

```dart
const double kMinInteractiveDimension = 48.0;
const Duration kThemeAnimationDuration = Duration(milliseconds: 200);
enum ThemeMode { system, light, dark }
enum TapTargetSize { padded, shrinkWrap }
abstract final class Colors { transparent; black; black54; white; }   // 只有 4 个
abstract final class Easing { emphasizedDecelerate; legacyDecelerate; standard; standardAccelerate; standardDecelerate; }
class VisualDensity { const VisualDensity({this.horizontal = 0, this.vertical = 0}); static const standard; static const compact; }
({String family, List<String>? fallback}) systemFontOf(TargetPlatform platform, {bool display = false});
List<String> appFontFamilyFallback({required TargetPlatform platform, required Iterable<Locale> locales, String? fontFamily});  // lib/font.dart：自动挑中文字形
```

### 1.3 明暗两套主题的标准写法

```dart
ThemeData themeOf(Brightness brightness) {
  var scheme = seededColorScheme(
    seedColor: seed,
    brightness: brightness,
    style: colorStyle,              // ColorStyle.vivid / tinted / soft / monochrome
  );
  if (brightness == Brightness.dark && pureBlack) {
    scheme = scheme.toPureBlack(true);   // 纯黑模式（只在 dark 生效）
  }
  return ThemeData(
    colorScheme: scheme,
    fontFamily: fontFamily,
    fontFamilyFallback: appFontFamilyFallback(
      platform: defaultTargetPlatform,
      locales: locales,
      fontFamily: fontFamily,
    ),
    // ★ 只有暗色需要：sheet 呈现时把每一级表面抬一级
    elevatedColorScheme: brightness == Brightness.dark ? scheme.elevated : null,
  );
}
```

> FlClash 原文见 `lib/manager/theme_manager.dart:39-50`、`lib/providers/state/theme.dart:82-89`。
> `ThemeData` 一旦颜色变了就是**不相等**的新对象，`ThemeCrossFade` 靠这个做明暗过渡——不要在 build 里无脑 `ThemeData(...)`，要缓存（FlClash 用 `_appThemes` map）。

### 1.4 路由

```dart
// lib/navigator.dart
class BaseNavigator { /* static push(context, page) 等工具 */ }
class RootPage<T> extends Page<T> { ... }
class FadePageRoute<T> extends PageRoute<T> { ... }
class CardPageRoute<T> extends PageRoute<T> { ... }   // PrismApp 默认的 pageRouteBuilder

// lib/page_transition.dart
class HomeRoute<T> extends PageRoute<T> with CardRouteMixin<T> { ... }
mixin CardRouteMixin<T> on ModalRoute<T> { ... }
```

`Navigator.of(context).push(...)` 用标准 PageRoute / 上面的 `HomeRoute` 即可，不要用 `MaterialPageRoute`。

---

## 2. 颜色

### 2.1 `seededColorScheme` —— 唯一正确的建色入口

`lib/color.dart:27`

```dart
ColorScheme seededColorScheme({
  required Color seedColor,
  required Brightness brightness,        // ★ 必填，没有默认值
  ColorStyle style = ColorStyle.vivid,
})
```

`ColorScheme.fromSeed` 也存在（`color_scheme.dart:8`），只是转到上面这个：

```dart
factory ColorScheme.fromSeed({
  required Color seedColor,
  Brightness brightness = Brightness.light,
  ColorStyle style = ColorStyle.soft,
});
static ColorScheme of(BuildContext context);   // = Theme.of(context).colorScheme
```

### 2.2 `ColorStyle` 枚举（4 个，**不是** Material 的 9 个 Variant）

`lib/color.dart:12`

```dart
enum ColorStyle {
  vivid,        // Material variant = content。primary = 种子色本身。表面近灰。
  tinted,       // Material variant = content。表面染上种子色相，chroma 上限 10。
  soft,         // Material variant = tonalSpot。primary = Material 算出来的（偏淡）。表面近灰。
  monochrome,   // Material variant = monochrome。primary = 黑或白。全灰。
}
```

| 值 | Material Variant | primary | 表面 | 什么时候用 |
|---|---|---|---|---|
| `vivid` | `content` | **就是你给的 seed**（亮色 tone 夹在 35–60，暗色 +3 夹在 50–75） | 近灰（chroma ≤ 3） | 默认首选，FlClash 默认 |
| `tinted` | `content` | seed 本身 | seed 色相、chroma ≤ 10 的淡染 | 想要「整页带一点点品牌色」 |
| `soft` | `tonalSpot` | Material 算的，偏淡 | 近灰 | 不想要品牌色的强存在 |
| `monochrome` | `monochrome` | 黑/白 | 灰 | 极简 / 无障碍 |

### 2.3 `ColorScheme` 的角色：核心在 `color_scheme.dart`，状态色在 `color.dart` 的 extension

`ColorScheme` 是 prism_ui 自己实现的（729 行）。**所有非 required 角色都是 nullable 入口 + 带 fallback 的 getter**——即你只给一部分也能用，缺的会退回到一个合理值（例：`onSurfaceVariant` 缺省 = `onSurface`，`outline` 缺省 = `onSurface`）。

```dart
const ColorScheme({
  required this.brightness, required this.primary, required this.onPrimary,
  Color? primaryContainer, Color? onPrimaryContainer, Color? primaryFixed, ...
  required this.secondary, required this.onSecondary,
  Color? secondaryContainer, ... 
  Color? tertiary, Color? onTertiary, Color? tertiaryContainer, ...
  required this.error, required this.onError, Color? errorContainer, Color? onErrorContainer,
  required this.surface, required this.onSurface,
  Color? surfaceDim, Color? surfaceBright,
  Color? surfaceContainerLowest, Color? surfaceContainerLow, Color? surfaceContainer,
  Color? surfaceContainerHigh, Color? surfaceContainerHighest,
  Color? onSurfaceVariant, Color? outline, Color? outlineVariant,
  Color? shadow, Color? scrim, Color? inverseSurface, Color? onInverseSurface,
  Color? inversePrimary, Color? surfaceTint,
});
const ColorScheme.light({...});     // 老 M2 默认值
const ColorScheme.dark({...});
ColorScheme copyWith({...});
static ColorScheme lerp(ColorScheme a, ColorScheme b, double t);
```

**❌ `success` / `warning` / `destructive` / `delayColor` / `chromeSurface` 不在 `ColorScheme` 类里**，它们是 **extension**：

```dart
// lib/color.dart:304  extension ColorSchemeExtension on ColorScheme
ColorScheme toPureBlack(bool isPureBlack);
Color get modalScrim;        // = alertScrim
Color get alertScrim;        // scrim @ 0.48(dark) / 0.20(light)
Color get destructive;       // iOS systemRed：#FF383C(light) / #FF4245(dark)  ← 删除用这个，不是 error
Color get success;           // 固定绿 0xFF4CAF50，tone 40/80
Color get onSuccess;
Color get successContainer;  // tone 90/30，chroma 夹 16
Color get onSuccessContainer;
Color get warning;           // 固定橙 0xFFFF9800，tone 40/80
Color get onWarning;
Color get warningContainer;
Color get onWarningContainer;

// lib/surface.dart:69  extension ChromeSurfaceExt on ColorScheme
Color get chromeSurface;     // 侧栏/标题栏=窗口 chrome：亮 surfaceContainerHighest / 暗 surfaceContainerLow

// lib/surface.dart:75  extension ElevatedSurfaceExt on ColorScheme
ColorScheme get elevated;    // 暗色专用：每级 +1（surface→surfaceContainer，…）

// lib/surface.dart:120 extension AppSurfaceThemeExt on ThemeData
ThemeData get elevated;      // 用 elevatedColorScheme 换掉 colorScheme

// lib/color.dart:242  extension ColorExtension on Color
Color get opacity80, opacity60, opacity50, opacity38, opacity30, opacity15, opacity12, opacity10, opacity0;
double get tone;                       // HCT tone
Color shiftTone(double delta);
String get hex;                        // '#RRGGBB'
```

`delayColor` **不存在于 prism_ui**，是 FlClash 自己 11 行扩展（`Q:\ref\FlClash\lib\ui\delay_color.dart`）：

```dart
extension DelayColorScheme on ColorScheme {
  Color? delayColor(int? delay) {
    if (delay == null) return null;
    if (delay < 0) return error;
    if (delay < 600) return success;
    return warning;
  }
}
```

### 2.4 状态色用法（来自 surfaces.md）

```dart
// 文字/图标：直接给颜色
Text('128 ms', style: style.copyWith(color: context.colorScheme.success));

// 小 chip：容器色 + on 色
TonalChip(
  label: '128 ms',
  color: scheme.successContainer,
  foregroundColor: scheme.onSuccessContainer,
);

// 整块填充（很少用）：fill = success，前景 = onSuccess（不要用 onSuccessContainer）
Text('OK', style: TextStyle(color: scheme.onSuccess));   // 在 success 底色上

// 错误：容器色填充，不要描边
Card(isError: true, child: ...);          // 内部用 errorContainer + onErrorContainer

// 删除确认：destructive，不是 error
AlertDialog(title: '删除？', destructive: true, actions: [TextButton(...), TextButton(...)]);
```

---

## 3. 表面层级（Surface Level）

### 3.1 `SurfaceLevel`

`lib/surface.dart:10`

```dart
enum SurfaceLevel {
  page,
  card,
  block,
  inset;

  static SurfaceLevel floatingOf(ColorScheme colorScheme);  // 亮=card，暗=block（浮层用）
  SurfaceLevel get next;                                    // page→card→block→inset→inset
  Color colorOf(ColorScheme colorScheme);
}
```

| 级别 | 亮色 | 暗色 | 承载什么 |
|---|---|---|---|
| `page` | `surfaceContainer` | `surface` | 页面 body、sheet |
| `card` | `surfaceBright` | `surfaceContainer` | Card、成组的行、亮色下的浮层 |
| `block` | `surfaceContainer` | `surfaceContainerHigh` | 卡片内的未选中 segment / tile / 井 |
| `inset` | `surfaceContainerHighest` | `surfaceContainerHighest` | block 里的小标记：glyph 井、badge、轨道 |

### 3.2 `SurfaceScope` + context 扩展

```dart
class SurfaceScope extends StatelessWidget {
  const SurfaceScope({super.key, required this.level, required this.child});
  final SurfaceLevel level;
  final Widget child;
  static SurfaceLevel of(BuildContext context);   // 没有祖先时返回 page（安全）
}

// lib/surface.dart:63  extension SurfaceContext on BuildContext
SurfaceLevel get surfaceLevel;         // = SurfaceScope.of(this)
SurfaceLevel get raisedSurfaceLevel;   // = surfaceLevel.next  ★ 组件该用的那个
```

### 3.3 用法铁律

```dart
// ✅ 组件内部：读「上一层」
final level = context.raisedSurfaceLevel;
final fill = level.colorOf(context.colorScheme);

// ✅ 自己造一个表面时，把 level 传给子树
PressSurface(
  fill: level.colorOf(scheme),
  shape: AppShape.all(AppCorner.md),
  child: SurfaceScope(level: level, child: child),   // ★ 别忘了这行
);

// ❌ 你绝对不该写的
final fill = isInBottomSheet ? Colors.white : Colors.grey;   // 按位置分支取色 = 规范明令禁止的 bug
final fill = SurfaceLevel.card.colorOf(scheme);              // 在调用点硬编码级别
```

- `Card` 已经替你做了这两件事（`card.dart:200,227`），所以在 `Card` 里的 `Card` 会自动更亮一级。
- 浮层（dialog / popup / dock / banner / toast）用 `SurfaceLevel.floatingOf(scheme)`。

### 3.4 暗色 sheet 抬一级

```dart
// ThemeData 里给 elevatedColorScheme（§1.3），sheet route 自己会用 ElevatedSurfaceTheme 套上。
class ElevatedSurfaceTheme extends StatelessWidget {
  const ElevatedSurfaceTheme({super.key, required this.child});
  static bool isIn(BuildContext context);
}
```

### 3.5 `Surface`（底层原语）

```dart
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    this.color = const Color(0x00000000),
    this.shape,
    this.clipBehavior = Clip.none,
    this.elevation = 0,
    this.shadowColor,
    this.textStyle,                   // ★ 默认 AppTextStyle.subheadline
    required this.child,
  });
  const Surface.transparent({        // 只画 shape 的边，命中穿透
    super.key, this.shape, this.clipBehavior = Clip.none, this.textStyle, required this.child,
  });
}
```

`Surface` 的关键副作用：**它给子树设了 `DefaultTextStyle = AppTextStyle.subheadline.of(context)`**。所以裸 `Text()` 放在任何 `Surface`/`Card`/`ListRow` 槽位里自带正确字号与颜色。

### 3.6 焦点环

```dart
BorderSide focusRingSide(ColorScheme colorScheme, {bool standsOff = false});   // 2dp primary
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.shape, this.standsOff = false, required this.child});
}
```

---

## 4. 形状 token

`lib/shape.dart`

### 4.1 `AppCorner`（double）与「最短边」规则

```dart
abstract final class AppCorner {
  static const double none = 0;
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 16;
  static const double lg   = 20;
  static const double xl   = 24;
  static const double xxl  = 28;
  static const double alert = 34;    // iOS 27 UIAlertController，比 sheet 更圆
  static const double full = 1000;

  static double fit(double shortestSide);   // 取 ≤ shortestSide/3 的最大 token
}
```

| token | 值 | 适用最短边 | 用在哪 |
|---|---|---|---|
| `none` | 0 | — | 方角；成组列表的平边 |
| `xs` | 4 | — | 已被圆角裁过的表面内部的小 block / tile |
| `sm` | 8 | 到 48 | chip、thumb、色块、小方 tile、`TonalChip` |
| `md` | 16 | 到 64 | 交互 chrome：输入框、菜单、按钮、弹层 |
| `lg` | 20 | 64–180 | 中等卡片：dashboard tile、proxy 节点卡 |
| `xl` | 24 | 全宽 | 任何通栏：列表行、成组列表、组头 |
| `xxl` | 28 | > 200 | sheet、全屏容器 |
| `alert` | 34 | — | 只有 `AppCorner` 有，传给 builder 用（alert / form sheet） |
| `full` | 1000 | — | 药丸/圆：按钮、轨道、指示器、进度、头像 |

**规则**：圆角按**组件最短边**取 token；尺寸来自 `LayoutBuilder` 或随字号变化时用 `AppCorner.fit(shortestSide)`；全宽表面固定用 `xl` 且**不**用 `fit()`（规格里唯一刻意超出一三分规矩的地方）。

### 4.2 `AppRadius`（BorderRadius）

```dart
abstract final class AppRadius {
  static const BorderRadius none, xs, sm, md, lg, xl, xxl, full;   // 与 AppCorner 一一对应
  static BorderRadius all(double corner);
  static BorderRadius top(double corner);
  static BorderRadius vertical({double top = AppCorner.none, double bottom = AppCorner.none});
}
```

### 4.3 `AppShape`（RoundedSuperellipseBorder，超椭圆/连续圆角）

```dart
abstract final class AppShape {
  static const RoundedSuperellipseBorder none, xs, sm, md, lg, xl, xxl, full;
  static const CircleBorder circle;
  static const AppInputBorder input;

  static RoundedSuperellipseBorder all(double corner);
  static RoundedSuperellipseBorder top(double corner);
  static RoundedSuperellipseBorder vertical({double top = AppCorner.none, double bottom = AppCorner.none});
  static RoundedSuperellipseBorder of(BorderRadius borderRadius);
}
```

- **药丸一律 `AppShape.full`，永远不要 `StadiumBorder`。**
- 圆角是超椭圆（superellipse），不是普通 `RoundedRectangleBorder`；这就是「iOS 连续圆角」的来源。
- 输入框的 `border`/`focusedBorder` **不要设**，保持默认 `AppShape.input`（`AppInputBorder`），它会把浮动 label 的缺口一起画出来。

### 4.4 调用模板

```dart
SizedBox(
  height: 44,
  child: Card(
    shape: AppShape.full,                         // 药丸
    child: ListRow(title: Text('一行')),
  ),
)

LayoutBuilder(builder: (_, c) {
  final r = AppCorner.fit(c.maxHeight);           // 随尺寸自适应
  return Card(radius: r, child: ...);
})

// 成组列表里的行（配合 ItemPosition）：别自己算，用现成的
Card(shape: AppShape.of(listItemRadiusOf(position)), ...);   // lib/list_selected.dart:6
```

---

## 5. 字体 / 文本

### 5.1 `AppTextStyle`（13 个命名样式，iOS Dynamic Type）

`lib/typography.dart:7`

```dart
enum AppTextStyle {
  display(40, 44, emphasizedWeight: FontWeight.w700),
  largeTitle(34, 41, emphasizedWeight: FontWeight.w700),
  title1(28, 34, emphasizedWeight: FontWeight.w700),
  pageTitle(24, 30, weight: FontWeight.w600, emphasizedWeight: FontWeight.w700),
  title2(22, 28, emphasizedWeight: FontWeight.w700),
  title3(20, 25),
  headline(17, 22, weight: FontWeight.w600),
  body(17, 22),
  callout(16, 21),
  subheadline(15, 20),
  footnote(13, 18),
  caption1(12, 16),
  caption2(11, 13);

  const AppTextStyle(this.size, this.leading, {this.weight = FontWeight.w400, this.emphasizedWeight = FontWeight.w600});

  final double size;
  final double leading;
  final FontWeight weight;
  final FontWeight emphasizedWeight;

  TextStyle of(BuildContext context, {bool emphasized = false});   // ★ 唯一正确取法

  static const TextStyle emphasis;    // TextStyle(fontWeight: FontWeight.w600)，用于 TextSpan
  static TextStyle custom(BuildContext context, {required double size, required double leading, FontWeight weight = FontWeight.w400});
}
```

`pageTitle` 和 `display` 是 prism_ui 加的两级（Material / iOS 都没有）。

```dart
// ✅
Text('标题', style: AppTextStyle.title3.of(context));
Text('值', style: AppTextStyle.body.of(context, emphasized: true));
TextSpan(text: ' 已连接', style: AppTextStyle.emphasis);            // 不用给字号

// ❌ 规范禁止
Text('标题', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600));
```

`context` 上的现成组合（`lib/context.dart:55`）：

```dart
TextStyle get listTitleStyle;      // body + onSurface       —— 列表行主标题
TextStyle get listSubtitleStyle;   // subheadline + onSurfaceVariant
TextStyle get listCaptionStyle;    // footnote + onSurfaceVariant
TextStyle get cardHeaderStyle;     // headline + onSurfaceVariant@80%
```

`TextStyle` 扩展（`lib/text_style.dart`）：

```dart
extension TextStyleExtension on TextStyle {
  TextStyle get toLight;     // color @80%
  TextStyle get toLighter;   // color @60%
  TextStyle get toTabular;   // tabularFigures（数字对齐，延迟/流量必用）
}
```

### 5.2 `Text` 组件 —— ❗ prism_ui **没有**自己的 `Text`

`lib/text.dart` 里没有 `Text` 类。**用 `flutter/widgets.dart` 的 `Text`**（它在 widgets 层，不是 material）。`text.dart` 提供 5 个辅助件：

```dart
/// [text]，被截断时给它整个字符串的 tooltip（长按触发）
class TooltipText extends StatefulWidget {
  final Text text;
  const TooltipText({super.key, required this.text});
}

/// 只在指针 hover 时出现的 tooltip（触摸没有 hover，长按留给行的右键菜单）
class HoverTooltip extends StatefulWidget {
  const HoverTooltip({super.key, required this.message, required this.child});
}

/// 单行/多行省略 + 溢出时 tooltip，最常用
class TooltipLabel extends StatelessWidget {
  const TooltipLabel(this.text, {super.key, this.style, this.maxLines = 2});
}

/// emoji 字体作用域
class EmojiFont extends InheritedWidget {
  const EmojiFont({super.key, required this.family, required this.pattern, required super.child});
  static EmojiFont? of(BuildContext context);
}

/// 会按 [EmojiFont] 拆 span 的 Text
class EmojiText extends StatelessWidget {
  const EmojiText(this.text, {super.key, this.maxLines, this.overflow, this.style});
  static double widthOf(BuildContext context, String text, TextStyle style);
}
```

写法对照：

```dart
// 裸 Text —— 在 Surface / Card / ListRow 槽位里自动拿到 subheadline 与颜色
Card(child: Text('设置'))

// 需要指定样式
Text('设置', style: AppTextStyle.body.of(context))

// 长文本会溢出 —— 用 TooltipLabel（省略号 + 溢出时 tooltip）
TooltipLabel('com.example.very.long.profile.name', maxLines: 1)

// 单行标题、需要 tooltip 但样式已知
TooltipText(text: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.listTitleStyle))

// 数字列（延迟、流量、时间）
Text('1.24 GB', style: AppTextStyle.body.of(context).toTabular)

// emoji 混排（国旗、地区标记）
EmojiText('🇭🇰 香港', style: AppTextStyle.body.of(context))
```

> 必读：`Surface` / `Card` / `ListRow` / `AppBar` / `AlertDialog` 都会设 `DefaultTextStyle`，所以**裸 `Text()` 在槽位里是正确做法**；只有你要不同字号时才显式给 `style`。

---

## 6. 核心组件速查

> 每条格式：**签名 → 最小可用片段 → 注意**。
> 找不到的组件标 ❌，并给真实替代。

### 6.1 表面 / 按压

#### `Card` ✅

```dart
// lib/card.dart:108
const Card({
  super.key,
  bool? isSelected,                    // 默认 false；只影响无障碍语义，除非同时 fillsSelection
  this.onPressed,                      // null = 禁用（内容变 38% 透明）
  this.radius,                         // 与 shape 二选一；默认 AppCorner.md
  this.padding,                        // 默认 EdgeInsets.zero
  this.enterAnimated = false,          // 出现时淡入放大
  this.shape,                          // OutlinedBorder?，比 radius 优先
  this.isError = false,                // errorContainer 填充 + error 光环
  this.enterActionsOnRight = false,    // 方向键 → 进入卡片内按钮
  this.statesController,
  this.inert = false,                  // 忽略按压（但保持可用颜色），切换时不动画
  this.fillsSelection = false,         // ★ 选中时真的用 primary 填充（segment/chip 用）
  required this.child,
});

// 静态工具
static BoxConstraints minimumOf(BuildContext context);
static EdgeInsets paddingOf(BuildContext context, EdgeInsets padding);
```

```dart
// 可点击卡片（列表行 / 设置行 / 仪表盘卡）
Card(
  onPressed: () => open(),
  padding: const EdgeInsets.all(16),
  child: ListRow(
    leading: GlyphIcon(Glyphs.settings),
    title: const Text('设置'),
    trailing: const GlyphIcon(Glyphs.chevronForward, size: 18),
  ),
)

// 选中的段/选项（唯一允许 primary 填充的场景）
Card(
  isSelected: isChosen,
  fillsSelection: true,
  shape: AppShape.full,
  onPressed: () => choose(mode),
  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text(label)),
)

// 错误行
Card(isError: true, child: ListRow(title: Text('证书无效')))
```

#### `PressSurface` + `PressLook` ✅

```dart
// lib/card_surface.dart:10
enum PressLook {
  ink,    // 内容色 @10% 状态层（Material InkWell 那种），Android 上额外有 sparkle
  tint,   // 整块变亮/变暗（iOS 按钮）
  none,   // 什么都不显示（把按压留给 ElasticPress 的膨胀）
}

// lib/press_surface.dart:16
const PressSurface({
  super.key,
  required this.fill,                  // Color（不能用 null！）
  required this.shape,                 // OutlinedBorder
  this.look = PressLook.ink,
  this.side = BorderSide.none,
  this.ringColor,
  this.ringStandsOff = false,
  this.foreground,                     // 会同时给图标和 textStyle 上色
  this.inkColor,                       // ink 的内容色（默认 onSurface）
  this.iconSize,
  this.textStyle,
  this.padding = EdgeInsets.zero,
  this.minimum = const BoxConstraints(),
  this.tapTarget = Size.zero,
  this.onPressed,
  this.inert = false,
  this.selected = false,
  this.statesController,
  this.reportsHover = false,
  this.showsHover = true,
  this.onKeyEvent,
  this.childFills = false,
  this.clipsChild = false,
  required this.child,
});
```

```dart
// 「不是 Card 的一行」——记录行、请求行、裸列表项
PressSurface(
  fill: Color(0x00000000),                 // 透明：这行没有填充
  shape: AppShape.all(AppCorner.md),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  onPressed: onTap,
  child: ListRow(title: Text(title), subtitle: Text(subtitle)),
)
```

**`PressSurface` 自带**：按下 ink/tint、hover 4% 覆盖、键盘/遥控焦点环、fill 变化的 200ms 缓动、Android sparkle。
**不需要** Material 的 `InkWell` / `Material` / `Ink`。

#### `PressRegion`（非表面类可点击）✅

```dart
const PressRegion({
  super.key,
  this.onTap, this.onHover, this.onPressedChanged, this.onFocusChange,
  this.shape, this.fill, this.overlay, this.hoverColor,
  this.canRequestFocus = true, this.excludeFromSemantics = false,
  this.enableFeedback = true, this.mouseCursor,
  required this.child,
});
```

#### `ElasticPress` / `ElasticButton` ✅（app bar 按钮的「膨胀」手感）

```dart
const ElasticPress({super.key, this.enabled = true, this.pullPastEdges = false, this.maxGrowth = _maxPressGrowth, this.maxPull, this.panelOf, required this.child});
const ElasticButton({super.key, this.enabled = true, required this.child});   // = ElasticPress + PressLook.none
```

```dart
ElasticPress(child: IconButton(tooltip: '刷新', icon: const GlyphIcon(Glyphs.search), onPressed: reload))
```

#### `CardSurface`（最底层 render object，一般不用）

```dart
const CardSurface({
  super.key, required this.shape, required this.fill, required this.previousFill,
  required this.side, required this.previousSide, required this.transition,
  required this.pressed, this.hover, this.sparkles, this.inkColor,
  required this.look, required this.brightness, required this.padding,
  required this.minimum, required this.tapTarget, required this.interactive,
  ... required this.child,
});
```

### 6.2 行 / 列表

#### `ListRow`（= Material `ListTile` 的几何，但**不含** ink/焦点/语义）✅

`lib/list_row.dart:16`

```dart
enum ListRowAlignment { center, top }

const ListRow({
  super.key,
  this.leading,
  required this.title,
  this.subtitle,
  this.trailing,
  this.padding = const EdgeInsets.symmetric(horizontal: 16),
  this.horizontalTitleGap,                 // 默认 16
  this.minVerticalPadding = listRowVerticalPadding,   // = 10
  this.minHeight = listRowMinHeight,                  // = 56
  this.alignment = ListRowAlignment.center,
});
```

`ListRow` **必须**被包在 `Card` / `PressSurface` / `DecorationListItem` 里才可点击。

```dart
// 两行列表项
Card(
  padding: EdgeInsets.zero,
  onPressed: onTap,
  child: ListRow(
    leading: GlyphIcon(AppGlyphs.dns, color: scheme.onSurfaceVariant),
    title: Text('DNS'),
    subtitle: Text('223.5.5.5'),
    trailing: const GlyphIcon(Glyphs.chevronForward, size: 18),
  ),
)
```

#### `ListRowSeparator` ❌ **不存在**

真实情况：`lib/list_row_separator.dart` 里是 **private** 的 `_ListRowSeparator`（`part of 'list.dart'`），只能通过 `DecorationListItem` 自动获得；它会在两侧行被高亮时**自动隐藏**那条发丝线。公开替代：

- 成组列表 → 用 `DecorationListItem`（自动带分隔线 + 首尾圆角）
- 任意位置的分隔 → `Divider()`（见 6.7）
- `PrismListView` **没有** `.separated` 构造；想要间隙用 `gap:` 参数

#### `DecorationListItem`（成组列表的一行，**最常用**）✅

`lib/list_selected.dart:15`

```dart
const DecorationListItem({
  super.key,
  this.contentPadding,
  required this.title,
  this.leading,
  this.trailing,
  this.subtitle,
  this.isSelected,
  this.onPressed,
  this.horizontalTitleGap,
  this.minVerticalPadding,
  this.invalid = false,      // 错误态：errorContainer
});

// 带圆形勾选框的编辑态行
const SelectedDecorationListItem({
  super.key,
  required this.isSelected,
  required this.onSelected,
  this.horizontalTitleGap,
  this.isEditing = false,
  this.invalid = false,
  required this.title,
  required this.onPressed,
  this.minVerticalPadding,
  this.subtitle,
  this.leading,
});

BorderRadius listItemRadiusOf(ItemPosition? position);   // 成组列表首尾圆角（xl）
```

```dart
// 一组成组列表（iOS inset grouped 样式）
DecorationListItem(title: Text('开机自启'), trailing: Switch(value: v, onChanged: onV), onPressed: toggle)
DecorationListItem(title: Text('自动更新'), onPressed: openUpdate, trailing: const DisclosureIndicator())

// 单选列表 + 勾
SelectedDecorationListItem(isSelected: picked, onSelected: pick, title: Text(name), onPressed: pick)
```

#### 列表头 / 尾 / 分组

`lib/list.dart`

```dart
const ListHeader({
  super.key,
  required this.title,
  this.caption,
  this.padding,
  this.actions = const [],        // List<IconButtonData>，1 个=单独；2 个=TonalButtonGroup
  this.trailing,
});

const ListFooter({super.key, required this.text});
const ListSectionGap({super.key});

Widget generateGroup(Iterable<Widget> items);
Widget generateSection({String? title, required Iterable<Widget> items, List<IconButtonData> actions = const [], String? footer});
Widget generateSliverSection<T>({
  String? title,
  required List<T> items,
  required Widget Function(T item) itemBuilder,
  List<IconButtonData> actions = const [],
  String? footer,
});
```

```dart
// 最省事的整页列表
ListView(   // 或 CustomScrollView
  children: [
    ListHeader(title: '通用', actions: [
      IconButtonData(glyph: AppGlyphs.add, tooltip: '新增', onPressed: add),
    ]),
    generateGroup([
      DecorationListItem(title: const Text('外观'), onPressed: () {}),
      DecorationListItem(title: const Text('语言'), onPressed: () {}),
    ]),
    const ListFooter(text: '修改立即生效'),
  ],
)
```

#### `PrismListView` / `SliverPrismList`（懒构建，带「远距离跳转不逐行测量」）✅

`lib/prism_list.dart`

```dart
const SliverPrismList({
  super.key,
  required this.itemCount,
  required this.itemBuilder,
  this.gap = 0,
  this.itemExtent,
  this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,  // 64
  this.findChildIndexCallback,
  this.listController,               // ListController（来自 super_sliver_list）
  this.addRepaintBoundaries = true,
  this.anchorAtEnd = false,          // 聊天/trace 那种贴底列表
});

const PrismListView({
  super.key,
  super.scrollDirection, super.reverse, super.controller, super.primary,
  super.physics, super.shrinkWrap, super.padding, super.scrollCacheExtent,
  super.keyboardDismissBehavior, super.clipBehavior,
  required this.itemCount,
  required this.itemBuilder,
  this.gap = 0,
  this.itemExtent,
  this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
  this.findChildIndexCallback,
  this.listController,
  this.addRepaintBoundaries = true,
  this.anchorAtEnd = false,
});
// 注意：PrismListView 没有 ListView.separated；行间距离用 gap:
```

```dart
PrismListView(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  itemCount: records.length,
  gap: 8,
  itemBuilder: (_, i) => RecordCard(record: records[i]),
)

// 放进 CustomScrollView
CustomScrollView(slivers: [
  SliverPadding(
    padding: const EdgeInsets.all(16),
    sliver: SliverPrismList(itemCount: n, itemBuilder: (_, i) => ..., gap: 8),
  ),
])
```

#### 可重排列表

```dart
class SliverPrismReorderableList extends SliverReorderableList { ... }
const PrismReorderableListView({
  super.key, required this.itemCount, required this.itemBuilder,
  required this.onReorderItem, required this.proxyDecorator,
  this.header, this.footer, this.itemExtent,
  this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
  this.controller, this.padding, this.scrollCacheExtent,
});
```

#### 排序 / 展开指示

`lib/sortable.dart`

```dart
const ReorderDragStartListener({super.key, required this.index, this.enabled = true, required this.child});
class SortModeScope extends InheritedWidget { const SortModeScope({super.key, required this.sorting, required super.child}); static SortModeScope? maybeOf(BuildContext); }
const SortHandle({super.key, required this.index});
const SortableItem({super.key, required this.index, required this.child});
static SortableItemData? SortableItem.maybeOf(BuildContext context);   // ({int index, bool sorting})?
const SortableTrailing({super.key, required this.item, required this.child});
const DisclosureIndicator({super.key});                 // 标准的「>」尾标，48dp 盒
const DetailButton({super.key, required this.glyph, required this.tooltip, required this.onPressed});  // 行尾按钮，与 DisclosureIndicator 对齐

// lib/effect.dart
const ExpandIcon({super.key, this.expand = false});     // 旋转 180° 的展开箭头
```

#### 滚动条

`lib/scroll.dart`

```dart
const Scrollbar({
  super.key, required this.child, required this.controller,
  this.thumbVisibility = false, this.padding = EdgeInsets.zero, this.onScrub,
});
const Scrollbar.ambient({super.key, required this.child, required this.controller, this.padding = EdgeInsets.zero});

const FloatingScrollbar({
  super.key, required this.controller, required this.hintBuilder,
  this.thumbVisibility = false, required this.child,
});   // 拖动时浮出 pill 提示（hintBuilder 返回文案）

const ScrollToEndBox({
  super.key, required this.child, required this.controller,
  this.onCancelToEnd, this.onResumeToEnd, this.enable = true,
});
```

> `PrismApp` 已经装了 `BaseScrollBehavior`，所以 `CustomScrollView`/`ListView` 自带 prism 风格的滚动条（桌面）。想自定义再用上面这些。

### 6.3 选择标记

`lib/selection_mark.dart` —— 规范要求「选中 = 保留填充 + 一个 primary 标记」，**不是**填充变色。

```dart
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({super.key});
  static const size = 24.0;              // primary 色的 check 勾
}

class SelectionBadge extends StatelessWidget {
  const SelectionBadge({super.key, this.size = 22, this.glyph = Glyphs.check, this.tonal = false});
  // tonal: primary@14% 底 + primary 勾；非 tonal: primary 填充 + onPrimary 勾
}
```

> ⚠️ `surfaces.md` 提到 `SelectionBadge.preferred`，**源码里没有这个构造**（只有默认构造 + 3 个具名参数）。要「pin 住的首选节点」标记，自己传 `glyph: AppGlyphs.pin` + `tonal: true`。

```dart
// 成组列表里的一行：勾在行尾（不是整行染色）
DecorationListItem(
  title: Text(name),
  isSelected: isPicked,
  onPressed: pick,
  trailing: isPicked ? const SelectionCheck() : null,
)

// 独立卡片 / 网格 tile：用 badge
Card(
  onPressed: pick,
  child: Stack(children: [
    content,
    if (isPicked) const Positioned(top: 8, right: 8, child: SelectionBadge()),
  ]),
)
```

### 6.4 按钮

`lib/common_button.dart` —— **名字和 Material 一样，但是另一个类**（`ElevatedButton` 没有对应物）。

```dart
const IconButton({
  super.key,
  required this.onPressed,          // null = 禁用
  required this.icon,               // Widget
  this.selectedIcon,
  this.isSelected,
  this.tooltip,                     // ★ 桌面 hover 提示，建议总是给
  this.iconSize,
  this.padding,
  this.style,                       // ButtonStyle?
});
const IconButton.filled({...同上但无 selectedIcon/isSelected...});

const TextButton({super.key, required super.onPressed, super.style, required super.child});
const TextButton.icon({super.key, required super.onPressed, super.style, required super.icon, required super.label});

const FilledButton({super.key, required super.onPressed, super.style, required super.child});
const FilledButton.icon({super.key, required super.onPressed, super.style, required super.icon, required super.label});

const OutlinedButton({super.key, required super.onPressed, super.style, required super.child});
const OutlinedButton.icon({...});

class ButtonStyle {
  const ButtonStyle({
    this.foregroundColor, this.backgroundColor, this.overlayColor, this.textStyle,
    this.side, this.shape, this.padding, this.minimumSize, this.fixedSize,
    this.maximumSize, this.iconSize, this.visualDensity, this.tapTargetSize,
    this.backgroundBuilder, this.pressLook, this.ringStandsOff,
  });
  factory ButtonStyle.from({
    Color? foregroundColor, Color? disabledForegroundColor,
    Color? backgroundColor, Color? disabledBackgroundColor,
    TextStyle? textStyle, OutlinedBorder? shape, EdgeInsetsGeometry? padding,
    Size? minimumSize, Size? fixedSize, Size? maximumSize, double? iconSize,
    VisualDensity? visualDensity, TapTargetSize? tapTargetSize,
    ButtonLayerBuilder? backgroundBuilder, PressLook? pressLook, bool? ringStandsOff,
  });
  ButtonStyle merge(ButtonStyle? other);
}

class ButtonThemeData {
  const ButtonThemeData({this.icon, this.text, this.filled, this.outlined});
  ButtonThemeData copyWith({...});
  ButtonThemeData merge(ButtonThemeData other);
}
class ButtonTheme extends InheritedWidget {
  const ButtonTheme({super.key, required this.data, required super.child});
  static ButtonThemeData of(BuildContext context);
  static Widget merge({required ButtonThemeData data, required Widget child});
}
```

```dart
// 一个主按钮 + 一个次按钮
FilledButton(onPressed: save, child: const Text('保存'))
TextButton(onPressed: cancel, child: const Text('取消'))

// 带图标
FilledButton.icon(onPressed: connect, icon: const GlyphIcon(Glyphs.check), label: const Text('连接'))

// 图标按钮（注意：icon 是 Widget，不是 IconData）
IconButton(
  tooltip: '刷新',
  icon: const GlyphIcon(AppGlyphs.refresh),
  onPressed: loading ? null : reload,
)

// 选中态图标按钮
IconButton(
  tooltip: '固定',
  icon: const GlyphIcon(AppGlyphs.pin),
  isSelected: pinned,
  selectedIcon: const GlyphIcon(AppGlyphs.pin),   // 或 AnimatedGlyph
  onPressed: togglePin,
)
```

#### `TonalButton` 族（iOS 26/27 风格的「胶囊 + 玻璃」按钮）

`lib/button.dart`

```dart
enum TonalButtonSize {
  bar(button: 44, icon: 24),
  docked(button: BottomInsetScope.dockedSearchHeight, icon: 24),
  section(button: 36, icon: 20),
  compact(button: 32, icon: 20);
}

const TonalButton({super.key, this.size = TonalButtonSize.section, this.glyph, required this.label, required this.onPressed});
const TonalButtonGroup({super.key, this.size = TonalButtonSize.bar, required this.children});
const TonalButtonTheme({super.key, this.grouped = false, this.glass = false, this.size = TonalButtonSize.bar, required this.child});
class MoreActionButton { const MoreActionButton({super.key, this.onPressed, required this.label, this.trailing}); }
```

```dart
// 页面下半部的次级动作
TonalButton(glyph: AppGlyphs.add, label: '添加配置', onPressed: addConfig)
```

#### app bar 上的按钮

```dart
// lib/models.dart
@freezed
abstract class IconButtonData with _$IconButtonData {
  const factory IconButtonData({
    required Glyph glyph,
    required VoidCallback? onPressed,
    String? tooltip,
    @Default(false) bool isLoading,     // 显示 spinner 并禁用
    bool? isSelected,                   // 非 null → 变成 toggle，选中用 primary 填充
  });
}

// lib/scaffold.dart
const AppBarActionButton({super.key, required this.data, this.icon});
```

### 6.5 输入控件

#### `Switch` ✅

```dart
const Switch({super.key, required this.value, required this.onChanged, this.semanticLabel});
// 静态：trackWidth = 52, trackHeight = 32
```

```dart
Switch(value: enabled, onChanged: (v) => setEnabled(v))
```

#### `Checkbox` ✅

```dart
const Checkbox({super.key, required this.value, required this.onChanged, this.isCircle = false});
// value: bool? —— null = 三态 indeterminate
```

```dart
Checkbox(value: checked, onChanged: (v) => toggle(v))
Checkbox(value: picked, isCircle: true, onChanged: (_) => pick())   // 编辑模式圆勾
```

#### `Slider` ✅

```dart
const Slider({
  super.key,
  required this.value,                    // double
  required this.onChanged,                // ValueChanged<double>?
  this.onChangeEnd,
  this.min = 0,
  this.max = 1,
  this.divisions,
  this.label,                             // 拖动时 thumb 上的气泡文案
  this.shape,                             // SliderShape?（默认带缺口的轨道 + 竖条 thumb）
});

abstract class SliderShape {             // 想自定义外观才用
  double get height;
  double get thumbInset;
  void paint(Canvas canvas, Size size, {required double value, required double activation, required bool enabled, required int? divisions, required TextDirection textDirection});
}
```

```dart
Slider(value: scale, min: 0.8, max: 1.4, divisions: 12, label: '${(scale * 100).round()}%', onChanged: setScale)
```

#### `SegmentedControl<T>` ✅（= Material `SegmentedButton`）

```dart
const SegmentedControl({
  super.key,
  required this.segments,     // List<(T, String)>  ★ 记录类型
  required this.value,        // T
  required this.onChanged,    // ValueChanged<T>
});
```

```dart
SegmentedControl<OutboundMode>(
  segments: const [(OutboundMode.rule, '规则'), (OutboundMode.global, '全局'), (OutboundMode.direct, '直连')],
  value: mode,
  onChanged: (m) => setMode(m),
)
```

#### `Chip` / `TonalChip` / `MetaChip`

```dart
// lib/chip.dart
const Chip({super.key, required this.label, this.onDeleted, this.onPressed, this.selected = false});
//   onDeleted != null → 可删除（右侧 ×，且永远不会被 selected 填充）
//   selected = true + onPressed → primary 填充的「选择 chip」

const TonalChip({super.key, required this.label, required this.color, required this.foregroundColor, this.onPressed});

const MetaChip({super.key, required this.label});      // 小号灰底标签（协议、类型标记）
```

```dart
Chip(label: '全局', selected: isGlobal, onPressed: pick)
Chip(label: kw, onDeleted: () => removeKeyword(kw))
TonalChip(label: '128ms', color: scheme.successContainer, foregroundColor: scheme.onSuccessContainer)
MetaChip(label: 'hysteria2')
```

#### `TextField` / `TextFormField`（prism_ui 自己的，签名基本对齐 Material）

`lib/text_field.dart`

```dart
const TextField({
  super.key,
  this.controller, this.focusNode, this.undoController,
  this.decoration = const InputDecoration(),
  this.keyboardType, this.textInputAction, this.textCapitalization = TextCapitalization.none,
  this.style, this.strutStyle, this.textAlign = TextAlign.start, this.textAlignVertical, this.textDirection,
  this.readOnly = false, this.showCursor, this.autofocus = false,
  this.obscuringCharacter = '•', this.obscureText = false, this.autocorrect = true,
  this.smartDashesType, this.smartQuotesType, this.enableSuggestions = true,
  this.maxLines = 1, this.minLines, this.expands = false, this.maxLength, this.maxLengthEnforcement,
  this.onChanged, this.onEditingComplete, this.onSubmitted, this.inputFormatters,
  this.enabled, this.cursorWidth = 2, this.cursorHeight, this.cursorRadius, this.cursorColor,
  this.keyboardAppearance, this.scrollPadding = const EdgeInsets.all(20),
  this.dragStartBehavior = DragStartBehavior.start, this.enableInteractiveSelection = true,
  this.onTap, this.onTapAlwaysCalled = false, this.onTapOutside, this.mouseCursor,
  this.buildCounter, this.scrollController, this.scrollPhysics,
  this.autofillHints = const <String>[], this.clipBehavior = Clip.hardEdge,
  this.contextMenuBuilder = TextSelectionMenu.editableText,
  this.canRequestFocus = true, this.enableIMEPersonalizedLearning = true,
});

TextFormField({
  super.key, this.controller, String? initialValue, FocusNode? focusNode,
  InputDecoration? decoration = const InputDecoration(), ... 同上 Material 的参数 ...,
  super.validator, super.onSaved, AutovalidateMode? autovalidateMode,
});

const InputDecoration({
  this.hint, this.hintText, this.hintStyle, this.hintMaxLines,
  this.helperText, this.error, this.errorText, this.errorStyle, this.errorMaxLines,
  this.counter, this.counterText, this.counterStyle,
  this.prefix, this.prefixText, this.prefixStyle, this.suffix, this.suffixText, this.suffixStyle,
  this.prefixIcon, this.suffixIcon, this.prefixIconConstraints, this.suffixIconConstraints,
  this.constraints, this.contentPadding, this.isDense, this.isCollapsed,
  this.filled, this.fillColor, this.hoverColor,
  this.border, this.enabledBorder, this.disabledBorder, this.focusedBorder, this.errorBorder, this.focusedErrorBorder,
  this.enabled = true,
});
const InputDecoration.collapsed({required this.hintText, ...});

// 输入框主题（lib/text_field.dart:249 / 309）
const InputDecorationThemeData({
  this.contentPadding, this.isDense = false, this.isCollapsed = false,
  this.filled = false, this.fillColor, this.hoverColor,
  this.border = AppShape.input, this.enabledBorder, this.disabledBorder,
  this.focusedBorder, this.errorBorder, this.focusedErrorBorder,
});
class InputDecorationTheme extends InheritedWidget {
  const InputDecorationTheme({super.key, required this.data, required super.child});
  static InputDecorationThemeData of(BuildContext context);
}
```

```dart
// 组里的一行（推荐：标题在行上，字段只是值）
Card(
  padding: EdgeInsets.zero,
  child: ListRow(
    title: const Text('端口'),
    trailing: SizedBox(
      width: 120,
      child: TextField(
        controller: portController,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.end,
        decoration: const InputDecoration(hintText: '7890'),   // 不设 border！
      ),
    ),
  ),
)

// 独立的、有浮动 label 的描边输入框（border 保持默认 = AppShape.input）
TextField(decoration: const InputDecoration(hintText: '订阅链接'))
```

**规范硬要求**：表单里的字段是「裸字段 + 行标题」（`ListRow` 的 title 就是标签），字段**不画自己的框**；只有孤立在页面上的字段才描边，而描边是 `AppInputBorder` 自动的——**调用点永远不要设 `border`**。

#### `SearchField` ✅

```dart
const SearchField({
  super.key,
  this.onChanged,               // ValueChanged<String>?
  this.controller,
  this.focusNode,
  this.autofocus = false,
  this.height,
  this.fill,
  this.glyph = Glyphs.search,
  this.hintText,
  this.onSubmitted,             // VoidCallback?
  this.trailing,
});
```

#### `SecretTextFormField` / `InputDialog` / `FilledInputTheme`

```dart
// lib/input.dart
const SecretTextFormField({
  super.key,
  required this.controller,
  this.focusNode,
  this.decoration = const InputDecoration(),
  this.maxLines = 1, this.maxLength, this.inputFormatters, this.textInputAction,
  this.onFieldSubmitted, this.validator, this.autofocus = false,
});   // 自动带 eye/eyeOff 切换按钮

const InputDialog({
  super.key,
  required this.title,
  required this.value,
  this.suffixText, this.resetValue, this.hintText, this.validator,
  this.obscureText, this.labelText, this.maxLength, this.inputFormatters, this.keyboardType,
  this.selectAll = false,
  this.autovalidateMode = AutovalidateMode.onUserInteraction,
});   // 用 showFloatingDialog 打开，pop 出 String?

const FilledInputTheme({super.key, required this.fillColor, this.borderRadius, this.contentPadding, required this.child});
```

```dart
final v = await showFloatingDialog<String>(
  context: context,
  child: InputDialog(title: '重命名', value: current),
);
if (v != null) rename(v);
```

### 6.6 弹层：Dialog / Sheet / Popup / 上下文菜单

#### `AlertDialog` + `showFloatingDialog` ✅（= Material `showDialog` + `AlertDialog`）

```dart
// lib/dialog.dart:44
Future<T?> showFloatingDialog<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = true,
});

// lib/dialog.dart:381
const AlertDialog({
  super.key,
  required this.title,           // ★ String，不是 Widget
  this.trailing,                 // 标题右侧控件
  this.actions,                  // List<Widget>?  —— 最后一个 = 默认动作（primary 填充）；第一个 = 取消
  this.child,                    // 正文
  this.padding,
  this.hasFields = false,        // ★ 字段模式：字段铺满按钮宽度、填按钮的色
  this.destructive = false,      // 最后一个动作 = destructive（iOS systemRed）
});

// lib/dialog.dart:662
const AlertActions({super.key, required this.actions, this.fill, this.destructive = false});
//   当你想在别处（如 form sheet 底部）复用 alert 的按钮布局时用
```

```dart
// 确认框
await showFloatingDialog<void>(
  context: context,
  child: AlertDialog(
    title: '删除这个配置？',
    child: const Text('删除后无法恢复。'),
    destructive: true,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
    ],
  ),
);

// 单值输入框
await showFloatingDialog<void>(context: context, child: InputDialog(title: '端口', value: '7890'));
```

> ❌ 没有 `showDialog` / `Dialog`（Material 的通用 `Dialog`）——只有 `showFloatingDialog` + `AlertDialog`。
> ❌ 没有 `barrierColor` 参数；alert 永久用 `ColorScheme.alertScrim`。

#### Sheet —— ❌ 没有 `Sheet` 组件，只有 5 个 `show*` 函数 + 3 个 route

`lib/sheet.dart`

```dart
enum SheetType { page, bottomSheet, sideSheet, formSheet;  bool get isCompact; }

@immutable
class SheetProps {
  final Color? backgroundColor;
  final List<double> detents;      // 默认 snapSheetDetents = [9/16, 0.9]
  const SheetProps({this.backgroundColor, this.detents = snapSheetDetents});
}
const snapSheetDetents = [9 / 16, 0.9];

// ★ 平台自适应的总入口：手机 → bottom sheet；桌面 → side sheet
Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  SheetProps props = const SheetProps(),
});

// 表单：手机 → bottom sheet；桌面 → 居中的卡片（max 440×720）
Future<T?> showFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  SheetProps props = const SheetProps(),
});

// 侧栏 sheet（桌面）
Future<T?> showModalSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
});

// 可拖动 detent 的 sheet；builder 能拿到 sheet 自己的 ScrollController
Future<T?> showSnapSheet<T>(
  BuildContext context, {
  required SnapSheetBuilder builder,     // Widget Function(BuildContext, ScrollController?)
});

// 「展开成全页」：手机 push 一个整页 sheet；桌面开侧栏
Future<T?> showExtend<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ExtendProps props = const ExtendProps(),
});

const ExtendProps({this.forceFull = false});
```

直接构造 route（需要自定义 barrier/transition 时）：

```dart
SnapSheetRoute<T>({
  required SnapSheetBuilder builder,
  required Color sheetBarrierColor,
  required String barrierLabel,
  List<double> detents = snapSheetDetents,
  bool fitsContent = false,
});
ModalSideSheetRoute<T>({
  required WidgetBuilder builder,
  required String barrierLabel,
  String? barrierOnTapHint,
  Color? backgroundColor,
  Color? modalBarrierColor,
});
FormSheetRoute<T>({
  required WidgetBuilder builder,
  required Color barrierColor,
  required String barrierLabel,
  Color? backgroundColor,
});
class SideSheet extends StatefulWidget {
  const SideSheet({super.key, this.backgroundColor, required this.builder});
}
```

```dart
// 简单的底部/侧边 sheet
await showSheet<void>(context: context, builder: (_) => const SettingsSheet());
// 内容里记得用 PrismScaffold 或 ScaffoldBar 才有标题栏和关闭按钮

// 可拖 detent，并且内容要跟着 sheet 的滚动
await showSnapSheet<void>(context, builder: (context, controller) {
  return PrismScaffold(
    bar: ScaffoldBar(isCompact: true, listenable: ..., builder: ..., loading: ...),
    body: PrismListView(controller: controller, ...),
  );
});

// 表单（多个值）
await showFormSheet<void>(context: context, builder: (_) => const ProfileForm());

// Material 的 showModalBottomSheet 对应
await showSheet<void>(context: context, builder: (_) => const Picker());
```

**sheet 尺寸的规矩**：sheet 的尺寸属于它的 route，**不要**为了调大小把内容包 `SizedBox`/`Container(width:)`。手机 bottom sheet 停在 `SheetProps.detents`；侧栏 sheet 由 `ModalSideSheetRoute` 按窗口宽度算；form sheet 是 `FormSheetRoute` 限制的卡片。

#### Popup / 菜单（= Material `PopupMenuButton`）

`lib/popup.dart`

```dart
enum PopupPlacement { overAnchorEnd, overAnchorStart, belowPoint }
typedef PopupOpen = void Function();

// ★ 用法：包住触发按钮，按下即开菜单
class PopupAnchor extends StatefulWidget {
  const PopupAnchor({
    super.key,
    required this.targetBuilder,      // Widget Function(PopupOpen open)
    required this.popupBuilder,       // WidgetBuilder
    this.placement = PopupPlacement.overAnchorEnd,
    this.bare = false,                // 触发件自身没有表面（如 bar 的标题）
  });
}

const PopupMenuItem({
  required this.label,               // String
  this.subtitle,
  this.glyph,                        // Glyph?
  this.onPressed,
  this.danger = false,               // 红色（菜单里用 error，不是 destructive）
  this.checked,                      // bool? —— 打勾
  this.keepsOpen = false,            // iOS keepsMenuPresented
  this.section,                      // PopupMenuSection? —— 从这里起分段
  this.subItems = const [],          // 子菜单
});

const PopupMenuSection({this.title});

const PopupMenu({super.key, required this.items, this.maxVisibleItems});
//   maxVisibleItems: 只渲染可见行（需等高行）；默认 null

const PopupValueText(this.text, {super.key, this.alignment = AlignmentDirectional.center});  // 值切换时模糊淡入的文本

AnchoredPopupRoute<T>({
  required this.builder, required this.anchorOf, required this.barrierLabel,
  this.placement = PopupPlacement.overAnchorEnd, this.elevated = false,
  this.sourceColor = Colors.transparent, this.sourceImage, this.bareSource = false,
  this.modal = true, this.avoid,
});
```

```dart
PopupAnchor(
  targetBuilder: (open) => IconButton(
    tooltip: '更多',
    icon: const GlyphIcon(Glyphs.more),
    onPressed: open,
  ),
  popupBuilder: (_) => PopupMenu(items: [
    PopupMenuItem(glyph: AppGlyphs.edit, label: '编辑', onPressed: edit),
    PopupMenuItem(glyph: AppGlyphs.copy, label: '复制', onPressed: copy),
    PopupMenuItem(glyph: AppGlyphs.delete, label: '删除', danger: true, onPressed: remove),
  ]),
)
```

#### 上下文菜单（= Material 的 secondary tap / long press 菜单）

```dart
const ContextMenuRegion({super.key, this.menuItems, required this.child});
// 右键（桌面）、长按（触摸）、菜单键、遥控器长按 select 都会开
```

```dart
ContextMenuRegion(
  menuItems: [
    PopupMenuItem(label: '编辑', onPressed: edit),
    PopupMenuItem(label: '删除', danger: true, onPressed: remove),
  ],
  child: Card(onPressed: openDetail, child: ...),
)
```

> 规范要求：**行的次要操作走上下文菜单，不要在行尾放「⋯」按钮**。

### 6.7 反馈 / 状态 / 杂项

#### `BannerHost` + `BannerLevel`（= Material `SnackBar` / `ScaffoldMessenger`）✅ 但 ❌ 没有 `Toast`

```dart
// lib/banner.dart
enum BannerLevel {
  info,      // 3s，默认表面色
  success,   // 3s，successContainer
  warning,   // 5s，warningContainer
  error;     // 6s，errorContainer
  Duration get duration;
  Color? fillOf(ColorScheme);
  Color contentOf(ColorScheme);
}

class BannerHost extends StatefulWidget {
  const BannerHost({super.key, required this.stacked, required this.topInset, required this.child});
  static BannerHostState? maybeOf(BuildContext context);
}

class BannerHostState extends State<BannerHost> {
  void show(String text, {BannerLevel level = BannerLevel.info, VoidCallback? onTap});
}
```

`PrismApp` 已经内置 `BannerHost`，所以只用：

```dart
BannerHost.maybeOf(context)?.show('已保存');                                   // info
BannerHost.maybeOf(context)?.show('连接失败', level: BannerLevel.error);        // error
BannerHost.maybeOf(context)?.show('配置已导入', level: BannerLevel.success, onTap: openIt);
```

> ❌ 没有 `Toast`、没有 `showToast()`、没有 `ScaffoldMessenger`。
> 重复 `show` 同样文案会被合并（`repeats`）。

#### `NullStatus` / `NullStatusSwitcher` / `EmptyIllustration` ✅（空态 / 错误态 / 加载态）

```dart
// lib/null_status.dart
abstract interface class Illustration {
  static const Illustration search = _SearchIllustration();
  Glyph get glyph;
  bool get isError;
}

const NullStatus({
  super.key,
  this.label,
  this.description,
  this.action,                  // Widget? —— 底部动作按钮
  required this.illustration,   // ★ 必填
});

const NullStatusSwitcher({
  super.key,
  this.isLoading = false,
  this.isEmpty = false,
  this.isSearching = false,
  this.holdsArrival = true,     // 第一次加载时压住路由转场
  this.loadingStatus,           // 首屏加载超过 400ms 才显示
  this.nullStatus,              // isEmpty 时显示
  required this.child,
});   // assert(!isEmpty || nullStatus != null)

const EmptyIllustration({super.key, required this.type, required this.dimension});
static double dimensionOf(BuildContext context);   // 矮屏 120，否则 160
```

```dart
NullStatusSwitcher(
  isLoading: profilesAsync.isLoading,
  isEmpty: profiles.isEmpty,
  nullStatus: NullStatus(
    label: '还没有配置',
    description: '添加一个订阅或手动导入配置。',
    illustration: EmptyIllustration(
      type: Illustration.search,
      dimension: EmptyIllustration.dimensionOf(context),
    ),
    action: FilledButton(onPressed: import, child: const Text('导入')),
  ),
  loadingStatus: const Center(child: ActivityIndicator.page()),
  child: PrismListView(itemCount: n, itemBuilder: (_, i) => ...),
)
```

> 自己的插图：实现 `Illustration` 接口（`glyph` + `isError`），FlClash 的做法见 `lib/ui/null_status_illustration.dart`。
> 规范要求：等待数据时**什么都不显示**（不是骨架屏）；长时间加载才给 `loadingStatus`。

#### `ActivityIndicator` / `LoadingBar` / ❌ `Loading`

```dart
// lib/loading.dart
const ActivityIndicator({super.key, this.size, this.color, this.semanticLabel});
const ActivityIndicator.page({super.key, this.color, this.semanticLabel});   // 整页用的尺寸 + 转场联动

const LoadingBar({super.key, required this.active});    // app bar 下面那 3dp 的两段进度
static const extent = 3.0;

class ActivityPresence extends InheritedWidget {         // switcher ↔ indicator 的转场握手
  const ActivityPresence({super.key, required this.animation, required super.child});
  static Animation<double>? maybeOf(BuildContext context);
}
```

```dart
// 按钮里的转圈
IconButton(icon: isLoading ? const ActivityIndicator(size: 20) : const GlyphIcon(Glyphs.check), ...)

// 整页转圈（配合 NullStatusSwitcher.loadingStatus）
const Center(child: ActivityIndicator.page())
```

> ❌ 没有 `Loading` 类；❌ 没有 `CircularProgressIndicator`。整页转圈 = `ActivityIndicator.page()`。

#### `SkeletonText` / `SkeletonPill`（❌ 没有 `Skeleton`）

```dart
const SkeletonText({super.key, required this.width, this.style});   // 占一行文字的脉动条
const SkeletonPill({super.key, required this.width, required this.height});
```

#### `LinearProgressIndicator`（同名不同库）

```dart
const LinearProgressIndicator({super.key, this.value, this.backgroundColor, this.minHeight = 4});
//   value == null → 不定进度（两条线跑）
```

#### `Divider`

```dart
const Divider({super.key, this.height = 16, this.thickness = 0});   // thickness 0 = 1 物理像素发丝线
static Color colorOf(BuildContext context);                          // onSurface @14% ★ 唯一正确的分隔色
static BorderSide createBorderSide(BuildContext context);
```

```dart
Divider()                                   // 行间
Divider(height: 1, thickness: 1)            // 贴着实心块
```

#### `Tooltip`

```dart
const Tooltip({
  super.key,
  required this.message,
  this.preferBelow = true,
  this.triggerMode = TooltipTriggerMode.longPress,   // 触摸默认长按；桌面 hover 自动有
  this.excludeFromSemantics = false,
  required this.child,
});
```

#### 其它常用的「非组件」工具

```dart
// 动画 / 转场
const FadeBox({super.key, required this.child, this.alignment});   // lib/fade_box.dart
const FadeThroughBox; const FadeScaleBox; const FadeScaleEnterBox;
const FadeSlideEnterTransition; const FadeScaleEnterTransition;
const AnimatedVisibility.sidebar({super.key, required this.visible, required this.child});
const AnimatedVisibility.bottomNavigation({super.key, required this.visible, required this.child});
class KeyedAnimatedList<T>;                                       // lib/keyed_animated_list.dart
class AnimatedEntries<K>; class EntryTransition;                  // lib/animated_entries.dart
class SpringCurve extends Curve; class ArrivingSimulation;         // lib/motion.dart
const ExpandIcon({super.key, this.expand = false});                // lib/effect.dart
const DisabledMask({super.key, required this.child, this.status = true});   // lib/disabled_mask.dart
class SliverCollapsibleSection; class SliverCollapsibleGroups; class CollapsibleHeader;  // lib/collapsible_section.dart
class ThemeCrossFade;                                              // 明暗切换淡入淡出
const GooSurface({super.key, this.glass, required this.color, this.shadows = const [], required this.child});  // lib/goo.dart
const GooPane({super.key, super.child});
bool GooSurface.of(BuildContext context);                          // 是否在 goo 表面内

// 排序模式见 §6.2（SortModeScope / SortableItem / SortHandle / SortableTrailing）
```

### 6.8 页面骨架：`PrismScaffold` / `ScaffoldBar` / `AppBar`

> ❗**最重要的一条**：`primaryAction` / `iconActions` / `menuItems` **不在 prism_ui 的 Scaffold 上**。那是 FlClash 应用层 `lib/ui/scaffold/scaffold.dart` 里的 `Scaffold`。prism_ui 只有更底层的三件套。

```dart
// lib/scaffold.dart:49  —— 只管布局，不管内容
const PrismScaffold({
  super.key,
  required this.bar,                    // PreferredSizeWidget ★ 必填
  required this.body,
  this.headerListenable,                // Listenable?  头部（如关键词条）变化时重建
  this.headerBuilder,                   // Widget? Function(BuildContext)?  浮在 bar 下面（body 不再压到它下面）
  this.foot,                            // Widget?  底部悬浮物（docked search / dock）
  this.footHidden = false,              // 隐藏 foot 但不动 body
  this.footInset = 0,                   // foot 给 body 留的高度（BottomInsetScope）
  this.footActions,                     // Widget?  foot 下面的动作条（form sheet 的取消/确认）
  this.backgroundColor,
  this.resizeToAvoidBottomInset,
});

// lib/scaffold.dart:214
const ScaffoldBar({
  super.key,
  required this.isCompact,              // true = sheet 里的 48dp bar；false = 页面 72dp bar（+ 顶部安全区）
  required this.listenable,             // Listenable  重建 bar 用
  required this.builder,                // WidgetBuilder
  required this.loading,                // ValueListenable<bool>  bar 底下那条 LoadingBar
  this.backgroundColor,
}) implements PreferredSizeWidget;

// lib/scaffold.dart:567  —— 真正画标题/左右按钮的 bar（= Material AppBar）
const AppBar({
  super.key,
  this.leading,                         // Widget?
  this.title,
  this.actions = const [],              // List<Widget>
  this.centerTitle = false,
  this.titleSpacing,
  this.toolbarHeight,                   // 默认 pageToolbarHeight = 72
  this.titleTextStyle,                  // 默认 title3 / onSurface
  this.systemOverlayStyle,
  this.clipBehavior = Clip.hardEdge,
});

// 辅助
const AppBarClearance({super.key, required this.child});     // 给「body 在 scaffold 外面」的页面让出 bar 高度
class AppBarActionButton { const AppBarActionButton({super.key, required this.data, this.icon}); }
enum AppBarActionEdge { icon, container; }
List<Widget> genActions(List<Widget> actions, {required AppBarActionEdge edge});
Iterable<Widget> separatedBy(Iterable<Widget> items, Widget separator);
double appBarActionInset(bool compact);         // compact ? 16 : 20
double appBarLeadingWidth(bool compact);
bool isCompactBar(BuildContext context, bool isMobileView);
const double appBarActionSpace = 4;
const double barButtonGap = 8;

// context 上的页面几何量（lib/context.dart）
double get appBarInset;
double get contentTopPadding;
double get sectionsTopPadding;
double get bottomInset;
bool get isInCompactSheet;
bool get isMobileView;
void safeNestedPop<T extends Object?>([T? result]);

// 常量（lib/metrics.dart）
const pageToolbarHeight = 72.0;
const sheetToolbarHeight = 48.0;
const sheetAppBarHeight = 68.0;
const listRowMinHeight = 56.0;
const listRowVerticalPadding = 10.0;
const bannerBarClearance = 59.0;
const midDuration = Duration(milliseconds: 200);
const commonDuration = Duration(milliseconds: 300);
// 自适应尺寸：16.ap(context) / 8.mAp(context)   （随字号缩放，mAp 只放大不缩小）
```

**最简页面（不用 FlClash 的 Scaffold）**：

```dart
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PrismScaffold(
      bar: ScaffoldBar(
        isCompact: false,
        listenable: Listenable.merge(const []),           // 没东西要监听就给个空 Listenable
        loading: const ValueNotifier(false),
        builder: (context) => AppBar(
          title: const Text('设置'),
          actions: [
            ElasticPress(
              child: AppBarActionButton(
                data: IconButtonData(
                  glyph: Glyphs.search,
                  tooltip: '搜索',
                  onPressed: () => openSearch(context),
                ),
              ),
            ),
            const SizedBox(width: appBarActionSpace),
          ],
        ),
      ),
      body: PrismListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
    );
  }
}
```

**FlClash 风格的 `Scaffold`（推荐照抄，能力最强）** —— 它在 `Q:\ref\FlClash\lib\ui\scaffold\scaffold.dart`，把 `primaryAction/iconActions/menuItems` 折进溢出菜单：

```dart
Scaffold(
  title: '配置',
  body: ...,
  isLoading: saving,
  // 一个主按钮（最显眼，靠右）
  primaryAction: IconButtonData(glyph: AppGlyphs.add, tooltip: '新增', onPressed: add),
  // 2-3 个图标按钮：超过 3 个自动折进「⋯」
  iconActions: [
    IconButtonData(glyph: AppGlyphs.refresh, tooltip: '刷新', onPressed: reload, isLoading: loading),
    IconButtonData(glyph: AppGlyphs.sort, tooltip: '排序', onPressed: toggleSort),
  ],
  // 折叠到溢出菜单里的菜单项
  menuItems: [
    PopupMenuItem(glyph: AppGlyphs.delete, label: '全部删除', danger: true, onPressed: clearAll),
  ],
  // 表单页的「保存」，会在 form sheet 里变成脚部的填充按钮
  confirmationAction: IconButtonData(glyph: AppGlyphs.check, tooltip: '保存', onPressed: save),
  // 内联搜索（桌面按 Ctrl/⌘+F）
  searchState: AppBarSearchState(onSearch: setQuery),
  // 选择模式下的动作
  selectionActions: [IconButtonData(glyph: AppGlyphs.delete, tooltip: '删除', onPressed: removeSelected)],
  // 可删除的筛选 chip
  keywords: keywordsNotifier,     // ValueListenable<List<ScaffoldKeyword>>
  canSort: true,
  backAction: null,
)
```

> 如果重写的项目里不想搬这套 870 行的 scaffold，就退而用 `PrismScaffold` + `ScaffoldBar` + `AppBar`，把动作直接塞进 `AppBar.actions`（**注意要自己在手机宽度下处理溢出**）。

### 6.9 导航

```dart
// 桌面侧栏（窗口 chrome）
const SidebarDestination({required this.glyph, required this.label});      // Glyph + String
const NavigationSidebar({
  super.key,
  required this.destinations,        // List<SidebarDestination>
  required this.selectedIndex,
  required this.expanded,
  required this.onSelected,          // ValueChanged<int>
  this.onToggle,                     // null = 无法就地展开，改开浮层
  this.windowControls = Size.zero,    // 原生窗口按钮遮住的区域
});

// 手机底部浮动 dock（iOS 26 风格、玻璃、可拖动选页）
const NavigationDockDestination({required this.glyph, required this.label});
const NavigationDock({
  super.key,
  required this.destinations,        // List<NavigationDockDestination>
  required this.selectedIndex,
  required this.onSelected,
});
static double heightOf(BuildContext context);
static double insetOf(BuildContext context);      // 内容底部要留的高度 → BottomInsetScope

// 手机底部常驻导航栏（关掉浮动 dock 时）
const NavigationDestination({required this.icon, required this.label});     // icon 是 Widget
const NavigationBar({
  super.key,
  required this.destinations,        // List<NavigationDestination>
  required this.selectedIndex,
  required this.onDestinationSelected,  // ValueChanged<int>
});

// Tabs —— ❌ 没有 TabView / TabBar，只有 TabController + TabBarView
class TabController extends ChangeNotifier {
  TabController({int initialIndex = 0, Duration? animationDuration, required this.length, required TickerProvider vsync});
  int get index; set index(int value);
  int get previousIndex;
  bool get indexIsChanging;
  double get offset; set offset(double value);
  void animateTo(int value, {Duration? duration, Curve curve = Curves.ease});
}
const TabBarView({
  super.key,
  required this.children,
  required this.controller,
  this.physics,
  this.dragStartBehavior = DragStartBehavior.start,
  this.viewportFraction = 1.0,
  this.clipBehavior = Clip.hardEdge,
});
```

```dart
// 手机：浮动 dock + 底部留白
Surface(
  color: SurfaceLevel.page.colorOf(context.colorScheme),
  child: Stack(children: [
    Positioned.fill(
      child: BottomInsetScope(
        inset: NavigationDock.insetOf(context),
        child: body,
      ),
    ),
    PositionedDirectional(
      start: 0, end: 0, bottom: 0,
      child: NavigationDock(
        destinations: [
          NavigationDockDestination(glyph: AppGlyphs.dashboard, label: '概览'),
          NavigationDockDestination(glyph: AppGlyphs.proxies, label: '代理'),
        ],
        selectedIndex: index,
        onSelected: (i) => setIndex(i),
      ),
    ),
  ]),
)

// Tab 页（分组标签）—— 标签条自己做（SegmentedControl 或 Chip 行）
TabBarView(controller: _tab, children: [PageA(), PageB()])
```

---

## 7. Material → prism_ui 对照表（批量改页面用）

| Material 里的 | prism_ui 对应 | 备注 |
|---|---|---|
| `MaterialApp` | `PrismApp` | 参数几乎一一对应；`ThemeMode` 是 prism_ui 的枚举 |
| `Theme` / `ThemeData` / `ColorScheme.fromSeed` | `Theme` / `ThemeData` / `seededColorScheme` | ✅ 同名不同库，直接换 import 即可，但 `ColorScheme.fromSeed` 有 `style:` 参数 |
| `Theme.of(context).colorScheme` | 同 | 或用 `context.colorScheme` 扩展 |
| `Theme.of(context).textTheme.titleMedium` 等 | `AppTextStyle.xxx.of(context)` | 没有 textTheme！ |
| `Scaffold` | `PrismScaffold`（bar+body）或 FlClash 的 `Scaffold`（title/primaryAction/…） | ❌ 没有 `Scaffold.of` / `ScaffoldMessenger` |
| `AppBar` | `AppBar`（放在 `ScaffoldBar.builder` 里） | ✅ 同名；但没有 `bottom:`；`title` 是 Widget |
| `Scaffold(backgroundColor:)` | `PrismScaffold(backgroundColor:)` | 默认 `SurfaceLevel.page` 色 |
| `Drawer` / `NavigationRail` | `NavigationSidebar` | ❌ 不存在 Drawer |
| `BottomNavigationBar` / `NavigationBar` | `NavigationDock`（浮动）或 `NavigationBar` | ✅ 同名 `NavigationBar`，但 `NavigationDestination.icon` 是 Widget |
| `Text` | `Text`（`flutter/widgets.dart`） | ✅ 继续用，样式从 `AppTextStyle` 取；长文本用 `TooltipLabel` |
| `Icon(Icons.foo)` | `GlyphIcon(Glyphs.foo)` / `GlyphIcon(AppGlyphs.foo)` | ❌ **图标字体整体不存在**，`Icons.*` 全部作废 |
| `InkWell` / `InkResponse` / `GestureDetector` | `PressSurface`（有表面）/ `PressRegion`（无表面）/ `GestureDetector`（纯手势） | ❌ 没有 `Material` 祖先，也没有 `Ink` |
| `ListTile` | `Card` + `ListRow`；成组时 `DecorationListItem` | `ListRow` 不带点击，必须包 `Card`/`PressSurface` |
| `Card` | `Card` | ✅ 同名；参数完全不同（`onPressed` / `isSelected` / `isError` / `shape`） |
| `ElevatedButton` | `FilledButton` | ❌ 没有 Elevated 这一级 |
| `FilledButton` | `FilledButton` | ✅ 同名同义 |
| `TextButton` | `TextButton` | ✅ |
| `OutlinedButton` | `OutlinedButton` | ✅（但它画的是 `outline` 色 1px 边框；规范里除输入框/焦点环极少用） |
| `IconButton` | `IconButton` / `IconButton.filled` | ✅ `icon:` 要 `GlyphIcon`，别忘 `tooltip:` |
| `FloatingActionButton` | ❌ 不存在 | 用 `TonalButton`（页面下半部）或放进 app bar 的 `primaryAction` |
| `Switch` | `Switch` | ✅ 参数只有 `value` / `onChanged` / `semanticLabel` |
| `Checkbox` | `Checkbox` | ✅ 多了 `isCircle` |
| `Radio` / `RadioListTile` | ❌ 不存在 | 用 `SelectedDecorationListItem`（圆勾）或 `Card + SelectionCheck` |
| `Slider` | `Slider` | ✅ 基本对齐；多了 `shape:` |
| `Chip` / `FilterChip` / `ChoiceChip` | `Chip`（`selected` + `onPressed` 即 choice chip）/ `TonalChip` / `MetaChip` | ❌ 没有 FilterChip/ActionChip 之分 |
| `SegmentedButton` | `SegmentedControl` | 参数不同：`List<(T, String)>` |
| `TabBar` / `TabBarView` / `TabController` | `TabBarView` / `TabController`（同名，参数略简） | ❌ **没有 `TabBar`**，标签条自己做（`SegmentedControl` 或 `Chip` 行） |
| `ListView` | 直接用（在 widgets 层）或 `PrismListView` | 长列表/远跳用 `PrismListView`；❌ 没有 `ListView.separated`（用 `gap:`） |
| `GridView` | 直接用（在 widgets 层） | prism_ui 没有网格组件，`GridView` / `SliverGrid` 继续用 |
| `CustomScrollView` / `SliverList` | `CustomScrollView` + `SliverPrismList` | ✅ |
| `RefreshIndicator` | ❌ **不存在** | 没有下拉刷新；自己做手势，或用按钮 + `LoadingBar`。规范也不要求下拉刷新 |
| `Scrollbar` | `Scrollbar` / `FloatingScrollbar` | ✅ 同名，`controller` 必填 |
| `showDialog` + `AlertDialog` + `Dialog` | `showFloatingDialog` + `AlertDialog` | ❌ 没有通用 `Dialog`；`title` 是 String |
| `showModalBottomSheet` | `showSheet`（手机）/ `showSnapSheet` / `showFormSheet` | ❌ 没有 `Sheet` 组件，只有 show 函数 |
| `showBottomSheet`（非模态） | ❌ | 用 `PrismScaffold(foot: ...)` |
| `showGeneralDialog` | `showFloatingDialog` 或自己 push `PopupRoute` | |
| `SnackBar` / `ScaffoldMessenger.showSnackBar` | `BannerHost.maybeOf(context)?.show(text, level: BannerLevel.x)` | ❌ 不存在 SnackBar/Toast |
| `PopupMenuButton<T>` | `PopupAnchor` + `PopupMenu(items: [PopupMenuItem(...)])` | 项是**数据类**，不是 Widget |
| `MenuAnchor` / `MenuItemButton` | 同上 | |
| `TextField` / `TextFormField` | `TextField` / `TextFormField` | ✅ 同名，签名基本一致；`decoration.border` 不要设 |
| `InputDecorationTheme` | `InputDecorationThemeData` / `InputDecorationTheme`（`lib/text_field.dart:248,308`） | |
| `Form` / `FormField` / `GlobalKey<FormState>` | 继续用（widgets 层） | ✅ |
| `CircularProgressIndicator` | `ActivityIndicator` / `ActivityIndicator.page()` | ❌ 不存在 |
| `LinearProgressIndicator` | `LinearProgressIndicator` | ✅ 同名；参数只有 `value` / `backgroundColor` / `minHeight` |
| `Divider` | `Divider` | ✅ 同名；`color` 只能来自 `Divider.colorOf(context)` |
| `VerticalDivider` | ❌ 不存在 | 用 `SizedBox(width: 1) + ColoredBox(Divider.colorOf(context))` |
| `Tooltip` | `Tooltip` | ✅ 同名同参数 |
| `IconTheme` / `IconThemeData` | 继续用（widgets 层） | `GlyphIcon` 从 `IconTheme` 读 color/size/fill |
| `Theme.of(context).iconTheme` | `Theme.of(context).iconTheme` | ✅ |
| `Material`（包一层才有 ink/elevation） | ❌ **不需要** | prism_ui 全部自行绘制，没有 Material 祖先要求 |
| `SafeArea` | 继续用（widgets） | `PrismScaffold` 已经处理了顶部 |
| `MediaQuery.of(context)` | 用分项：`paddingOf` / `viewInsetsOf` / `sizeOf` / `textScalerOf` | 规范明令：不要用整块 `MediaQuery.of` |
| `Color.withOpacity` | `color.withValues(alpha: x)` 或 `color.opacity80` 等 | Flutter 已弃用 `withOpacity` |
| `Colors.grey[600]` | ❌ 只有 `Colors.black/white/transparent/black54` | 用 `ColorScheme` 角色 |
| `NotificationListener` / `ScrollController` 等 | 继续用（widgets） | ✅ |
| `Navigator` / `MaterialPageRoute` | `Navigator` / `HomeRoute` / `CardPageRoute` | ❌ 没有 MaterialPageRoute |
| `RefreshCallback` / `onRefresh` | ❌ | 见 RefreshIndicator 行 |

---

## 8. 图标：Glyph 而不是 icon font

### 8.1 三件套

```dart
// lib/icons/glyph.dart
enum GlyphRole { body, detail, line }

class Glyph {
  const Glyph(this.shapes, {this.matchTextDirection = false});
  final List<GlyphShape> shapes;
  final bool matchTextDirection;     // RTL 时水平镜像（返回箭头等）
  static const size = 24.0;
  static const strokeWidth = 1.8;
}

sealed class GlyphShape {
  const GlyphShape({this.role = GlyphRole.body, this.solid = false});
  final GlyphRole role;              // body=1.8dp 描边，detail=更细，line=直线段
  final bool solid;
  Path get path;
}
// 具体形状（画 glyph 时用）：
GlyphBox(left, top, right, bottom, radius, {role});
GlyphCircle(x, y, radius, {role, solid});
GlyphOval(left, top, right, bottom, {role});
GlyphArc(...); GlyphPolyline([...], {role, closed}); GlyphVertex(x, y, [radius]); GlyphLink(a, b, radius); ...

// lib/icons/glyph_icon.dart
const GlyphIcon(this.glyph, {super.key, this.fill, this.size, this.color});
//   fill: 0 = 描边（默认），1 = 实心  ★ 实心只用在「填充按钮里」
//   color/size 缺省从 IconTheme 取；fill 缺省从 IconTheme.fill 取

// lib/icons/animated_glyph.dart —— 选中时描边→实心 + 轻微弹一下
const AnimatedGlyph({super.key, required this.glyph, required this.filled});
```

### 8.2 `Glyphs` —— prism_ui 自带的**全部只有 20 个**

`lib/icons/glyphs.dart`（293 行）

```
arrowBack, chevronBack, chevronForward, chevronDown, picker, caretDown,
close, clearField, check, more, dragHandle, sort, search, pin, eye, eyeOff,
copy, cut, paste, selectAll
```

加两个函数：

```dart
static Glyph sidebar(double progress);              // 侧栏开关图标（动画中间态）
static Glyph backFor(TargetPlatform platform);      // 按平台挑返回样式
```

> 真要用别的图标（删除、设置、刷新、CPU、内存、Wi-Fi……）**必须自己写 Glyph**，见下。

### 8.3 `AppGlyphs` ❌ 不是 prism_ui 的一部分

`AppGlyphs` 是 FlClash 应用层的文件：`Q:\ref\FlClash\lib\ui\icons\app_glyphs.dart`（1840 行，129 个常量）。**prism_ui 里没有 `AppGlyphs`。** 你要在重写的项目里自己建一个（照抄那个文件的形状定义，或自己画）。

```dart
// lib/ui/icons/app_glyphs.dart
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/glyph.dart';
import 'package:prism_ui/icons/glyphs.dart';

abstract final class AppGlyphs {
  static const dashboard = Glyph([
    GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
    GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
    GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
    GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
  ]);

  static const delete = Glyph([ /* ... */ ]);
  // ...
}
```

FlClash 那 129 个名字（供你按需实现）：

```
dashboard, proxies, profiles, requests, clock, connections, dns, resources, logs, tools,
target, arrowBack, chevronBack, chevronForward, chevronDown, chevronUp, picker, caretDown,
arrowUp, arrowDown, openExternal, undo, redo, sync, refresh, reset, export, upload, add,
remove, addCircle, removeCircle, close, clearField, check, checkDouble, checkCircle, block,
info, warning, error, more, moreCircle, dragHandle, sort, filter, textShort, wrap, listAdd,
edit, compose, delete, clearAll, copy, cut, paste, selectAll, deselect, search, matchCase,
regex, importFile, cloudDownload, cloudSync, link, send, rules, rulePresets, code, settings,
sliders, wrench, toggle, toggleOn, pin, eye, eyeOff, lock, lockOpen, key, password, account,
sparkle, bolt, locate, star, puzzle, customize, layers, radar, nodeGroup, sun, pureBlack,
palette, paintbrush, eyedropper, motion, blur, liquidGlass, font, textSize, language,
keyboard, photos, camera, qrCode, torch, torchOff, torchAuto, vpn, status, verified,
certificate, swap, shuffle, split, speed, dataUsage, memory, cpu, devices, broom, wifi,
wifiOff, gavel, appsList, iconTile
```

### 8.4 用法

```dart
// 普通位置：描边
GlyphIcon(AppGlyphs.settings)

// 指定大小/颜色
GlyphIcon(AppGlyphs.delete, size: 18, color: context.colorScheme.error)

// 填充按钮里：实心（规范要求）
FilledButton.icon(onPressed: go, icon: const GlyphIcon(Glyphs.check, fill: 1), label: const Text('连接'))

// 导航栏选中态：描边→实心动画
AnimatedGlyph(glyph: AppGlyphs.dashboard, filled: index == selected)

// 图标跟随主题（放 IconTheme 里）
IconTheme.merge(data: const IconThemeData(color: ..., size: 20, fill: 0), child: ...)
```

> 规则（SKILL.md）：「每个图标都是 glyph，绝不用 icon font；`prism_ui` 组件自己画的放 `Glyphs`，应用自己的放 `AppGlyphs`，用 `GlyphIcon` 显示，选中会填充的用 `AnimatedGlyph`。Glyph 默认描边，只有在**填充按钮内部**才 `fill: 1`。」

---

## 9. 交互硬性 checklist（改页面时逐条对）

### 表面 / 颜色

- [ ] **不要结构性边框。** 层次靠 `SurfaceLevel` 的明度台阶；只有三种边框合法：焦点环（2dp primary）、输入框（聚焦时）、窗口 chrome 的内边缘分隔线。
- [ ] 组件内取色用 `context.raisedSurfaceLevel.colorOf(scheme)`，**不要**在调用点硬编码 `SurfaceLevel.card`。
- [ ] 自己造表面后**必须** `SurfaceScope(level: level, child: ...)`，否则里面的东西不会自动更深一级。
- [ ] 浮层（dialog / popup / dock / banner）用 `SurfaceLevel.floatingOf(scheme)`。
- [ ] 暗色下 sheet 要抬一级：`ThemeData(elevatedColorScheme: scheme.elevated)`。
- [ ] `primaryContainer` / `secondaryContainer` / `tertiaryContainer` **不是**表面色也不是选中色，不要用它们填 card / row / mark / 导航指示器。
- [ ] 状态色（success/warning/error）只上文字、glyph 或小 chip，**不要**整块卡填充。整块填充的内容色用 `onSuccess`/`onWarning`，不是 `xxxContainer`。
- [ ] 删除动作在 alert 里用 `ColorScheme.destructive`（iOS systemRed），不是 `error`；菜单里的危险项用 `danger: true`（内部是 error）。
- [ ] 分隔线颜色只能来自 `Divider.colorOf(context)`（`onSurface` @14%），**不要**用 `outlineVariant`。
- [ ] 文本：标题和值 `onSurface`，标签/次要行 `onSurfaceVariant`。`outline` 不是文字色，值不要染 primary。

### 选中

- [ ] **选中 = 保留原本的填充 + 加一个 primary 标记**。成组列表行用 `SelectionCheck`，独立卡片/tile 用 `SelectionBadge`。
- [ ] **不要**用填充表示选中。唯一例外：连体按钮组 / 模式切换 / 一排 choice chip → `Card(fillsSelection: true)` 或 `Chip(selected: true)`，**每组只能有一个**。
- [ ] 多选编辑模式：用圆形 `Checkbox(isCircle: true)`，行本身填充不变。
- [ ] `Card.isSelected` 单独用只影响无障碍语义，视觉上什么都不变。

### 按压缩放

- [ ] 卡片、行、chip、色块、segment：按压 = `PressLook.ink`（状态层，Android 额外 sparkle）。**不要**自己写 `setState` 改颜色。
- [ ] 按钮（filled/text/icon）：按压 = `PressLook.tint`（亮色变到 75%，暗色混 20% 白）。
- [ ] `ElasticPress` 内的按钮、以及选中的 segment：`PressLook.none`，把反馈交给膨胀动画。
- [ ] **任何东西都不缩放**（除 `ElasticPress` 的整块膨胀）。
- [ ] hover：`PressSurface` 自己会铺 4% `onSurface` 并改鼠标手型；不要另加 hover 变色。

### 前景 / 控件互相抢事件

- [ ] 卡里放开关/图标按钮时，控件自己吃按压，卡不该亮：`CardSurface` 已经会跳过「命中语义 tap」的区域。所以**别用 `GestureDetector` 包住控件**（会破坏这个判断），用 `PressSurface` / `IconButton`。

### 形状

- [ ] 圆角只用 token：`AppCorner.*` / `AppRadius.*` / `AppShape.*`。**调用点不写裸数字**。
- [ ] 尺寸不确定时用 `AppCorner.fit(shortestSide)`；全宽表面固定 `xl`，**不要** `fit()`。
- [ ] 药丸用 `AppShape.full`，**不要** `StadiumBorder`；圆/头像用 `AppShape.circle`。
- [ ] 嵌套圆角是**算**出来的（`outer = inner + inset`），不是再加一个 token。
- [ ] 输入框的 `border` 留空（= `AppShape.input`）。
- [ ] 组件已经自带形状时，调用点**不要**再包一层 `ClipRRect`。

### 文字

- [ ] 字号/字重只能来自 `AppTextStyle`，**禁止**裸 `fontSize` / `fontWeight`。
- [ ] 中文 fallback 用 `appFontFamilyFallback(...)`，别自己拼字体列表。
- [ ] 数字列（延迟、流量、时间）加 `.toTabular`。

### 页面结构

- [ ] app bar 的动作以数据形式交给 bar（`IconButtonData`），这样溢出能自动折进「⋯」。
- [ ] 行的次要操作走 `ContextMenuRegion`（右键/长按），**不要**行尾放「⋯」按钮。
- [ ] 页面/弹层导航用「来处 context 的 navigator」，不要无脑 `rootNavigator`。`context.safeNestedPop()` 会优先关 sheet 内层的 navigator。
- [ ] 读 `MediaQuery` 用分项方法（`paddingOf` / `viewInsetsOf` / `sizeOf` / `textScalerOf`），不要 `MediaQuery.of`。
- [ ] 数据还没齐就什么都不显示（`NullStatusSwitcher.isLoading`），**不要**骨架屏；久等才给 `loadingStatus`。
- [ ] 等待中的异步按钮：`IconButtonData(isLoading: true)` 或自己换 `ActivityIndicator`，并把 `onPressed` 置 null。

---

## 10. 常见坑（按踩到的概率排序）

### 坑 1（最容易踩）：`PrismApp` 不提供 `ViewScope`，`AppBar`/`ScaffoldBar`/`showSheet` 会直接崩

`lib/view_scope.dart:25`：

```dart
assert(scope != null, 'No ViewScope found above $context.');
```

用到 `ViewScope` 的地方（都会 assert）：`AppBar.build`（`isCompactBar` → `ViewScope.isMobileOf`，`scaffold.dart:612`）、`ScaffoldBar`（`_WindowControlsClearance` → `windowControlsOf`）、`context.isMobileView`、`showSheet` / `showFormSheet` / `showSnapSheet` / `showExtend`。

> 注：`PrismScaffold` 本身**不**读 `ViewScope`，但它通常配的 `ScaffoldBar`/`AppBar` 会读。所以只要有 app bar 就必须提供。

**必须**在 `PrismApp` 之下、页面之上自己放一个（FlClash 的写法 `lib/manager/theme_manager.dart:113`）：

```dart
class ViewportScope extends StatelessWidget {
  const ViewportScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ViewScope(
          size: size,
          isMobile: size.width < 720,     // 自己的断点
          windowControls: Size.zero,
          child: child,
        );
      },
    );
  }
}
```

### 坑 2：`UiLocalizations` 必须注册，否则所有 show* 都崩

`lib/l10n.dart:6` 是 `abstract class`，`of()` 里 assert。`showSheet` / `showFormSheet` / `showSnapSheet` / `showModalSideSheet` / `showFloatingDialog` / `Scaffold` 的返回按钮 / `ContextMenuRegion` 都调它。

```dart
// 你需要实现这 18 个 getter
class AppUiLocalizations extends UiLocalizations {
  @override String get back => '返回';
  // cancel, clearSearch, close, copy, cut, dialog, hidePassword, more,
  // noSearchResults, paste, reset, select, search, selectAll, showLess,
  // showMore, showPassword, sort, submit
  static const LocalizationsDelegate<UiLocalizations> delegate = ...;
}

PrismApp(
  localizationsDelegates: const [
    AppUiLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,   // flutter_localizations
  ],
  ...
)
```

### 坑 3：没有 `prism_ui` 的 `Text`/`Icon`，图标字体彻底作废

- `Text` → 用 `flutter/widgets.dart` 的 `Text`（✅ 在 widgets 层，不需要 material）。
- `Icon` → **删掉**。`Icon` 本身在 widgets 层（`widgets/icon.dart`），但 prism_ui 的组件不会给它正确颜色/尺寸语义；统一改 `GlyphIcon`。
- `Icons.xxx` → ❌ Material 的图标字体，prism_ui 里一个都没有。必须按 §8 自己定义 Glyph。

### 坑 4：`Scaffold` / `AppBar` 的「高级参数」不在 prism_ui

- `PrismScaffold` **没有** `primaryAction` / `iconActions` / `menuItems` / `title` / `isLoading`。
- `prism_ui` 的 `AppBar` 有 `title` / `actions` / `leading`，但**没有** `bottom:`、`flexibleSpace:`、`elevation:`（它不画表面）。
- 需要 `primaryAction`/`iconActions`/`menuItems` 的能力 → 照抄 FlClash 的 `lib/ui/scaffold/scaffold.dart`（约 870 行 + 两个 part 文件），或者自己写一个 100 行左右的包装：把 `iconActions` 里超过 3 个的部分塞进一个 `PopupAnchor` 溢出菜单。

### 坑 5：`Card` 里放控件 → 控件必须能「吃」按压，否则整卡都亮

`CardSurface`（`lib/card_surface.dart`）遇到「语义 tap」会跳过自己的按压。所以：
- ✅ 用 `Switch` / `Checkbox` / `IconButton` / `PressSurface` / `PressRegion`
- ❌ 用裸 `GestureDetector` 包一个按钮（语义上没有 tap，卡片会跟着亮）

### 坑 6：`ListRow` 不带点击；列表也没有分隔线组件

- `ListRow` 只是**几何**（leading/title/subtitle/trailing + M3 的 baseline 逻辑），没有 ink、没有焦点、没有语义。可点击必须包 `Card` / `PressSurface`。
- 分隔线：❌ 没有公开的 `ListRowSeparator`。用 `DecorationListItem`（自动带）+ `Divider()`。

### 坑 7：shader 行为（liquid_glass / ink_sparkle）

| | 触发条件 | 不可用时 |
|---|---|---|
| `liquid_glass` | 必须 `PrismApp(liquidGlass: LiquidGlassQuality.standard/ultra)`；内部还要 `ui.ImageFilter.isShaderFilterSupported`（Impeller） | `PrismApp.liquidGlass == null`（默认）→ `LiquidGlassScope.enabled = false` → 组件自动退回**填充色**方案（dock / 按钮 / menu / alert 全是普通表面）。shader 加载失败只报一次 `FlutterError`，之后永久降级。**不会崩。** |
| `ink_sparkle` | 只在 `TargetPlatform.android` 且 `PressLook.ink` 时发 | shader 未加载好（首次是异步加载）就**不画** sparkle，状态层照常显示。**不会崩。** |

结论：**纯 Flutter 项目里不传 `liquidGlass` 就是全降级**，不需要做任何兼容处理；想要玻璃效果才传。`packages/prism_ui/pubspec.yaml` 已经声明了 `shaders/liquid_glass.frag` 和 `shaders/ink_sparkle.frag`，走 path 依赖时资源路径是 `packages/prism_ui/shaders/...`，正常能加载。

### 坑 8：Flutter 版本 / 新 API 依赖

`packages/prism_ui/pubspec.yaml` 写死 `flutter: '>=3.47.0'`（本机 SDK 是 3.50.0）。prism_ui 用到的较新 SDK 符号：

| 符号 | 用在哪 |
|---|---|
| `RSuperellipse` / `Path.addRSuperellipse` | `icons/glyph.dart`、所有超椭圆绘制 |
| `RoundedSuperellipseBorder` | `AppShape` 全部 token |
| `RawTooltip` / `TooltipTriggerMode`（在 widgets 层） | `lib/tooltip.dart` |
| `ImageFilter.isShaderFilterSupported` | `liquid_glass.dart:1303` |
| `TickerMode.getValuesNotifier` / `TickerModeData` | `press_surface.dart:134` |
| `MediaQuery.displayCornerRadiiOf` | `sheet.dart` 的 `bottomSheetRadiusOf` |
| `NavigationNotification` / `WidgetsApp.onNavigationNotification` | `app.dart` |
| `WidgetsApp.pageRouteBuilder` | `app.dart:172` |
| `SliverMainAxisGroup` | `list.dart` / `prism_list.dart` |
| `WidgetState` / `WidgetStatesController` / `IconThemeData.fill` | 按钮、`GlyphIcon` |
| `TextScaler` / `MediaQuery.textScalerOf` | 全局字号 |

落地要求：`pubspec.yaml` 的 `environment: flutter: '>=3.47.0'`（Dart SDK ≥ 3.10）。低于这个版本**编译不过**，不是运行时降级。

### 坑 9：`MeasureScope` 也是必需的

`lib/measure.dart:99` assert。`PrismApp` 已经提供，所以只要不把组件渲染到 `PrismApp` 之外（例如另一个 `runApp` / `WidgetsApp`）就没问题。`ListHeader`、`InfoHeader`、`ListRow` 的高度计算都依赖它。

### 坑 10：`ViewScope`/`MeasureScope` 之外，还有几个「有默认值所以安全」的 scope

这些 `of()` 都有默认值，缺了不崩，但**语义会不对**：

| scope | 缺省行为 | 后果 |
|---|---|---|
| `SurfaceScope` | `page` | 卡片永远用 page 的下一级（在嵌套卡片里就错了）—— 所以 `Card` 自己会包一层 |
| `BottomInsetScope` | `0` | body 底部不给 dock 留白，内容被 dock 盖住 |
| `TopInsetScope` / `FloatingBarScope` | `null` / `null` | `context.appBarInset` 退化到 `MediaQuery.padding.top + 72` |
| `SheetProvider` | `null` | `context.isInCompactSheet == false`、`safeNestedPop` 直接 pop 页面 |
| `LiquidGlassScope` | `enabled = false` | 无玻璃 |
| `GooSurface` | `false` | dock / 搜索框用普通填充而非 goo 形变 |

### 坑 11：`Theme.of(context)` 永不返回 null，但也不会回退到 Material 主题

`Theme.of` 在没有 `Theme` 祖先时用 `ThemeData._fallbacks.putIfAbsent(platform, ThemeData.new)` —— 一个 seed 0xFF6750A4 + `ColorStyle.soft` 的默认主题。所以：
- ❌ 不要指望「没有 PrismApp 也能拿到 Material 的颜色」。
- ✅ 组件能渲染，但颜色会不是你的品牌色。测试/预览时记得包 `Theme(data: ..., child: ...)`。

### 坑 12：`Card` / `Chip` / `SegmentedControl` 的 `inert` 与 `PressLook.none`

- `Card(inert: true)` = 忽略按压但保留可用颜色 → 用在「正在切换中，不想让动画跑」的场合（如 chips 组）。
- 选中 segment 上的 `PressSurface` 故意 `onPressed: () {}` 而不是 null（null 会让它掉焦点）。

---

## 11. 附录

### 11.1 「不存在 / 名字不同」总表

| 你列的 / Material 的 | 真实情况 |
|---|---|
| `Sheet` 组件 | ❌ 只有 `showSheet` / `showSnapSheet` / `showFormSheet` / `showModalSideSheet` / `showExtend` + `SnapSheetRoute` / `ModalSideSheetRoute` / `FormSheetRoute` / `SideSheet` |
| `ListRowSeparator` | ❌ private `_ListRowSeparator`；公开替代 `DecorationListItem` / `Divider` |
| `Button` | ❌ `common_button.dart` 里没有 `Button`；是 `IconButton` / `TextButton` / `FilledButton` / `OutlinedButton` |
| `Toast` / `showToast` | ❌ `BannerHost.maybeOf(context)?.show(...)` + `BannerLevel` |
| `Loading` | ❌ `ActivityIndicator` / `ActivityIndicator.page()` / `LoadingBar` |
| `Skeleton` | ❌ `SkeletonText` / `SkeletonPill`（只有这两个） |
| `TabView` / `TabBar` | ❌ 只有 `TabController` + `TabBarView`；标签条用 `SegmentedControl` 或 `Chip` 行 |
| `Sidebar` | ❌ `NavigationSidebar` + `SidebarDestination` |
| `Scaffold(primaryAction/iconActions/menuItems)` | ❌ 那是 FlClash 应用层 `lib/ui/scaffold/scaffold.dart` 的 `Scaffold`；prism_ui 是 `PrismScaffold` + `ScaffoldBar` + `AppBar` |
| `Popup` / `ContextMenu` | ✅ `PopupAnchor` + `PopupMenu` / `ContextMenuRegion`（菜单项是 `PopupMenuItem` 数据类，不是 Widget） |
| `AppGlyphs` | ❌ 不在 prism_ui（在 `Q:\ref\FlClash\lib\ui\icons\app_glyphs.dart`，应用层） |
| `delayColor` | ❌ 不在 prism_ui（FlClash `lib/ui/delay_color.dart`，11 行） |
| `chromeSurface` | ✅ 存在，但是 **extension** `ChromeSurfaceExt`（`lib/surface.dart:69`），不在 `ColorScheme` 类里 |
| `success` / `warning` / `destructive` | ✅ 存在，但是 **extension** `ColorSchemeExtension`（`lib/color.dart:304`） |
| `SelectionBadge.preferred` | ❌ 只在 surfaces.md 里提过；源码只有默认构造（`size` / `glyph` / `tonal`） |
| `RefreshIndicator` | ❌ prism_ui 没有任何下拉刷新 |
| `Radio` / `RadioListTile` | ❌ 用 `SelectedDecorationListItem` / `Card + SelectionCheck` |
| `Dialog`（通用） | ❌ 只有 `AlertDialog`（`title` 是 `String`） |
| `FloatingActionButton` | ❌ 不存在 |
| `VerticalDivider` | ❌ 不存在 |
| `Text`（prism_ui 版） | ❌ `text.dart` 里是 `TooltipText` / `HoverTooltip` / `TooltipLabel` / `EmojiFont` / `EmojiText`；`Text` 用 widgets 的 |
| `Material` 祖先 | ✅ 完全不需要 |

### 11.2 源码索引（改页面时按需翻）

| 文件 | 内容 |
|---|---|
| `lib/prism_ui.dart` | barrel（98 行） |
| `lib/app.dart` | `PrismApp` |
| `lib/theme_data.dart` | `Theme` / `ThemeData` / `ThemeMode` / `TapTargetSize` / `VisualDensity` / `Colors` / `Easing` / `systemFontOf` |
| `lib/theme.dart` | `MinFilledButtonTheme` / `MinIconButtonTheme`（只有这些） |
| `lib/color.dart` | `ColorStyle` / `seededColorScheme` / `ColorExtension` / `ColorSchemeExtension`（状态色） |
| `lib/color_scheme.dart` | `ColorScheme` |
| `lib/surface.dart` | `SurfaceLevel` / `SurfaceScope` / `Surface` / `FocusRing` / `chromeSurface` / `elevated` / `ElevatedSurfaceTheme` |
| `lib/shape.dart` | `AppCorner` / `AppRadius` / `AppShape` / `AppInputBorder` |
| `lib/typography.dart` | `AppTextStyle` |
| `lib/text.dart` | `TooltipText` / `HoverTooltip` / `TooltipLabel` / `EmojiFont` / `EmojiText` |
| `lib/context.dart` | `context.colorScheme` / `listTitleStyle` / `appBarInset` / `isMobileView` / `safeNestedPop` / … |
| `lib/metrics.dart` | 行高/栏高常量、`16.ap(context)` / `8.mAp(context)` |
| `lib/measure.dart` | `Measure` / `MeasureScope` |
| `lib/view_scope.dart` | `ViewScope`（必须自己提供） |
| `lib/card.dart` | `Card` / `Info` / `InfoHeader` / `SkipTraversalFocusNode` |
| `lib/press_surface.dart` | `PressSurface` |
| `lib/card_surface.dart` | `PressLook` / `CardSurface` |
| `lib/press_region.dart` | `PressRegion` |
| `lib/list_row.dart` | `ListRow` / `ListRowAlignment` |
| `lib/list.dart` | `ListHeader` / `ListFooter` / `ListSectionGap` / `generateGroup|Section|SliverSection` / `DecorationListItem` / `SelectedDecorationListItem` / `listItemRadiusOf` |
| `lib/list_row_separator.dart` | `part of list.dart`，private |
| `lib/prism_list.dart` | `PrismListView` / `SliverPrismList` / `PrismReorderableListView` / `ListController` |
| `lib/scroll.dart` | `Scrollbar` / `FloatingScrollbar` / `ScrollToEndBox` |
| `lib/selection_mark.dart` | `SelectionCheck` / `SelectionBadge` |
| `lib/common_button.dart` | `IconButton` / `TextButton` / `FilledButton` / `OutlinedButton` / `ButtonStyle` / `ButtonTheme` |
| `lib/button.dart` | `TonalButton` / `TonalButtonGroup` / `TonalButtonTheme` / `TonalButtonSize` / `MoreActionButton` |
| `lib/chip.dart` | `Chip` / `TonalChip` / `MetaChip` |
| `lib/switch.dart` / `checkbox.dart` / `slider.dart` / `segmented_control.dart` | 各控件 |
| `lib/text_field.dart` | `TextField` / `TextFormField` / `InputDecoration` / `InputDecorationTheme(Data)` / `InputDecorator` |
| `lib/search_field.dart` | `SearchField` |
| `lib/input.dart` | `SecretTextFormField` / `InputDialog` / `FilledInputTheme` |
| `lib/dialog.dart` | `showFloatingDialog` / `AlertDialog` / `AlertActions` / `AlertHostRoute` / `AlertMotionRouteMixin` |
| `lib/sheet.dart` | `showSheet` / `showFormSheet` / `showSnapSheet` / `showExtend` / `SheetProps` / `SheetType` |
| `lib/snap_sheet.dart` / `side_sheet.dart` / `form_sheet.dart` | 各 route |
| `lib/sheet_header.dart` | `SheetDragHandle` / `SheetToolBar` / `FloatingHeader` / `FloatingHeaderBody` |
| `lib/popup.dart` | `PopupAnchor` / `PopupMenu` / `PopupMenuItem` / `PopupMenuSection` / `PopupPlacement` / `AnchoredPopupRoute` / `PopupValueText` |
| `lib/context_menu.dart` | `ContextMenuRegion` |
| `lib/banner.dart` | `BannerHost` / `BannerLevel` |
| `lib/null_status.dart` | `NullStatus` / `NullStatusSwitcher` / `EmptyIllustration` / `Illustration` |
| `lib/loading.dart` | `ActivityIndicator` / `LoadingBar` / `ActivityPresence` |
| `lib/skeleton.dart` | `SkeletonText` / `SkeletonPill` |
| `lib/linear_progress.dart` / `divider.dart` / `tooltip.dart` | 各组件 |
| `lib/scaffold.dart` | `PrismScaffold` / `ScaffoldBar` / `AppBar` / `AppBarActionButton` / `AppBarClearance` |
| `lib/sidebar.dart` / `navigation_dock.dart` / `navigation_bar.dart` / `tab_view.dart` | 导航 |
| `lib/sortable.dart` | 排序模式、`DisclosureIndicator` / `DetailButton` |
| `lib/models.dart` | `IconButtonData` |
| `lib/inherited.dart` | 各种 scope + `sheetScrollController` |
| `lib/icons/` | `Glyph` / `GlyphIcon` / `Glyphs` / `AnimatedGlyph`（**需单独 import**） |
| `lib/liquid_glass.dart` / `goo.dart` / `press_sparkle.dart` | 玻璃 / goo / sparkle |
| `lib/motion.dart` / `page_transition.dart` / `navigator.dart` | 动画与路由 |

### 11.3 一页速记

```dart
// 表面：靠明度，不靠边框
Card(onPressed: ..., child: ListRow(leading: ..., title: Text(...), trailing: ...))

// 选中：加勾，不染色
trailing: isSelected ? const SelectionCheck() : null

// 颜色：一切都来自 scheme
color: context.colorScheme.onSurfaceVariant

// 圆角：token，不写数字
shape: AppShape.full          // 药丸
radius: AppCorner.xl          // 通栏

// 文字：命名样式
style: AppTextStyle.body.of(context, emphasized: true)

// 图标：glyph，不用字体
GlyphIcon(AppGlyphs.refresh, size: 20)

// 弹层：show* 函数 + 数据化菜单
await showFormSheet<void>(context: context, builder: (_) => MyForm(initial: v));
PopupAnchor(targetBuilder: (open) => IconButton(icon: ..., onPressed: open), popupBuilder: (_) => PopupMenu(items: [...]));

// 反馈：BannerHost
BannerHost.maybeOf(context)?.show('已保存', level: BannerLevel.success);
```
