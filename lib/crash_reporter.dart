library crash_reporter;

// === 新 API（推荐）===
export 'src/crash_sdk.dart';
export 'src/event_type.dart';
export 'src/session.dart';
export 'src/breadcrumb/breadcrumb.dart';
export 'src/breadcrumb/breadcrumb_buffer.dart';
export 'src/breadcrumb/collectors/navigation_collector.dart';

// === 兼容层 / 旧 API ===
export 'src/crash_reporter.dart';
export 'src/crash_report_helper.dart';
export 'src/models/notification_config.dart';
export 'src/models/crash_data.dart';
export 'src/models/exception_decision.dart';
export 'src/models/parse_mode.dart';
