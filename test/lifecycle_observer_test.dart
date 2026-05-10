import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcrash/src/crash_persistence.dart';
import 'package:xcrash/xcrash.dart';

void main() {
  late List<String> captured;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    captured = <String>[];
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: (s) async => captured.add(s));
  });

  tearDown(XCrashSDK.debugReset);

  // 通过一次 dummy report() 把 SDK 内部的面包屑 buffer 倒出来
  Future<List<Map<String, dynamic>>> drainCrumbs() async {
    captured.clear();
    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'drain',
      severity: Severity.info,
      message: 'flush',
    );
    final p = jsonDecode(captured.single) as Map<String, dynamic>;
    return (p['breadcrumbs'] as List).cast<Map<String, dynamic>>();
  }

  test('paused → markCleanShutdown + 写 paused 面包屑', () async {
    expect(await CrashPersistence.wasCleanShutdown(), isFalse);

    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.paused);
    // markCleanShutdown 是 unawaited，等串行化队列排干
    await CrashPersistence.loadPending();

    expect(await CrashPersistence.wasCleanShutdown(), isTrue);

    final crumbs = await drainCrumbs();
    final lifecycle = crumbs.where((c) => c['category'] == 'lifecycle');
    expect(lifecycle.any((c) => c['message'] == 'paused'), isTrue);
  });

  test('detached → markCleanShutdown（不写面包屑）', () async {
    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.detached);
    await CrashPersistence.loadPending();

    expect(await CrashPersistence.wasCleanShutdown(), isTrue);

    final crumbs = await drainCrumbs();
    final lifecycle = crumbs.where((c) => c['category'] == 'lifecycle');
    // detached 没写面包屑（与 paused 行为有别）
    expect(lifecycle.any((c) => c['message'] == 'detached'), isFalse);
  });

  test('resumed → 清掉 cleanShutdown + 写 resumed 面包屑 + 自增 foregroundCount',
      () async {
    // 先标记成"已干净退出"
    await CrashPersistence.markCleanShutdown();
    expect(await CrashPersistence.wasCleanShutdown(), isTrue);

    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.resumed);
    await CrashPersistence.loadPending();

    // resumed 必须清掉，否则前台崩溃会被误判为 clean
    expect(await CrashPersistence.wasCleanShutdown(), isFalse);

    final crumbs = await drainCrumbs();
    expect(
      crumbs.any((c) =>
          c['category'] == 'lifecycle' && c['message'] == 'resumed'),
      isTrue,
    );

    // foregroundCount 自增：从 drain 那条 report 的 session 字段验证
    final p = jsonDecode(captured.single) as Map<String, dynamic>;
    expect((p['session'] as Map)['foregroundCount'], greaterThanOrEqualTo(1));
  });

  test('inactive / hidden 都不写面包屑、不动 cleanShutdown', () async {
    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.inactive);
    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.hidden);
    await CrashPersistence.loadPending();

    expect(await CrashPersistence.wasCleanShutdown(), isFalse);

    final crumbs = await drainCrumbs();
    final lifecycle = crumbs.where((c) => c['category'] == 'lifecycle');
    expect(lifecycle, isEmpty);
  });

  test('resumed 清 cleanShutdown 防 background→foreground→crash 误判', () async {
    // 模拟一次完整循环：paused（写 clean）→ resumed（清 clean）→ 之后崩
    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.paused);
    await CrashPersistence.loadPending();
    expect(await CrashPersistence.wasCleanShutdown(), isTrue);

    XCrashSDK.debugDispatchLifecycle(AppLifecycleState.resumed);
    await CrashPersistence.loadPending();
    // 关键不变量：resumed 之后必须为 false，
    // 否则下次启动 detect 时会把这次"前台崩溃"误判为 clean shutdown
    expect(await CrashPersistence.wasCleanShutdown(), isFalse);
  });
}
