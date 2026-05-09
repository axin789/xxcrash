## 2.0.0

**Breaking rewrite.** 从 Telegram/Slack/Discord/Webhook 多渠道上报插件
改为"统一事件上报 SDK"。宿主工程注入一个 `ContentSender` 回调，
SDK 只负责拼 payload，不再自带 HTTP 层、签名或多渠道分发。

### 新增
- `XCrashSDK.init(sender, userProvider, appRunner, reportConfigs, intervalMs)`
- 统一上报入口：`XCrashSDK.report(type, subKey, severity, message, ...)`
- 便捷方法：`reportVideoError` / `reportApiError` / `reportBusinessError`
- `leaveBreadcrumb(...)` 面包屑 + 容量 50 的环形缓冲
- `BreadcrumbNavigatorObserver` 自动采集页面跳转
- `VideoPlayerReporter` 包装 `video_player` 的 `VideoPlayerController`，
  自动上报播放错误、卡顿、首帧超时，主动上报花屏
- 会话机制：`sessionId` / 启动时长 / 前台次数跟随每条事件
- 生命周期监听：`AppLifecycleState` resume 记 breadcrumb

### 移除
- `CrashReporter` / `CrashReportHelper`（旧静态门面）
- `TelegramNotifier` / `SlackNotifier` / `DiscordNotifier` / `WebhookNotifier`
- `CrashStorage`（本地 SharedPreferences 缓存）
- `NotificationConfig` / `TelegramConfig` / `SlackConfig` / `DiscordConfig` / `WebhookConfig`
- `MessageBuilder`（HTML/Markdown/JSON payload 拼装器）
- `telegram_api.dart`
- 依赖：`shared_preferences` / `mockito` / `http` / `crypto` / `otp`

### 兼容性
不再兼容 1.x。所有调用方需改为 `XCrashSDK.init(...)` + `XCrashSDK.report(...)`。

---

## 1.0.0

- Initial release.
- Telegram crash report sender.
- 支持初始化、自定义日志、异常处理。
