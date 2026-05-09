/// 上报事件的顶层分类。后端用 `eventType` 字段分流存储。
enum EventType { crash, video, api, business }

/// 严重级别。
enum Severity { fatal, error, warning, info }
