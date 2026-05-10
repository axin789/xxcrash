# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project identity

**`xcrash`** — a Flutter SDK for crash and runtime-event reporting. Version 2.0 is a ground-up rewrite: it no longer bundles Telegram/Slack/Discord/Webhook transports. Host projects inject a `ContentSender` callback and the SDK just hands them a JSON string.

Public API lives behind `lib/xcrash.dart` (barrel). Import for consumers: `import 'package:xcrash/xcrash.dart';`.

The barrel uses explicit `show` clauses to pin the public surface to exactly 7 symbols: `XCrashSDK`, `ContentSender`, `EventType`, `Severity`, `BreadcrumbNavigatorObserver`, `VideoPlayerReporter`, `TelegramConfig`. Everything else in `lib/src/` is internal. When adding something new, only surface it via `show` if consumers genuinely need it.

## Commands

```bash
flutter pub get                                       # install deps
flutter pub get --directory example                   # also needed for the demo
flutter test                                          # run all 81 tests
flutter test test/crash_sdk_test.dart                 # single file
flutter test --plain-name 'sender 抛异常被吞掉'       # single test by name
flutter analyze                                       # static analysis (expects 0 issues)
cd example && flutter run                             # demo app
```

## Architecture

### Single entry — `XCrashSDK`

```
XCrashSDK.init(sender, userProvider, appRunner, reportConfigs, intervalMs, telegram?)
  │
  ├─ sync setup first        — seed device platform + Session + limiter +
  │                            _inited=true + _hookFlutterError + _hookPlatformDispatcher
  │                            (so first-frame errors are captured)
  └─ runZonedGuarded         — await appRunner →
     │                        _hookLifecycle →
     │                        unawaited(_loadPlatformInfo)  (PackageInfo + deviceInfo in bg) →
     │                        unawaited(_flushPendingAndDetectLastCrash → writeHeartbeat boot)
     ↳ zone error handler    — uncaught async errors → report(crash) (dedup'd with the 2 hooks)
```

`_loadPlatformInfo` is `unawaited` because platform channels are slow and we don't want to block visible app startup. Before it resolves, `_deviceData` still has a minimal `{platform, debugMode}` seed set synchronously in `init()` — reports during that window carry *some* OS info, not empty maps.

After init, everything flows through **`XCrashSDK.report(type, subKey, severity, message, error, stack, context, data)`**. The three convenience methods `reportVideoError` / `reportApiError` / `reportBusinessError` are thin wrappers that set `type` + shape `data`.

Payload assembly happens inline in `report()`; output is a JSON-encoded map handed to the injected `ContentSender`. Sender exceptions are caught and debug-printed — never rethrown.

### Remote-crash resilience — `CrashPersistence`

Three mechanisms on top of SharedPreferences:

1. **Pending queue** (`xcrash.pending.v1`): `report()` writes payload to disk before network; `removePending(id)` after the main sender succeeds. Size cap 20, FIFO. Each entry carries an `attempt` counter — `loadPendingForRetry()` only filters out poison pills (`attempt >= _maxAttempts=3`) and entries older than `_maxAgeMs=7d`. The `attempt` increment itself is deferred to `bumpPendingAttempt(id)`, called by the startup-flush loop *after* a dispatch genuinely fails — this avoids the old failure mode where dying mid-dispatch would still bump the counter and prematurely mark a payload as poison.
2. **Heartbeat** (`xcrash.heartbeat.v1`): `updateHeartbeat(state)` persists "currently doing X" plus a snapshot of breadcrumbs. `init()` writes a `type: 'boot'` heartbeat right after the startup flush.
3. **Clean-shutdown marker** (`xcrash.clean_shutdown.v1`): `_LifecycleObserver` sets it on `paused`/`detached`, clears it on `resumed` and every `writeHeartbeat`. On next cold start, "heartbeat exists + no clean shutdown" synthesizes a `suspected_native_crash` event.

**All mutating ops are serialized on a single `Future` chain** (`CrashPersistence._queue`). Without this, concurrent `report()` calls race on the read-modify-write of the pending list and silently drop entries. This is the load-bearing piece — if you add new SharedPreferences ops to this file, go through `_serialize(...)`.

Entry ids are `<microseconds>.<8-hex-random>` so two `report()` calls in the same microsecond don't collide.

### Rate limiting — `ErrorReportLimiter`

Keyed by `"${eventType}:${subKey}"`. Use `XCrashSDK.limiterKey(type, subKey)` (or the internal `ErrorReportLimiter.keyOf(...)`) to build the string — don't hand-concat in `reportConfigs` or you'll misspell and silently lose the rule. Two gates:

1. **Startup threshold** (`reportConfigs`). Key in the config is either the full limiter key (e.g. `"video:buffer_stall": 5`) or falls back to the error's `runtimeType.toString()`. Default is `{'DioException': 10, 'DioError': 10}` covering Dio 4 and 5.
2. **Interval**. After a report is allowed, the same key is muted for `intervalMs`. Suppressed hits collect their `context` strings (ordered list, duplicates preserved, capped per key) and ride along in `suppressedContexts` on the next allowed report.

Distinct-key count is capped at `_maxTrackedKeys=500` with FIFO eviction. If you generate unbounded subKeys (e.g. putting raw IDs in `reportApiError`'s path), either fix the call site to template (`/user/:id` not `/user/123`) or call `ErrorReportLimiter.clear()` on user-switch.

### Ignore policy

Inlined in `XCrashSDK._shouldIgnore`. Currently filters two Flutter-specific phantom errors: `Looking up a deactivated widget` and `setState() called after dispose`. Add new rules here, not at call sites. If the ignore set grows, split it back out to a dedicated file.

### Session — `lib/src/session.dart`

One sessionId per cold start (128-bit hex). `foregroundCount` is incremented by the lifecycle observer. All reports embed `session.{id, startTimeMs, durationMs, foregroundCount}`. Has a `@visibleForTesting` `debugReset()` — tests rely on it.

### Breadcrumbs — `lib/src/breadcrumb/`

Ring buffer, capacity 50. `XCrashSDK.leaveBreadcrumb(...)` is the single write path. Each `report()` call embeds the current snapshot **and** appends itself to the buffer (so later reports see "we already reported X").

Two auto-collectors:
- `BreadcrumbNavigatorObserver` — users attach to `MaterialApp.navigatorObservers`.
- Lifecycle transitions — wired automatically in `_LifecycleObserver`.

There is intentionally no Dio collector bundled: Dio versions diverge and peer-dep hell isn't worth it. The README shows the 10-line interceptor pattern; users copy it.

### `video_player` integration — `lib/src/integrations/video_player_reporter.dart`

The only third-party integration with a **hard dependency** on `video_player`. Wraps `VideoPlayerController.addListener` and detects:

- `playback_error`      — `value.hasError` transitions to true (reports once, then short-circuits)
- `buffer_stall`        — `isPlaying` but `position` hasn't advanced for `bufferStallThreshold`
- `first_frame_timeout` — `attach()` to first non-zero `position` exceeds `firstFrameTimeout`

`visual_glitch` (花屏) is user-triggered via `reportVisualGlitch()` because decoder-level corruption rarely surfaces as an error event.

Always pair `attach()` with `detach()` in the widget's dispose — otherwise listeners leak when controllers outlive the screen.

## Conventions

- Code comments mix Chinese and English; match whichever is already present in the file you're editing.
- Static-only classes (`XCrashSDK`, `Session`, `ErrorReportLimiter`) expose `@visibleForTesting` reset hooks. Use them in `setUp` / `tearDown`; don't reach into private state.
- When adding a new event subtype, prefer a new `subKey` value under an existing `EventType` over introducing a new `EventType`. Only add to the enum when the backend needs a different schema.
- Dart SDK floor is `>=2.17.0 <4.0.0`. Don't use records/patterns/switch expressions unless you also raise the floor.

## Things that are easy to get wrong

- **Renaming the barrel.** Public import is `package:xcrash/xcrash.dart`. Changing that breaks every consuming app — major version bump required.
- **Test hooks and production code.** `XCrashSDK.debugForceEnable`, `debugReset`, and `debugFlushPendingAndDetectLastCrash` are `@visibleForTesting`. Do not call them from app code or examples — the lint will flag it, but the breakage (skipping PackageInfo/deviceInfo snapshot, skipping the runZonedGuarded hook, etc.) is silent.
- **Bypassing `CrashPersistence._serialize` in new methods.** If you add a new read-modify-write path on SharedPreferences in this file and forget to wrap it in `_serialize`, you've reintroduced the concurrency race that the whole queue was built to prevent. Tests won't always catch this — they're deterministic-ish; a real user with FlutterError + PlatformDispatcher double-firing will.
- **`video_player` dependency bloat.** Adding more player SDKs (better_player / fijkplayer) should be separate opt-in files under `integrations/`. Don't add their packages to `pubspec.yaml` as hard deps — that forces every consumer to pull them.
- **Limiter keys are namespaced by event type.** The full key is `${type}:${subKey}`, so the same `subKey` under different `EventType`s does **not** collide — `video:buffer_stall` and `business:buffer_stall` are independent buckets. Always build keys via `XCrashSDK.limiterKey(...)` (or `ErrorReportLimiter.keyOf`) when populating `reportConfigs`; a hand-typed `'buffer_stall': 5` would be matched against the legacy errorType fallback path, not against any specific event.
- **`reportApiError` path templating.** `subKey` is `"$path:$statusCode"`. If the path contains a raw ID (`/user/123`), every request generates a unique subKey and the limiter map hits its LRU cap. Template the path before calling.
