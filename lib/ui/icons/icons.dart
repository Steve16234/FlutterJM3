/// 图标只从这里取：prism_ui 的 glyph 原语 + 本应用自己的图标集。
///
/// prism_ui 的 barrel 不 export icons/，所以必须单独 import 这个文件。
library;

export 'package:prism_ui/icons/icons.dart';

export 'app_glyphs.dart';
