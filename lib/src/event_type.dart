/// 上报事件的顶层分类。后端用 eventType 字段分流存储。
enum EventType { crash, video, api, business }

extension EventTypeExt on EventType {
  String get value {
    switch (this) {
      case EventType.crash:
        return 'crash';
      case EventType.video:
        return 'video';
      case EventType.api:
        return 'api';
      case EventType.business:
        return 'business';
    }
  }
}

/// 严重级别。限频/告警策略可按此字段差异化。
enum Severity { fatal, error, warning, info }

extension SeverityExt on Severity {
  String get value {
    switch (this) {
      case Severity.fatal:
        return 'fatal';
      case Severity.error:
        return 'error';
      case Severity.warning:
        return 'warning';
      case Severity.info:
        return 'info';
    }
  }
}
