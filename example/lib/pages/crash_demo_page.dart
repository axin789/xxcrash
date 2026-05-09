import 'dart:async';

import 'package:flutter/material.dart';

/// 触发三种不同路径的 Dart 崩溃，验证 XCrashSDK 挂载的 hook：
///
/// 1. 在 build 里调 `FlutterError.reportError` → `FlutterError.onError` 捕获
/// 2. zone 内抛未捕获 async 异常           → `runZonedGuarded` 捕获
/// 3. 从 `Timer.run` 里抛 zone 外异常       → `PlatformDispatcher.onError` 捕获
///
/// 每个按钮点下去都会在 sender 日志里出现一条 `eventType: crash` 的上报。
class CrashDemoPage extends StatelessWidget {
  static const route = '/crash';
  const CrashDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('崩溃捕获 demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Hint(
            '下列按钮会真的把异常抛到框架里。debug 模式会看到红屏/报错，'
            '这是正常现象——SDK 已经同步把事件上报给 sender。',
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              // build/layout/paint 阶段常见：FlutterError.reportError 是官方入口。
              FlutterError.reportError(FlutterErrorDetails(
                exception: StateError('demo FlutterError'),
                stack: StackTrace.current,
                library: 'xcrash_example',
                context: ErrorDescription('manually triggered from demo'),
              ));
              _toast(context, 'FlutterError.onError → crash 已上报');
            },
            child: const Text('1. 触发 FlutterError.onError'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              // 走业务 zone 内的异步路径，runZonedGuarded 会兜住。
              Future<void>.delayed(const Duration(milliseconds: 50), () {
                throw StateError('demo uncaught async in zone');
              });
              _toast(context, 'runZonedGuarded → crash 50ms 后上报');
            },
            child: const Text('2. 抛 zone 内未捕获 async 异常'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              // Timer.run 的回调脱离当前 zone，runZonedGuarded 抓不到，
              // PlatformDispatcher.onError 负责兜底。
              Timer.run(() {
                throw StateError('demo outside runZonedGuarded');
              });
              _toast(context, 'PlatformDispatcher.onError → crash 已上报');
            },
            child: const Text('3. 抛 zone 外异常（Timer.run）'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => throw Exception('demo sync throw from onPressed'),
            child: const Text('4. 同步 throw（框架会按回调异常处理）'),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}
