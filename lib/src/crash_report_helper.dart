import 'crash_sdk.dart';
import 'event_type.dart';

/// 向后兼容的包装。现存调用方不用改签名，内部转发到 [XCrashSDK.report]。
///
/// 新代码建议直接调用 `XCrashSDK.report(...)` / `reportVideoError(...)`
/// / `reportApiError(...)` / `reportBusinessError(...)`。
class CrashReportHelper {
  static Future<void> report({
    required Object error,
    required StackTrace stack,
    required String context,
    Map<String, dynamic>? userData,
    Map<String, dynamic>? appData,
    Map<String, dynamic>? deviceData,
  }) {
    // 老签名里的 userData/appData/deviceData 现在由 XCrashSDK 内部统一注入。
    // 这里只把显式传入的值当作"调用点附加的快照"塞进 data。
    final overrides = <String, dynamic>{
      if (userData != null) 'user': userData,
      if (appData != null) 'app': appData,
      if (deviceData != null) 'device': deviceData,
    };

    return XCrashSDK.report(
      type: EventType.crash,
      subKey: error.runtimeType.toString(),
      severity: Severity.fatal,
      message: error.toString(),
      error: error,
      stack: stack,
      context: context,
      data: overrides.isEmpty ? null : overrides,
    );
  }
}
