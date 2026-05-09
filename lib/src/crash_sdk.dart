import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher, ErrorCallback;

import 'package:flutter/foundation.dart'
    show
        FlutterExceptionHandler,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'breadcrumb/breadcrumb.dart';
import 'breadcrumb/breadcrumb_buffer.dart';
import 'crash_persistence.dart';
import 'deviceinfo.dart';
import 'event_type.dart';
import 'integrations/telegram_sender.dart';
import 'report_limiter.dart';
import 'session.dart';

/// 把组装好的 JSON 字符串交给宿主工程的 HTTP 层。
/// SDK 不关心怎么发、怎么鉴权、怎么重试。
typedef ContentSender = Future<void> Function(String content);

/// 统一的崩溃 / 视频 / 接口 / 业务错误上报 SDK。
///
/// 使用方式：
/// ```dart
/// XCrashSDK.init(
///   appRunner: () async => runApp(const MyApp()),
///   userProvider: () => {'uid': AuthService.uid},
///   sender: (content) => HttpUtils.post(
///     '/system/track',
///     data: {'content': content},
///   ),
///   reportConfigs: {'video:buffer_stall': 5},
/// );
/// ```
class XCrashSDK {
  XCrashSDK._();

  static ContentSender? _sender;
  static TelegramSender? _telegramSender;
  static Map<String, dynamic>? Function()? _userProvider;
  static Map<String, dynamic> _appData = const {};
  static Map<String, dynamic> _deviceData = const {};
  static bool _inited = false;
  static final BreadcrumbBuffer _breadcrumbs = BreadcrumbBuffer(capacity: 50);

  /// Hook 去重窗口：同一个 error 被 FlutterError + PlatformDispatcher 并发
  /// 回调时只上报一次（阈值 200ms，正好卡掉双路重入，不影响真的短时连续错误）。
  static int _lastHookErrorHash = 0;
  static int _lastHookErrorMs = 0;

  /// 安装 hook 前用户已经设置过的 handler，我们会链式转发，不吞掉它们。
  static FlutterExceptionHandler? _prevFlutterErrorHandler;
  static ErrorCallback? _prevPlatformErrorHandler;

  /// 单条 stack 文本的硬上限（AOT obfuscated stack 常常不换行，按行截没用）。
  static const int _maxStackChars = 8 * 1024;

  /// 默认起步阈值：`DioException`（Dio 5+）和 `DioError`（Dio 4.x 兼容）
  /// 累计 10 次才允许首次上报。消费者可用 `reportConfigs` 覆盖。
  static const _defaultReportConfigs = {
    'DioException': 10,
    'DioError': 10,
  };

  /// 初始化入口。重复调用会被忽略。
  ///
  /// [sender]   主通道：收到 JSON 字符串，交给宿主自己的 HTTP 层上报。
  /// [telegram] 可选的并联通道；给出就自动把格式化后的消息发给 Telegram bot。
  static void init({
    required ContentSender sender,
    required Map<String, dynamic>? Function() userProvider,
    required Future<void> Function() appRunner,
    Map<String, int>? reportConfigs,
    int intervalMs = 60 * 1000,
    TelegramConfig? telegram,
  }) {
    if (_inited) return;
    _sender = sender;
    _telegramSender = telegram != null ? TelegramSender(telegram) : null;
    _userProvider = userProvider;

    // 同步预填最小平台指纹：`_loadPlatformInfo` 是 unawaited 的，
    // 在它 resolve 前如果崩溃，起码后端还能知道是哪个 platform 的事件，
    // 不至于把不同 OS 的崩溃合并到同一 bucket。
    _deviceData = _seedDeviceData();

    Session.init();
    ErrorReportLimiter.setStartReportThresholds(
      reportConfigs ?? _defaultReportConfigs,
    );
    ErrorReportLimiter.setIntervalMs(intervalMs);
    ErrorReportLimiter.setReportEnabled(true);
    _inited = true;
    _hookFlutterError();
    _hookPlatformDispatcher();

    runZonedGuarded(
      () async {
        await appRunner();
        _hookLifecycle();
        unawaited(_loadPlatformInfo());
        // appRunner 完成 = WidgetsFlutterBinding 已初始化 = SharedPreferences 可用。
        // 顺序要求：先跑"上次疑似崩溃检测"（读的是上一轮的心跳），
        // 再写本次的 boot 心跳（覆盖上一轮），否则会把自己当作"上次状态"。
        unawaited(_flushPendingAndDetectLastCrash().then((_) {
          // boot 心跳：从此刻起任何 native crash 都能在下次启动被检测到
          return CrashPersistence.writeHeartbeat(
            {'type': 'boot', 'sessionId': Session.id},
            breadcrumbs: _breadcrumbs.snapshot(),
          );
        }));
      },
      (error, stack) {
        if (_shouldDedupHookCrash(error)) return;
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

  /// 启动时补报上次进程没送完的 payload，并检测是否疑似 native 崩溃。
  static Future<void> _flushPendingAndDetectLastCrash() async {
    // 1. 补报上次积压的。loadPendingForRetry 顺手丢弃毒丸 / 过期条目；
    //    attempt 计数推迟到本轮 dispatch 真的失败之后再 bump。
    final pending = await CrashPersistence.loadPendingForRetry();
    for (final entry in pending) {
      final senderOk = await _dispatchToSender(entry.payload);
      // Telegram 是辅助通道，失败不阻塞主上报。fire-and-forget。
      if (_telegramSender != null) {
        unawaited(_dispatchToTelegram(entry.payload));
      }
      if (senderOk) {
        await CrashPersistence.removePending(entry.id);
      } else {
        await CrashPersistence.bumpPendingAttempt(entry.id);
      }
    }

    // 2. 检测上次是否异常退出：有心跳但没有正常退出标记
    final lastHeartbeat = await CrashPersistence.readHeartbeat();
    final cleanShutdown = await CrashPersistence.wasCleanShutdown();
    if (lastHeartbeat != null && !cleanShutdown) {
      // 跳过"裸 boot 心跳"：init() 自己写的 boot 心跳之后还没发生任何业务行为
      // （面包屑空），下次启动看到这条无法区分"native crash" / "用户主动
      // swipe-kill" / "iOS 后台 jetsam"，信噪比太低。直接吞掉，
      // 否则用户每次冷启动后立刻杀进程都会产生一条假崩溃。
      final state = lastHeartbeat['state'];
      final crumbs = lastHeartbeat['breadcrumbs'] as List?;
      final isStubBoot = state is Map &&
          state['type'] == 'boot' &&
          (crumbs == null || crumbs.isEmpty);
      if (isStubBoot) return;

      await report(
        type: EventType.crash,
        subKey: 'suspected_native_crash',
        severity: Severity.fatal,
        message: '上次运行异常退出（未检测到正常关闭）',
        context: 'suspected_native_crash',
        data: {
          'lastHeartbeatTs': lastHeartbeat['ts'],
          'lastHeartbeatState': lastHeartbeat['state'],
          if (lastHeartbeat['breadcrumbs'] != null)
            'lastBreadcrumbs': lastHeartbeat['breadcrumbs'],
        },
      );
    }
  }

  /// 所有上报的唯一入口。
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
    if (!_inited) return;
    if (error != null && _shouldIgnore(error)) return;

    final key = ErrorReportLimiter.keyOf(type.name, subKey);
    final suppressed = ErrorReportLimiter.shouldReport(
      key,
      context: context,
      error: error,
    );
    if (suppressed == null) return;

    final suppressedPaths = ErrorReportLimiter.takeSuppressedContexts(key);

    final payload = <String, dynamic>{
      'eventType': type.name,
      'subKey': subKey,
      'severity': severity.name,
      'timestamp': DateTime.now().toIso8601String(),
      'session': Session.toMap(),
      'app': _appData,
      'device': _deviceData,
      'user': _safeUser(),
      'message': message,
      if (error != null)
        'error': {
          'type': error.runtimeType.toString(),
          'message': error.toString(),
          if (stack != null) 'stack': _trimStack(stack),
        },
      if (context != null) 'context': context,
      if (data != null) 'data': data,
      'breadcrumbs': _breadcrumbs.snapshot(),
      'suppressedCount': suppressed,
      if (suppressedPaths.isNotEmpty) 'suppressedContexts': suppressedPaths,
    };

    // 先落盘：万一进程在发送途中死掉，下次启动还能补报。
    final pendingId = await CrashPersistence.addPending(payload);

    // 主通道：必须 await + 拿到结果才能决定 pending 落盘条目去留。
    final senderOk = await _dispatchToSender(payload);
    // 辅助通道：fire-and-forget。Telegram 失败不影响主流程，也不阻塞 caller。
    if (_telegramSender != null) {
      unawaited(_dispatchToTelegram(payload));
    }

    if (pendingId != null && senderOk) {
      await CrashPersistence.removePending(pendingId);
    }

    leaveBreadcrumb(
      category: type.name,
      level: severity.name,
      message: '$subKey: $message',
    );
  }

  /// 写一条"当前正在做 X"的心跳。
  ///
  /// 如果进程死在做这件事的途中（比如某个视频 URL），
  /// 下次启动时 SDK 会读到这条心跳并合成一条 `suspected_native_crash`
  /// 事件上报，便于远端定位。
  ///
  /// 建议挂载点：视频切源、路由切换、长耗时业务的入口。
  ///
  /// 心跳会自动附带当前面包屑快照，下次崩溃上报时作为"死前时间轴"。
  static Future<void> updateHeartbeat(Map<String, dynamic> state) async {
    if (!_inited) return;
    await CrashPersistence.writeHeartbeat(
      state,
      breadcrumbs: _breadcrumbs.snapshot(),
    );
  }

  /// 把 pending 队列里所有未送出的 payload 立刻尝试发送一次。
  ///
  /// 典型场景：用户即将 logout / 切账号，希望在 token 失效之前把残余崩溃报
  /// 出去。语义是"尽力一次"而不是"等到成功"——发送失败的 payload 仍然留在
  /// 队列里走正常的下次启动重发流程，不会卡住调用方。
  ///
  /// 与启动时的补发路径不同：这里走 [CrashPersistence.loadPending]（只读），
  /// **不** bump attempt 计数，不会因为用户多次 flush 而把 payload 推向毒丸。
  static Future<void> flush() async {
    if (!_inited) return;
    final pending = await CrashPersistence.loadPending();
    for (final entry in pending) {
      final senderOk = await _dispatchToSender(entry.payload);
      if (_telegramSender != null) {
        unawaited(_dispatchToTelegram(entry.payload));
      }
      if (senderOk) {
        await CrashPersistence.removePending(entry.id);
      }
      // flush 路径不 bump attempt：用户可能多次主动 flush，
      // 不应该把"网络暂时不通"惩罚成毒丸。
    }
  }

  /// 清掉所有持久化状态（pending 队列 / heartbeat / cleanShutdown 标记）。
  ///
  /// 典型场景：用户切账号，避免上一个账号的崩溃（带着旧 user uid）被本账号
  /// 上报；或测试期间重置环境。注意：内存里的限频器、面包屑、session 不受
  /// 影响——如有需要请额外调 [ErrorReportLimiter.clear]。
  static Future<void> clearPersistence() => CrashPersistence.clearAll();

  /// 添加一条面包屑。业务主动调用，或由 collector 自动写入。
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

  /// 拼接限频 key 的规范方法，写 `reportConfigs` 时用它避免拼错：
  ///
  /// ```dart
  /// reportConfigs: {
  ///   XCrashSDK.limiterKey(EventType.video, 'buffer_stall'): 5,
  /// }
  /// ```
  static String limiterKey(EventType type, String subKey) =>
      ErrorReportLimiter.keyOf(type.name, subKey);

  // ---------- 便捷封装 ----------

  /// 视频播放异常上报。
  ///
  /// [subKey] 推荐：`playback_error` / `buffer_stall` / `decode_error` /
  /// `first_frame_timeout` / `visual_glitch`。
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
      data: {'videoUrl': videoUrl, if (extra != null) ...extra},
    );
  }

  /// 接口错误上报（典型在 Dio 拦截器里调用）。
  ///
  /// 注意：[path] 建议传模板化的形式（`/user/:id` 而非 `/user/123`），
  /// 否则限频器的 key 会因为路径里带动态 id 而爆炸性增长。
  static Future<void> reportApiError({
    required String path,
    required String method,
    required int statusCode,
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

  /// 业务逻辑错误上报。
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

  // ---------- 测试钩子 ----------

  /// 仅用于测试：绕过 init 的 runZoned/PackageInfo 路径，
  /// 直接把 SDK 置为已初始化。生产代码不要调。
  @visibleForTesting
  static void debugForceEnable({
    required ContentSender sender,
    Map<String, dynamic>? Function()? userProvider,
    Map<String, dynamic> appData = const {'version': 'test'},
    Map<String, dynamic> deviceData = const {'platform': 'test'},
    TelegramConfig? telegram,
  }) {
    _sender = sender;
    _telegramSender = telegram != null ? TelegramSender(telegram) : null;
    _userProvider = userProvider;
    _appData = appData;
    _deviceData = deviceData;
    _inited = true;
    Session.init();
    ErrorReportLimiter.setReportEnabled(true);
  }

  /// 仅用于测试：等价于 init 里对上次运行状态的检测与 pending 重发。
  /// 先在 SharedPreferences 里准备好 heartbeat / cleanShutdown / pending，
  /// 然后 [debugForceEnable] + 调这个方法即可验证端到端补报流程。
  @visibleForTesting
  static Future<void> debugFlushPendingAndDetectLastCrash() =>
      _flushPendingAndDetectLastCrash();

  /// 仅用于测试：重置所有静态状态。
  @visibleForTesting
  static void debugReset() {
    _inited = false;
    _sender = null;
    _telegramSender = null;
    _userProvider = null;
    _appData = const {};
    _deviceData = const {};
    _lastHookErrorHash = 0;
    _lastHookErrorMs = 0;
    _prevFlutterErrorHandler = null;
    _prevPlatformErrorHandler = null;
    _breadcrumbs.clear();
    ErrorReportLimiter.clear();
    ErrorReportLimiter.setReportEnabled(false);
    // ignore: invalid_use_of_visible_for_testing_member
    Session.debugReset();
  }

  // ---------- 内部 ----------

  /// 包了一层 try/catch 调用宿主提供的 [userProvider]：
  /// 业务侧的 provider 可能在登录态过期 / `Provider.of` 错误上下文里抛，
  /// 不能因为它崩了把整条 report 一起搞挂。返回 null = 本次报告不带 user。
  static Map<String, dynamic>? _safeUser() {
    try {
      return _userProvider?.call();
    } catch (e) {
      debugPrint('[XCrashSDK] userProvider threw: $e');
      return null;
    }
  }

  static Future<bool> _dispatchToSender(Map<String, dynamic> payload) async {
    final sender = _sender;
    if (sender == null) return false;
    try {
      await sender(jsonEncode(payload));
      return true;
    } catch (e) {
      debugPrint('[XCrashSDK] sender failed: $e');
      return false;
    }
  }

  static Future<bool> _dispatchToTelegram(Map<String, dynamic> payload) async {
    // TelegramSender 内部已自吞，这里再套一层保险，并返回成功标识。
    try {
      await _telegramSender?.send(payload);
      return true;
    } catch (e) {
      debugPrint('[XCrashSDK] telegram failed: $e');
      return false;
    }
  }

  static Future<void> _loadPlatformInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = await getDeviceInfo();
      _appData = packageInfo.data;
      _deviceData = deviceInfo;
    } catch (e) {
      debugPrint('[XCrashSDK] platform info load failed: $e');
    }
  }

  static Map<String, dynamic> _seedDeviceData() {
    // 用 foundation 提供的 `defaultTargetPlatform` / `kIsWeb`，不碰 `dart:io`，
    // 这样 SDK 能编译进 Flutter web（哪怕 web 上完整的 device_info 等异步接入
    // 尚未 resolve，也至少带了个 platform 字段）。
    //
    // 必须 `toLowerCase()`：`TargetPlatform.iOS.name == 'iOS'`，但
    // `getDeviceInfo()` 里 iOS 分支硬编码的是 `'ios'`。如果不小写化，
    // _loadPlatformInfo resolve 之前的崩溃带 platform=`iOS`，之后带 `ios`，
    // 后端按 platform 聚合时会被拆成两个 bucket。
    return {
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
      'debugMode': kDebugMode,
    };
  }

  static void _hookFlutterError() {
    _prevFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // 先把上一层 handler（通常是 FlutterError.presentError）跑完，
      // 不要吞掉用户可能已经设的链。
      try {
        _prevFlutterErrorHandler?.call(details);
      } catch (_) {}
      if (_shouldDedupHookCrash(details.exception)) return;
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

  /// 覆盖 runZonedGuarded 抓不到的少数异步异常（如在 zone 外启动的
  /// Timer、某些 plugin 的回调）。Flutter 3.1+ 官方推荐与 runZonedGuarded
  /// 搭配使用，不是替代关系。
  ///
  /// 返回 true 表示已处理，Flutter 不再打印到 stderr。如果用户之前设过
  /// 自己的 handler，我们用它的返回值（否则默认 true）。
  static void _hookPlatformDispatcher() {
    _prevPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (!_shouldDedupHookCrash(error)) {
        report(
          type: EventType.crash,
          subKey: error.runtimeType.toString(),
          severity: Severity.fatal,
          message: error.toString(),
          error: error,
          stack: stack,
          context: 'PlatformDispatcher',
        );
      }
      // 调用用户原来的 handler 并尊重它的返回值
      try {
        return _prevPlatformErrorHandler?.call(error, stack) ?? true;
      } catch (_) {
        return true;
      }
    };
  }

  static void _hookLifecycle() {
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
  }

  /// Flutter 最常见两个无意义异常，永久忽略。
  static bool _shouldIgnore(Object error) {
    final msg = error.toString();
    return msg.contains('Looking up a deactivated widget') ||
        msg.contains('setState() called after dispose');
  }

  /// 同一个异常常常会同时被 FlutterError.onError、PlatformDispatcher.onError、
  /// runZonedGuarded handler 里的两到三个抓到。200ms 内同一个异常 *对象*
  /// 视为重复，只上报一次。
  ///
  /// 用 `identityHashCode` 而不是 `runtimeType + toString()`：后者对
  /// `toString` 输出带时间戳 / 句柄地址 / uuid 的异常（部分 PlatformException
  /// 实现就是这样）每次哈希都不同 → 三路 hook 各报一次去重失效。同一对象
  /// 被多路 hook 拿到时 identity 必然相同；两个不同业务点抛的同类型异常即
  /// 使 toString 完全相同，identity 也不同，仍会被分别上报。
  static bool _shouldDedupHookCrash(Object error) {
    final hash = identityHashCode(error);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (hash == _lastHookErrorHash && now - _lastHookErrorMs < 200) {
      return true;
    }
    _lastHookErrorHash = hash;
    _lastHookErrorMs = now;
    return false;
  }

  static String _trimStack(StackTrace stack, {int maxLines = 50}) {
    final text = stack.toString();
    final lines = text.split('\n');
    String out;
    if (lines.length > maxLines) {
      out = '${lines.take(maxLines).join('\n')}\n... (${lines.length - maxLines} more)';
    } else {
      out = text;
    }
    // 再套一层字符级硬截：AOT obfuscated stack 常常是超长单行，
    // 按行切完全无效，必须兜底。
    if (out.length > _maxStackChars) {
      out = '${out.substring(0, _maxStackChars)}…';
    }
    return out;
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        Session.markForeground();
        XCrashSDK.leaveBreadcrumb(category: 'lifecycle', message: 'resumed');
        // 清掉可能残留的上一轮 clean_shutdown 标记，
        // 否则 background→foreground→crash 会被误判为"正常退出"。
        // 通过 CrashPersistence 的串行队列保证与 markCleanShutdown 有序。
        unawaited(CrashPersistence.clearCleanShutdown());
        break;
      case AppLifecycleState.paused:
        XCrashSDK.leaveBreadcrumb(category: 'lifecycle', message: 'paused');
        unawaited(CrashPersistence.markCleanShutdown());
        break;
      case AppLifecycleState.detached:
        unawaited(CrashPersistence.markCleanShutdown());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
