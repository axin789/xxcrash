import 'dart:convert';
import 'dart:ui' show PlatformDispatcher, ErrorCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcrash/xcrash.dart';

/// 一个 toString 每次返回不同字符串的异常 —— 验证旧版 dedup
/// （runtimeType + toString 哈希）会失效，新版（identityHashCode）能去重。
class _DynamicToStringError implements Exception {
  static int _i = 0;
  @override
  String toString() => 'dynamic-stuff-${_i++}';
}

void main() {
  late List<String> captured;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    captured = <String>[];
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: (s) async => captured.add(s));
    XCrashSDK.debugResetHookDedup();
  });

  tearDown(XCrashSDK.debugReset);

  Future<void> _settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  group('Hook dedup（identityHashCode 防多 hook 重报）', () {
    test('200ms 内同一异常对象第二次以后返回 true（被去重）', () {
      final err = StateError('boom');
      expect(XCrashSDK.debugCheckHookDedup(err), isFalse,
          reason: '冷启动第一条永远放行');
      expect(XCrashSDK.debugCheckHookDedup(err), isTrue,
          reason: '同一对象 200ms 内第二次应被去重');
      expect(XCrashSDK.debugCheckHookDedup(err), isTrue);
    });

    test('不同异常对象就算 toString 完全相同也不被合并', () {
      final a = StateError('boom');
      final b = StateError('boom'); // toString 一样，但 identity 不同
      expect(XCrashSDK.debugCheckHookDedup(a), isFalse);
      expect(XCrashSDK.debugCheckHookDedup(b), isFalse,
          reason:
              'identity 不同 = 真的发生了两次业务异常，必须分别上报，不能因为 toString 相同被吞');
    });

    test('toString 每次变的异常仍能去重（identityHashCode 兜底）', () {
      final err = _DynamicToStringError();
      expect(err.toString() == err.toString(), isFalse,
          reason: '前置：本异常 toString 确实每次不同');
      expect(XCrashSDK.debugCheckHookDedup(err), isFalse);
      expect(XCrashSDK.debugCheckHookDedup(err), isTrue,
          reason: '旧版用 toString 哈希这里会回归失败；新版按 identityHashCode 仍能去重');
    });

    test('200ms 窗口外不再去重', () async {
      final err = StateError('boom');
      expect(XCrashSDK.debugCheckHookDedup(err), isFalse);
      expect(XCrashSDK.debugCheckHookDedup(err), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(XCrashSDK.debugCheckHookDedup(err), isFalse,
          reason: '过了去重窗口，同一异常允许重新上报');
    });
  });

  group('Hook 链式转发：装 hook 前已设的 prev handler 不能被吞掉', () {
    late FlutterExceptionHandler? originalFlutterHandler;
    late ErrorCallback? originalPlatformHandler;

    setUp(() {
      originalFlutterHandler = FlutterError.onError;
      originalPlatformHandler = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = originalFlutterHandler;
      PlatformDispatcher.instance.onError = originalPlatformHandler;
    });

    test('FlutterError.onError：先调 prev handler，再走 SDK report',
        () async {
      var prevCalled = 0;
      FlutterError.onError = (details) {
        prevCalled++;
      };

      XCrashSDK.debugInstallHooks();

      // 触发一次 hook
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('build crashed'),
        stack: StackTrace.current,
      ));

      await _settle();

      expect(prevCalled, 1, reason: '用户原 handler 必须被链式调用');
      // 同时 SDK 走了 report
      final crashes = captured
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((p) => p['eventType'] == 'crash');
      expect(crashes, isNotEmpty);
      expect(crashes.first['context'], 'FlutterError');
    });

    test('PlatformDispatcher.onError：先调 prev handler，再走 SDK report',
        () async {
      var prevCalled = 0;
      PlatformDispatcher.instance.onError = (e, s) {
        prevCalled++;
        return false; // 用户原 handler 表示"未处理"
      };

      XCrashSDK.debugInstallHooks();

      // 触发一次 hook
      PlatformDispatcher.instance.onError!(
        StateError('async crashed'),
        StackTrace.current,
      );

      await _settle();

      expect(prevCalled, 1);
      final crashes = captured
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((p) => p['eventType'] == 'crash');
      expect(crashes, isNotEmpty);
      expect(crashes.first['context'], 'PlatformDispatcher');
    });

    test('PlatformDispatcher.onError：尊重 prev handler 的 bool 返回值',
        () async {
      PlatformDispatcher.instance.onError = (e, s) => true; // 用户表示已处理

      XCrashSDK.debugInstallHooks();

      final ret = PlatformDispatcher.instance.onError!(
        StateError('handled'),
        StackTrace.current,
      );
      expect(ret, isTrue, reason: 'SDK 应转发 prev handler 的返回值');
    });

    test('Hook 内部 prev handler 抛异常不影响 SDK 自己的上报',
        () async {
      FlutterError.onError = (details) {
        throw Exception('prev handler bug');
      };

      XCrashSDK.debugInstallHooks();

      // 不应该 rethrow
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('payload'),
        stack: StackTrace.current,
      ));

      await _settle();

      // SDK 自己的 report 仍然走了
      final crashes = captured
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((p) => p['eventType'] == 'crash');
      expect(crashes, isNotEmpty);
    });
  });
}
