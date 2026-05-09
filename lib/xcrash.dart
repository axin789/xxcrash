/// XCrash — Flutter 崩溃 & 运行时事件上报 SDK。
///
/// ```dart
/// import 'package:xcrash/xcrash.dart';
/// ```
library xcrash;

export 'src/crash_sdk.dart' show XCrashSDK, ContentSender;
export 'src/event_type.dart' show EventType, Severity;
export 'src/breadcrumb/collectors/navigation_collector.dart'
    show BreadcrumbNavigatorObserver;
export 'src/integrations/video_player_reporter.dart' show VideoPlayerReporter;
export 'src/integrations/telegram_sender.dart' show TelegramConfig;
