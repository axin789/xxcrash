# xcrash

一个轻量的 Flutter 崩溃与运行时事件上报 SDK。统一采集 **崩溃 / 视频播放 / 接口 / 业务** 四类事件，限频、带上下文面包屑、打包成 JSON，然后**交给宿主工程自己的 HTTP 层**上报。SDK 不关心你怎么发请求、怎么鉴权、怎么重试。

还额外帮你处理了"**远端设备的崩溃**"这个场景：进程死在途中的 payload 下次启动自动补发；就算是 native 层 SIGSEGV 把整个 Dart 带走，下次启动也能靠心跳合成一条 `suspected_native_crash`。

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)

---

## 特性

- **三层 Dart 崩溃捕获** —— `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError`
- **远端崩溃兜底** —— 上报队列落盘 + 心跳推断 + 干净退出标记，native 崩溃也能被"迟到上报"
- **不绑定传输层** —— 注入一个 `sender(content)` 回调，SDK 只负责给 JSON
- **可选 Telegram 旁路** —— 同一份事件并联到 Telegram bot，远端 debug 不再靠 adb
- **统一事件模型** —— crash / video / api / business 共用一套 payload
- **限频器** —— 每个 key 独立的起步阈值 + 时间窗口，防止崩溃风暴打爆后端
- **面包屑** —— 容量 50 的环形缓冲，每次上报附带最近 50 条行为痕迹
- **会话机制** —— 每次冷启动一个 `sessionId`，事件可按会话聚合
- **`video_player` 集成** —— 自动检测播放错误 / 卡顿 / 首帧超时
- **多项目复用** —— 一个 SDK 跨项目共享，各自用自己的上报接口

---

## 安装

直接拉 git，免私有 pub：

```yaml
dependencies:
  xcrash:
    git:
      url: https://github.com/axin789/xxcrash.git
      ref: main          # 或锁到具体 tag / commit，例如 ref: v2.0.0
```

跑一次：

```bash
flutter pub get
```

要求 Dart SDK `>=2.17.0 <4.0.0`。公开入口只有一个：

```dart
import 'package:xcrash/xcrash.dart';
```

> 想固定版本，把 `ref: main` 换成 `ref: v2.0.0`（或任意 commit hash）。
> 本地 fork / 改造期间也可以临时用 `path: ../xcrash`。

---

## 最小用法

```dart
import 'package:flutter/material.dart';
import 'package:xcrash/xcrash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  XCrashSDK.init(
    appRunner: () async => runApp(const MyApp()),
    userProvider: () => {'uid': AuthService.currentUid},
    sender: (content) async {
      await MyHttpUtils.post('/system/track', data: {'content': content});
    },
    reportConfigs: const {
      'crash:DioException': 5,     // Dio 错累计 5 次才首报
      'video:buffer_stall': 5,     // 卡顿 5 次才首报
      'video:playback_error': 1,   // 播放错首次就报
    },
    intervalMs: 60 * 1000,         // 每个 key 每 60 秒最多一次
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [BreadcrumbNavigatorObserver()],  // 自动记录页面跳转
      home: const HomePage(),
    );
  }
}
```

`sender` 收到的是一个完整 JSON 字符串。你怎么塞进自家接口都行 —— 上面这个例子把它塞到 `content` 字段走 `/system/track`。

---

## 崩溃怎么捕获的

### Dart 层（三重兜底）

| 层 | 捕获什么 |
| --- | --- |
| `FlutterError.onError` | build / layout / paint 阶段的框架错误 |
| `PlatformDispatcher.instance.onError` | zone 外的 async、某些 plugin 回调 |
| `runZonedGuarded` | 业务 zone 内的未捕获 async 错误 |

上面三个都由 `init()` 自动装好，业务代码无需任何额外调用。

### 远端设备：进程死亡场景

这里才是 xcrash 真正的价值所在。普通 crash reporter 在进程死掉那一刻就丢数据了，xcrash 靠三个机制兜住：

1. **上报队列落盘** —— 每次 `report()` 会先把 payload 写进 SharedPreferences（最多存 20 条，FIFO 淘汰），主通道发送成功后再删除。发到一半死掉？下次启动自动补发。
2. **心跳** —— 每次冷启动写一条 `boot` 心跳；业务关键时刻可以调 `updateHeartbeat(...)` 更新成"我正在做 X"（比如当前视频 URL）。心跳里自动附带面包屑快照。
3. **Clean-shutdown 标记** —— `paused` / `detached` 生命周期下写"正常退出"标记；`resumed` 时自动清掉。

下次启动时 SDK 做一次 `_flushPendingAndDetectLastCrash()`：

- 补发队列里未送出的 payload
- 如果看到 "有心跳 + 没干净退出标记" → 合成一条 `suspected_native_crash` 事件上报，带上死前在做什么、死前 50 条面包屑
- 例外：如果上次只有 init 时写的裸 `boot` 心跳（业务还没动起来、面包屑空），就不报 —— 这种情况下"用户主动 swipe-kill"和"真崩溃"无法区分，宁可漏也别假报

**这意味着你能看到的是：** 就算设备不在身边，用户的手机在**前台** native crash 一次，下次他重启 app 你就会收到一条带上下文的上报。

**已知边界：**
- 仅在前台崩溃才能被自动检测到。app 已经被切到后台时如果被 iOS jetsam / Android LMK 杀掉，由于 `paused` 生命周期已经写过"干净退出"标记，下次启动不会被识别为疑似崩溃。
- iOS 上无法和"用户主动从任务栏滑掉"区分；裸 boot 心跳过滤就是为了这种场景。

---

## 四种事件

### 1. 崩溃（自动，不用调）

`init` 内部已挂好三层 hook。所有 Dart 异常自动走 `EventType.crash`。

### 2. 视频播放异常

用 `VideoPlayerReporter` 包装 `video_player` 的 controller：

```dart
final controller = VideoPlayerController.networkUrl(Uri.parse(url));
final reporter = VideoPlayerReporter(
  controller: controller,
  videoUrl: url,
  metadata: {'albumId': 123},
  bufferStallThreshold: const Duration(seconds: 3),
  firstFrameTimeout: const Duration(seconds: 10),
);
reporter.attach();

// 用户点"画面异常"按钮（花屏这种无法自动检测）
IconButton(
  icon: const Icon(Icons.report_problem),
  onPressed: () => reporter.reportVisualGlitch(extra: {'feedback': '画面花屏'}),
);

@override
void dispose() {
  reporter.detach();     // ← 必须，否则 listener 泄漏
  controller.dispose();
  super.dispose();
}
```

自动上报：`playback_error` / `buffer_stall` / `first_frame_timeout`
手动上报：`visual_glitch`

> 如果你用的不是 `video_player`（比如 `niuma_player` / `better_player` / `fijkplayer`），自己写一个类似的适配层即可：在 controller listener 里检测到异常时调 `XCrashSDK.reportVideoError(...)`，在 `setSource` 时调 `XCrashSDK.updateHeartbeat({'type':'video', 'url': url})`。

### 3. 接口错误

在 Dio 拦截器里调用：

```dart
class TrackInterceptor extends Interceptor {
  @override
  void onResponse(Response r, ResponseInterceptorHandler h) {
    XCrashSDK.leaveBreadcrumb(
      category: 'network',
      message: '${r.requestOptions.method} ${r.requestOptions.path} -> ${r.statusCode}',
    );
    h.next(r);
  }

  @override
  void onError(DioException e, ErrorInterceptorHandler h) {
    XCrashSDK.reportApiError(
      path: e.requestOptions.path,
      method: e.requestOptions.method,
      statusCode: e.response?.statusCode ?? -1,
      durationMs: _durationOf(e.requestOptions),
      errno: e.type.name,
    );
    h.next(e);
  }
}
```

> SDK 不内置 Dio 拦截器 —— Dio 版本分裂，peer-dep 会很痛。上面 10 行复制过去就行。

### 4. 业务错误

业务代码主动调用：

```dart
XCrashSDK.reportBusinessError(
  scene: 'login_risk_control',
  message: '风控拒绝登录',
  extra: {'riskCode': 'R03', 'retry': 2},
);
```

### 通用入口

三个便捷方法覆盖不了的场景直接调 `report()`：

```dart
XCrashSDK.report(
  type: EventType.business,
  subKey: 'payment_refund_failed',
  severity: Severity.error,
  message: '退款失败',
  context: '/order/refund',
  data: {'orderId': 'o1', 'amount': 9.9},
  error: e,          // 可选
  stack: s,          // 可选
);
```

---

## 面包屑

一条手动记录：

```dart
XCrashSDK.leaveBreadcrumb(
  category: 'custom',
  level: 'info',
  message: '点击领取奖励',
  data: {'taskId': 123},
);
```

自动采集的：

- **页面跳转** —— 把 `BreadcrumbNavigatorObserver()` 挂到 `MaterialApp.navigatorObservers`
- **生命周期** —— `init()` 自动装，resumed / paused 都会记
- **上报本身** —— 每次 `report()` 会把自己以 `"$subKey: $message"` 的形式补写一条面包屑

容量 50，环形缓冲，FIFO 淘汰。

---

## 心跳（给 native 崩溃兜底）

业务代码在"关键动作"前面加一行：

```dart
// 切换视频源时
await XCrashSDK.updateHeartbeat({'type': 'video', 'url': url, 'backend': 'ijk'});

// 进入长流程、复杂路由、耗时操作前
await XCrashSDK.updateHeartbeat({'type': 'feature', 'name': 'photo_export'});
```

心跳会覆盖上一条，同时自动附带当前面包屑快照。进程死了之后，这份快照会出现在下一次启动的 `suspected_native_crash` 事件的 `data.lastHeartbeatState` + `data.lastBreadcrumbs` 里。

> 不是每个 setState 都要调。**挂在你怀疑会死在那儿的动作**上即可（播放、支付、大图解码、相册导出、音视频合成这类）。

---

## Telegram 旁路（可选）

传 `telegram` 参数就会在主 sender 之外并联一路 Telegram bot。两条路各走各的、独立失败、互不阻塞；主通道失败会留在 pending 队列等重发，Telegram 失败就丢（辅助通道，丢了比重复好）。

**准备工作：**

1. Telegram 搜 `@BotFather`，发 `/newbot`，拿到 **Bot Token**（形如 `1234:ABC...`）。Token 等同密码，尽量**别入库**，用远程配置或运行时下发。
2. 拿到 **Chat ID**：
   - **发给自己**：给 bot 私聊一条消息，浏览器打开 `https://api.telegram.org/bot<TOKEN>/getUpdates`，看 `"chat":{"id":12345}`
   - **发到群**：把 bot 拉进群，群里发消息，同上；群 id 是负数（超群 `-1001234567890`）
   - **发到频道**：bot 设为频道管理员；chat ID 填 `@channel_username` 或 `-100...`

**用法：**

```dart
XCrashSDK.init(
  // ...其他参数
  telegram: const TelegramConfig(
    botToken: String.fromEnvironment('TG_BOT_TOKEN'),
    chatId: '-1001234567890',
    parseMode: 'HTML',          // 默认 HTML；传 null 发纯文本
    disableWebPagePreview: true,
    disableNotification: false,
    timeout: Duration(seconds: 10),
  ),
);
```

**消息长这样：**

```
🚨 FATAL · crash
subKey: StateError
message: bad state
session: abc12345 (23420ms)
app: 1.2.3+45
device: ios iPhone15,3 17.4
user: u-001
context: /player

error:
StateError: bad state
<pre>
#0 main (main.dart:12)
#1 ...
</pre>

breadcrumbs:
• [navigation] push /home
• [network] GET /feed 200
• ...
```

Telegram 单消息上限 4096 字符，SDK 在 4000 字符处截断并追加 `…`。完整数据仍然走主 `sender` 送到你们后端。

---

## 限频行为

- Key = `"${eventType}:${subKey}"`，每个 key 独立计数
- **起步阈值** —— 累计出现 N 次才允许首次上报（`reportConfigs` 配）。注意：累计计数本进程内只增不减，长时间运行后所有 key 都会越过 threshold gate，主要起"防冷启动头几秒一波噪音"的作用，不是常驻防抖
- **时间窗口** —— 放行一次后，同 key 在 `intervalMs` 内继续累计但不上报
- **压制统计** —— 被压制期间出现过的 `context` 会收集起来，下次放行时随事件的 `suppressedCount` / `suppressedContexts` 字段一并上报，信息不丢但不刷屏

`reportConfigs` 的 key 有两种形式：

```dart
{
  // 形式一：完整 key (推荐) —— 精确到 (eventType, subKey)
  'video:buffer_stall': 5,
  'api:/feed:500': 3,

  // 形式二：error 的 runtimeType —— 兼容老配置；仅当完整 key 未配时回落匹配
  'DioException': 10,
}
```

如果需要清空限频状态（例如用户切换账号），调 `ErrorReportLimiter.clear()`。

---

## Payload 结构

`sender` 收到的 `content` 反序列化后：

```json
{
  "eventType": "crash | video | api | business",
  "subKey": "playback_error",
  "severity": "fatal | error | warning | info",
  "timestamp": "2026-04-24T10:00:00.000Z",
  "session": {
    "id": "...",
    "startTimeMs": 1745488800000,
    "durationMs": 42000,
    "foregroundCount": 2
  },
  "app":    { "appName": "...", "version": "...", "buildNumber": "..." },
  "device": { "platform": "ios", "model": "iPhone15,3", "systemVersion": "17.4" },
  "user":   { "uid": "..." },
  "message": "单行摘要",
  "error": {
    "type": "PlatformException",
    "message": "...",
    "stack": "#0 ...\n#1 ..."
  },
  "context": "路由 / 接口路径 / 播放器 URL",
  "data": { /* 事件自带的结构化字段 */ },
  "breadcrumbs": [
    { "ts": 1745488801000, "category": "navigation", "level": "info", "message": "push /home", "data": {...} }
  ],
  "suppressedCount": 3,
  "suppressedContexts": ["/feed/list", "/feed/detail"]
}
```

`suspected_native_crash` 事件的 `data` 里会额外带：

```json
{
  "lastHeartbeatTs": 1745488800000,
  "lastHeartbeatState": { "type": "video", "url": "...", "backend": "ijk" },
  "lastBreadcrumbs": [ /* 死前那一轮的 50 条面包屑 */ ]
}
```

---

## 公开 API 速查

所有公开符号都来自 `package:xcrash/xcrash.dart`：

| 符号 | 用途 |
| --- | --- |
| `XCrashSDK.init(...)` | 初始化入口，重复调用忽略 |
| `XCrashSDK.report(...)` | 通用上报入口（其余都是它的包装） |
| `XCrashSDK.reportVideoError(...)` | 视频播放事件（`playback_error` / `buffer_stall` / `visual_glitch` / 自定义） |
| `XCrashSDK.reportApiError(...)` | 接口错误，subKey 默认 `"$path:$statusCode"` |
| `XCrashSDK.reportBusinessError(...)` | 业务错误，subKey = `scene` |
| `XCrashSDK.leaveBreadcrumb(...)` | 手动写面包屑 |
| `XCrashSDK.updateHeartbeat(state)` | 更新心跳（给 native 崩溃兜底） |
| `XCrashSDK.flush()` | 立刻把 pending 队列尝试发一遍（logout / 切账号前用，不 bump attempt） |
| `XCrashSDK.clearPersistence()` | 清掉 pending / heartbeat / cleanShutdown（切账号前用） |
| `ContentSender` | `typedef Future<void> Function(String content)` |
| `EventType` | `crash / video / api / business` |
| `Severity` | `fatal / error / warning / info` |
| `BreadcrumbNavigatorObserver` | 挂到 `MaterialApp.navigatorObservers` 自动记录路由跳转 |
| `VideoPlayerReporter` | `video_player` 的 controller 适配器 |
| `TelegramConfig` | Telegram 旁路配置 |

---

## 测试

```bash
flutter pub get
flutter test                                          # 81 个测试
flutter test test/crash_sdk_test.dart                 # 单文件
flutter test --plain-name 'sender 抛异常被吞掉'       # 按名称
flutter analyze                                       # 0 issues
```

覆盖范围：持久化、限频、session、面包屑环形缓冲、Telegram 消息渲染（HTML / MarkdownV2 / Markdown legacy）+ HTML 截断 tag 平衡、SDK 整体集成。

---

## 许可

MIT
