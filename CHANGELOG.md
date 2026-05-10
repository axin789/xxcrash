## 2.0.0

**Breaking rewrite.** 从 Telegram/Slack/Discord/Webhook 多渠道上报插件
改为"统一事件上报 SDK"。宿主工程注入一个 `ContentSender` 回调，
SDK 只负责拼 payload，不再自带 HTTP 层、签名或多渠道分发。

### 新增
- `XCrashSDK.init(sender, userProvider, appRunner, reportConfigs, intervalMs, telegram?)`
- 统一上报入口：`XCrashSDK.report(type, subKey, severity, message, ...)`
- 便捷方法：`reportVideoError` / `reportApiError` / `reportBusinessError`
- `XCrashSDK.flush()` —— logout/切账号前主动把 pending 队列全发一遍
- `XCrashSDK.clearPersistence()` —— 切账号场景清掉 pending / heartbeat / cleanShutdown
- `XCrashSDK.updateHeartbeat(state)` —— 给 native 崩溃兜底用
- `XCrashSDK.limiterKey(type, subKey)` —— 拼 reportConfigs key 的规范方法
- `leaveBreadcrumb(...)` 面包屑 + 容量 50 的环形缓冲
- `BreadcrumbNavigatorObserver` 自动采集页面跳转
- `VideoPlayerReporter` 包装 `video_player` 的 `VideoPlayerController`，
  自动上报播放错误、卡顿、首帧超时，主动上报花屏
- 会话机制：`sessionId` / 启动时长 / 前台次数跟随每条事件
- 生命周期监听：`AppLifecycleState` resume / paused / detached 全部覆盖
- **远端崩溃兜底（`CrashPersistence`）**：
  - pending 队列（最多 20，FIFO）+ 启动时自动补发
  - 7 天过期 + 3 次 attempt 毒丸保护
  - heartbeat + clean-shutdown 标记，下次启动检测疑似 native crash
  - 全量 SharedPreferences 操作串行化，多并发 report 不会丢条目
- **限频器（`ErrorReportLimiter`）**：
  - `${type}:${subKey}` namespaced key
  - 起步阈值（防冷启动头几秒噪音）+ 时间窗口
  - 被压制的 context 在下次放行时随事件一并上报
- **可选 Telegram 旁路（`TelegramConfig`）**：
  - 同一份事件并联发到 Telegram bot
  - 支持 HTML / MarkdownV2 / Markdown / 纯文本，保留字符正确转义
  - HTML 截断保持 tag 平衡，不再被 4096 字符上限拒收
  - HTTP 全阶段超时，不会拖累主上报
  - Web 端 no-op，SDK 仍可编译

### 修复（对抗性审核 7 轮）
- `platform` 字段在 seed 与 `_loadPlatformInfo` 之间统一小写，后端聚合
  不再被 `iOS` / `ios` 拆桶
- HTML 截断不感知 tag 导致 Telegram 400 整条消息丢失
- 裸 boot 心跳不再触发误报 `suspected_native_crash`（用户主动 swipe-kill 场景）
- Markdown / MarkdownV2 不转义保留字符让 subKey 含 `_` 时整条 400
- Hook dedup 改用 `identityHashCode`，不再被 `toString` 带时间戳的异常绕过
- attempt 计数推迟到 dispatch 真失败之后再 bump，避免"启动到一半崩 3 次"
  把 payload 误判为毒丸
- `sender` / Telegram 通道拆开顺序 await + fire-and-forget，不再依赖
  `Future.wait` 的位置约定
- `userProvider` 抛异常被吞，不影响主上报

### 移除
- `CrashReporter` / `CrashReportHelper`（旧静态门面）
- `TelegramNotifier` / `SlackNotifier` / `DiscordNotifier` / `WebhookNotifier`
- `CrashStorage`（本地 SharedPreferences 缓存的旧实现）
- `NotificationConfig` / `SlackConfig` / `DiscordConfig` / `WebhookConfig`
- `MessageBuilder`（HTML/Markdown/JSON payload 拼装器）
- `telegram_api.dart`
- 依赖：`mockito` / `http` / `crypto` / `otp`

### 测试
93+ 个 unit / widget test，`flutter analyze` 0 issue，覆盖：
持久化 / 限频器 / session / 面包屑 / 生命周期 / 路由观察者 /
Telegram 三种 parseMode 渲染 + 截断 / VideoPlayerReporter 全状态机 /
hook dedup + 链式转发 / SDK 端到端集成。

### 兼容性
不再兼容 1.x。所有调用方需改为 `XCrashSDK.init(...)` + `XCrashSDK.report(...)`。

---

## 1.0.0

- Initial release.
- Telegram crash report sender.
- 支持初始化、自定义日志、异常处理。
