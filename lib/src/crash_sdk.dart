import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'breadcrumb/breadcrumb.dart';
import 'breadcrumb/breadcrumb_buffer.dart';
import 'deviceinfo.dart';
import 'event_type.dart';
import 'report_limiter.dart';
import 'session.dart';

/// 交给宿主工程的 HTTP 请求层。SDK 只负责拼好 JSON 字符串，
/// 由宿主决定走哪个接口、怎么鉴权、怎么重试。
typedef ContentSender = Future<void> Function(String content);

/// 统一的崩溃 / 异常 / 业务 / 视频 / 接口错误上报 SDK。
///
/// 使用方式：
/// ```dart
/// void main() {
///   XCrashSDK.init(
///     appRunner: () async => runApp(MyApp()),
///     userProvider: () => { 'uid': AuthService.uid },
///     sender: (content) => HttpUtils.post(
///       '/system/track',
///       data: { 'content': content },
///     ),
///     reportConfigs: {'DioError': 10},
///   );
/// }
/// ```
class XCrashSDK {
  static ContentSender? _sender;
  static Map<String, dynamic>? Function()? _userProvider;
  static Map<String, dynamic> _appData = const {};
  static Map<String, dynamic> _deviceData = const {};
  static bool _inited = false;
  static bool _enabled = false;
  static final BreadcrumbBuffer _breadcrumbs = BreadcrumbBuffer(capacity: 50);

  /// 默认限频：DioError 累计 10 次才首报，之后按 interval。
  static const _defaultReportConfigs = {'DioError': 10};

  /// 初始化入口。只能调用一次，二次调用会被忽略。
  static void init({
    required ContentSender sender,
    required Map<String, dynamic>? Function() userProvider,
    required Future<void> Function() appRunner,
    Map<String, int>? reportConfigs,
    int intervalMs = 60 * 1000,
  }) {
    if (_inited) return;
    _sender = sender;
    _userProvider = userProvider;

    Session.init();

    runZonedGuarded(
      () async {
        await appRunner();

        ErrorReportLimiter.setStartReportThresholds(
          reportConfigs ?? _defaultReportConfigs,
        );
        ErrorReportLimiter.setIntervalMs(intervalMs);
        ErrorReportLimiter.setReportEnabled(true);

        final packageInfo = await PackageInfo.fromPlatform();
        final deviceInfo = await getDeviceInfo();
        _appData = packageInfo.data;
        _deviceData = deviceInfo;
        _inited = true;
        _enabled = true;

        _hookFlutterError();
      },
      (error, stack) {
        report(
          type: EventType.crash,
          subKey: error.runtimeType.toString(),
          severity: Severity.fatal,
          message: error.toString(),
          error: error,
          stack: stack,
          context: 'runZonedGuarded',
        );
      },
    );
  }

  static void _hookFlutterError() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(
        type: EventType.crash,
        subKey: details.exception.runtimeType.toString(),
        severity: Severity.fatal,
        message: details.exception.toString(),
        error: details.exception,
        stack: details.stack ?? StackTrace.current,
        context: 'FlutterError',
      );
    };
  }

  /// 所有上报的唯一入口。
  ///
  /// - [type]     事件分类（crash / video / api / business）
  /// - [subKey]   限频 key 的后半段，粒度自行把控；
  ///              crash 用 `runtimeType`，api 用 `path:status`，
  ///              video 用 `buffer_stall` / `decode_error` 等语义标签。
  /// - [severity] 严重级别
  /// - [message]  单行人类可读摘要
  /// - [error]    原始错误对象（可选，crash/业务异常时传）
  /// - [stack]    堆栈（可选）
  /// - [context]  触发场景字符串（路由/接口路径/播放器 id 等）
  /// - [data]     类型相关的结构化字段
  static Future<void> report({
    required EventType type,
    required String subKey,
    required Severity severity,
    required String message,
    Object? error,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? data,
  }) async {
    if (!_enabled) return;

    // 1. 已知无意义异常直接丢弃
    if (error != null && _shouldIgnore(error)) return;

    // 2. 所有类型统一走限频器，key = "${type}:${subKey}"
    final limiterKey = '${type.value}:$subKey';
    final suppressed = ErrorReportLimiter.shouldReport(
      limiterKey,
      context: context,
      error: error,
      stackTrace: stack,
    );
    if (suppressed == null) return;

    final suppressedPaths =
        ErrorReportLimiter.takeSuppressedContexts(limiterKey);

    // 3. 组装 payload
    final payload = <String, dynamic>{
      'eventType': type.value,
      'subKey': subKey,
      'severity': severity.value,
      'timestamp': DateTime.now().toIso8601String(),
      'session': Session.toMap(),
      'app': _appData,
      'device': _deviceData,
      'user': _userProvider?.call(),
      'message': message,
      if (error != null)
        'error': {
          'type': error.runtimeType.toString(),
          'message': error.toString(),
          if (stack != null) 'stack': _trimStack(stack, maxLines: 50),
        },
      if (context != null) 'context': context,
      if (data != null) 'data': data,
      'breadcrumbs': _breadcrumbs.snapshot(),
      'suppressedCount': suppressed,
      if (suppressedPaths.isNotEmpty) 'suppressedContexts': suppressedPaths,
    };

    // 4. 交给宿主的 sender；异常吞掉，不影响 App
    try {
      await _sender?.call(jsonEncode(payload));
    } catch (e) {
      debugPrint('[XCrashSDK] sender failed: $e');
    }

    // 5. 同时把这次上报写入面包屑，后续事件可以看到"刚才报了什么"
    leaveBreadcrumb(
      category: type.value,
      level: severity.value,
      message: '$subKey: $message',
    );
  }

  /// 添加面包屑（业务主动调用；也可挂 NavigatorObserver / Dio Interceptor 自动采集）
  static void leaveBreadcrumb({
    required String category,
    required String message,
    String level = 'info',
    Map<String, dynamic>? data,
  }) {
    _breadcrumbs.add(Breadcrumb(
      category: category,
      message: message,
      level: level,
      data: data,
    ));
  }

  // ---------- 便捷封装 ----------

  /// 视频播放异常上报。
  ///
  /// [subKey] 推荐取值：`buffer_stall` / `playback_error` /
  /// `decode_error` / `visual_glitch` / `first_frame_timeout`。
  static Future<void> reportVideoError({
    required String subKey,
    required String videoUrl,
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stack,
    Severity severity = Severity.warning,
  }) {
    return report(
      type: EventType.video,
      subKey: subKey,
      severity: severity,
      message: 'video $subKey',
      error: error,
      stack: stack,
      context: videoUrl,
      data: {
        'videoUrl': videoUrl,
        if (extra != null) ...extra,
      },
    );
  }

  /// 接口错误上报。典型 Dio 拦截器里调用。
  /// subKey 默认为 `path:status`，方便后台按路径聚合。
  static Future<void> reportApiError({
    required String path,
    required int statusCode,
    required String method,
    int? durationMs,
    String? errno,
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stack,
  }) {
    return report(
      type: EventType.api,
      subKey: '$path:$statusCode',
      severity: Severity.warning,
      message: '$method $path -> $statusCode',
      error: error,
      stack: stack,
      context: path,
      data: {
        'path': path,
        'method': method,
        'status': statusCode,
        if (durationMs != null) 'durationMs': durationMs,
        if (errno != null) 'errno': errno,
        if (extra != null) ...extra,
      },
    );
  }

  /// 业务逻辑错误上报（支付失败、登录异常、风控触发等）。
  static Future<void> reportBusinessError({
    required String scene,
    required String message,
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stack,
    Severity severity = Severity.error,
  }) {
    return report(
      type: EventType.business,
      subKey: scene,
      severity: severity,
      message: message,
      error: error,
      stack: stack,
      context: scene,
      data: extra,
    );
  }

  // ---------- 外部只读 ----------

  static Map<String, dynamic>? get userData => _userProvider?.call();
  static Map<String, dynamic> get appData => _appData;
  static Map<String, dynamic> get deviceData => _deviceData;
  static bool get isInitialized => _inited;
  static bool get isEnabled => _enabled;

  /// 手动清空限频器（切换用户/退出登录时调用一次即可）
  static void cleanData() => ErrorReportLimiter.clear();

  // ---------- 内部 ----------

  /// 永久忽略规则。Flutter 里两个最常见又完全没用的异常。
  static bool _shouldIgnore(Object error) {
    final msg = error.toString();
    return msg.contains('Looking up a deactivated widget') ||
        msg.contains('setState() called after dispose');
  }

  static String _trimStack(StackTrace stack, {int maxLines = 50}) {
    final lines = stack.toString().split('\n');
    if (lines.length <= maxLines) return stack.toString();
    return '${lines.take(maxLines).join('\n')}\n... (${lines.length - maxLines} more)';
  }
}
