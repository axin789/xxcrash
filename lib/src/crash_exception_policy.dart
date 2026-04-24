
import 'package:xcrash/src/report_limiter.dart';

import 'models/exception_decision.dart';

class CrashExceptionPolicy {
  static ExceptionDecision decide(
      Object error,
      String context,
      StackTrace stack,
      ) {
    final type = error.runtimeType.toString();

    /// 1️⃣ 永远忽略的异常
    if (_shouldIgnore(error)) {
      return ExceptionDecision(
        shouldReport: false,
        suppressedCount: 0,
        type: type,
      );
    }

    /// 2️⃣ 所有异常统一走限频
    final suppressed = ErrorReportLimiter.shouldReport(
      type,
      context: _extractContext(context),
      error: error,
      stackTrace: stack,
    );

    /// ❌ 被限频
    if (suppressed == null) {
      return ExceptionDecision(
        shouldReport: false,
        suppressedCount: ErrorReportLimiter.suppressedCount(type),
        type: type,
      );
    }

    /// ✅ 允许上报
    return ExceptionDecision(
      shouldReport: true,
      suppressedCount: suppressed,
      type: type,
    );
  }

  /// ================================
  /// 忽略规则（SDK 白名单）
  /// ================================
  static bool _shouldIgnore(Object error) {
    final msg = error.toString();
    return msg.contains('Looking up a deactivated widget') ||
        msg.contains('setState() called after dispose');
  }

  /// ================================
  /// context 解析规则
  ///
  /// - path_xxx → 只记录 path
  /// - 其它 → 原样记录
  /// ================================
  static String _extractContext(String context) {
    if (context.startsWith('path_')) {
      return context.substring(5); // 去掉 path_
    }
    return context;
  }
}
