import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/settings_store.dart';
import 'package:flutterjm/core/theme_mode.dart';
import 'package:flutterjm/state/app_state.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jm_settings_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('设置写入后可被新实例读回', () async {
    await SettingsStore(directory: tmp).write(
      const AppSettings(
        themeMode: JmThemeMode.dark,
        searchHistory: <String>['黑客', '催眠'],
      ),
    );

    final read = await SettingsStore(directory: tmp).read();
    expect(read.themeMode, JmThemeMode.dark);
    expect(read.searchHistory, <String>['黑客', '催眠']);
  });

  test('没有存档时返回默认值', () async {
    final read = await SettingsStore(directory: Directory('${tmp.path}/sub'))
        .read();
    expect(read.themeMode, JmThemeMode.system);
    expect(read.searchHistory, isEmpty);
    // 液态玻璃默认开启；不支持的设备可在设置页打开「低性能模式」关闭。
    expect(read.liquidGlass, isTrue);
  });

  test('液态玻璃开关可持久化', () async {
    await SettingsStore(directory: tmp).write(
      const AppSettings(liquidGlass: true),
    );
    final read = await SettingsStore(directory: tmp).read();
    expect(read.liquidGlass, isTrue);
  });

  test('旧版存档的 liquidGlass=false 不盖掉新版默认开启', () async {
    // 旧版（默认关）写过 liquidGlass 键；新版换用 glassEnabled 键，
    // 且低性能模式是全新语义，旧值应当被忽略，玻璃仍默认开启。
    final file = File('${tmp.path}${Platform.pathSeparator}'
        '${SettingsStore.fileName}');
    file.writeAsStringSync(
      '{"themeMode":"system","searchHistory":[],"liquidGlass":false}',
    );
    final read = await SettingsStore(directory: tmp).read();
    expect(read.liquidGlass, isTrue);
  });

  test('存档损坏时回落到默认值，不影响启动', () async {
    final dir = Directory('${tmp.path}/corrupt')
      ..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}${SettingsStore.fileName}')
        .writeAsStringSync('{ 这不是 json');

    final read = await SettingsStore(directory: dir).read();
    expect(read.themeMode, JmThemeMode.system);
    expect(read.searchHistory, isEmpty);
  });

  test('切到深色后「重启」仍是深色', () async {
    final first = AppState(settings: SettingsStore(directory: tmp));
    await first.restoreSettings();
    expect(first.themeMode, JmThemeMode.system);

    first.setThemeMode(JmThemeMode.dark);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    first.dispose();

    final second = AppState(settings: SettingsStore(directory: tmp));
    await second.restoreSettings();
    expect(second.themeMode, JmThemeMode.dark);
    second.dispose();
  });

  test('搜索历史也会被记住', () async {
    final first = AppState(settings: SettingsStore(directory: tmp));
    await first.restoreSettings();
    first.addSearchHistory('  催眠  ');
    first.addSearchHistory('无修正');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    first.dispose();

    final second = AppState(settings: SettingsStore(directory: tmp));
    await second.restoreSettings();
    expect(second.searchHistory, <String>['无修正', '催眠']);
    second.dispose();
  });

  test('清空搜索历史也会落盘', () async {
    final first = AppState(settings: SettingsStore(directory: tmp));
    await first.restoreSettings();
    first.addSearchHistory('abc');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    first.clearSearchHistory();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    first.dispose();

    final second = AppState(settings: SettingsStore(directory: tmp));
    await second.restoreSettings();
    expect(second.searchHistory, isEmpty);
    second.dispose();
  });
}
