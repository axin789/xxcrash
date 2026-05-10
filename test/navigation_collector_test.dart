import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcrash/xcrash.dart';

/// 不挂 Navigator —— 直接构造 mock route 调 observer 的 callback，
/// 这样测的是 BreadcrumbNavigatorObserver 自己的逻辑，不被
/// `pumpAndSettle` 在 desktop binding 上偶尔死等的问题拖死。
class _NamedRoute extends Route<void> {
  @override
  final RouteSettings settings;
  _NamedRoute(String name) : settings = RouteSettings(name: name);
}

class _AnonRoute extends Route<void> {
  @override
  final RouteSettings settings = const RouteSettings();
}

/// 通过一次 dummy report() 把 SDK 内部面包屑 buffer 的快照倒出来。
Future<List<Map<String, dynamic>>> _drain(List<String> captured) async {
  captured.clear();
  await XCrashSDK.report(
    type: EventType.business,
    subKey: 'drain',
    severity: Severity.info,
    message: 'flush',
  );
  expect(captured.length, 1);
  final p = jsonDecode(captured.single) as Map<String, dynamic>;
  return (p['breadcrumbs'] as List).cast<Map<String, dynamic>>();
}

void main() {
  late List<String> captured;
  late BreadcrumbNavigatorObserver observer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    captured = <String>[];
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: (s) async => captured.add(s));
    observer = BreadcrumbNavigatorObserver();
  });

  tearDown(XCrashSDK.debugReset);

  test('didPush 写入 navigation 面包屑（带 from / to）', () async {
    observer.didPush(_NamedRoute('/detail'), _NamedRoute('/'));

    final crumbs = await _drain(captured);
    final navs =
        crumbs.where((c) => c['category'] == 'navigation').toList();
    expect(navs, isNotEmpty);

    final pushDetail =
        navs.firstWhere((c) => (c['message'] as String).contains('/detail'));
    expect(pushDetail['message'], 'push /detail');
    expect(pushDetail['data']['to'], '/detail');
    expect(pushDetail['data']['from'], '/');
  });

  test('didPop 写入 navigation 面包屑', () async {
    observer.didPop(_NamedRoute('/detail'), _NamedRoute('/'));

    final crumbs = await _drain(captured);
    final pops = crumbs.where(
      (c) =>
          c['category'] == 'navigation' &&
          (c['message'] as String).startsWith('pop'),
    );
    expect(pops, isNotEmpty);
    final pop = pops.first;
    expect(pop['message'], 'pop /detail');
    expect(pop['data']['from'], '/detail');
    expect(pop['data']['to'], '/');
  });

  test('didReplace 写入 from→to', () async {
    observer.didReplace(
      newRoute: _NamedRoute('/profile'),
      oldRoute: _NamedRoute('/login'),
    );

    final crumbs = await _drain(captured);
    final rep = crumbs.firstWhere(
      (c) =>
          c['category'] == 'navigation' &&
          (c['message'] as String).startsWith('replace'),
    );
    expect(rep['message'], 'replace /login -> /profile');
    expect(rep['data']['from'], '/login');
    expect(rep['data']['to'], '/profile');
  });

  test('didRemove 只记 route 名（无 from/to data）', () async {
    observer.didRemove(_NamedRoute('/dialog'), _NamedRoute('/'));

    final crumbs = await _drain(captured);
    final rm = crumbs.firstWhere(
      (c) =>
          c['category'] == 'navigation' &&
          (c['message'] as String).startsWith('remove'),
    );
    expect(rm['message'], 'remove /dialog');
    // didRemove 没填 data
    expect(rm['data'], isNull);
  });

  test('未命名路由 fallback 用 runtimeType 作为名字', () async {
    observer.didPush(_AnonRoute(), null);

    final crumbs = await _drain(captured);
    final nav = crumbs.firstWhere(
      (c) =>
          c['category'] == 'navigation' &&
          (c['message'] as String).contains('_AnonRoute'),
    );
    expect(nav['data']['to'], contains('_AnonRoute'));
    expect(nav['data']['from'], isNull);
  });
}
