# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project identity

Despite the README and folder being called `crash_reporter` / `xxcrash`, the actual Dart package name in `pubspec.yaml` is **`xcrash`**. Imports must use `package:xcrash/...`, not `package:crash_reporter/...`. The example app (`example/lib/main.dart`) still imports `package:crash_reporter/crash_reporter.dart` — that import is stale relative to the current package name and will not resolve without fixing the import or aliasing the dependency.

The public entry point is `lib/crash_reporter.dart`, which re-exports the symbols in `lib/src/`. Only add a symbol to that barrel if it is meant to be public API.

## Commands

All commands are run from the package root. Flutter/Dart tooling is required.

```bash
flutter pub get                          # install deps (also run inside example/ for the demo app)
flutter test                             # run all tests in test/
flutter test test/crash_reporter_test.dart   # run a single file
flutter test --plain-name 'Local crash storage works'  # run a single test by name
flutter analyze                          # lint (uses flutter_lints via default analysis_options)
cd example && flutter run                # run the demo app against a device/emulator
```

Tests rely on `SharedPreferences.setMockInitialValues({})` to stub persistence — reuse that pattern for any new test that touches `CrashStorage`.

## Architecture

The package exposes two layers. Do not confuse them — they have different lifecycles and different expectations about what the caller has already set up.

### Layer 1 — `CrashReporter` (`lib/src/crash_reporter.dart`)

Low-level static façade. Holds four optional notifier instances (`TelegramNotifier`, `SlackNotifier`, `DiscordNotifier`, `WebhookNotifier`), a `NotificationConfig` gating which of them fire, and a `CrashStorage` (SharedPreferences, capped at 50 entries) for local persistence.

Key behaviors worth knowing before editing:

- `initialize()` is idempotent-ish but destructive: passing a config *without* a given notifier leaves the previously-constructed one in place (via the `update*Config` methods), but re-calling `initialize` replaces the `NotificationConfig` and may drop notifiers whose config is null. Prefer the typed `updateXConfig` methods for runtime reconfiguration.
- Crashes reported **before** `initialize()` are queued in `_pendingCrashes` (still written to local storage) and flushed with a 500 ms delay between items after init. Any new code paths that produce crashes must tolerate this pre-init window.
- `_sendToAllNotifiers` / `_sendEventToAllNotifiers` / `_sendStartupToAllNotifiers` fan out with `Future.wait(..., eagerError: false)` and swallow per-notifier failures via `.catchError`. Individual notifiers should still `rethrow` on transport errors; the fan-out is the single swallow point.

### Layer 2 — `XCrashSDK` (`lib/src/crash_sdk.dart`)

Opinionated wrapper designed for real-app integration. This is what apps typically call; it is *not* documented in the README.

`XCrashSDK.init(...)` wires up, in order:

1. A `runZonedGuarded` around `appRunner`, so uncaught async errors flow into `CrashReportHelper.report`.
2. `PackageInfo` + `getDeviceInfo()` (`lib/src/deviceinfo.dart`) snapshot into static `_appData` / `_deviceData` that are attached to every report.
3. `CrashReporter.initialize(...)` with Telegram + Webhook enabled by default (Slack/Discord are **not** initialized by this path — add them via `updateSlackConfig` / `updateDiscordConfig` if needed).
4. `FlutterError.onError` hook (synchronous framework errors).
5. `ErrorReportLimiter` configuration (`setStartReportThresholds`, `setIntervalMs`).

Two subtleties that have bitten past changes:

- **Deferred server URL.** `init(crashReportUrl: () => ...)` stores the callback; the real webhook URL is resolved lazily on the first crash via `ensureServerConfig()` inside `ErrorReportLimiter.shouldReport`. Until `setServerConfigUrl` succeeds, `_reportEnabled` is false and **nothing is transmitted**, even though local storage still accumulates. When debugging "why isn't anything being sent," check `ErrorReportLimiter.reportEnabled` and the `crashReportUrl` callback's return value.
- **Server URL format.** `setServerConfigUrl` requires a URL containing an `appid` query param (e.g. `https://host/report?appid=xxx`) and throws `ArgumentError` otherwise. The appId is extracted and reused as both the webhook query param and the HMAC-style signing input (`md5(appId + ts)`) in `WebhookNotifier._sendPayload`.

### Rate limiting — `ErrorReportLimiter` (`lib/src/report_limiter.dart`)

Every crash flowing through `CrashReportHelper` is gated here, keyed by `runtimeType.toString()`:

- **Startup threshold** (`_startReportThreshold`): an error type must occur N times (configured via `setStartReportThresholds`, default `{"DioError": 10}`) before *any* report is emitted. Useful for noisy transient errors.
- **Interval** (`_intervalMs`, default 60 s): after the startup threshold is cleared, at most one report per type per interval.
- Suppressed hits accumulate `_suppressedCount` and unique `context` strings into `_suppressedContexts`; the next allowed report pulls them via `takeSuppressedContexts` and attaches them as `suppressedPaths`/`suppressedCount` in `extraData`.
- A hard cap of 50 distinct error types is enforced by LRU eviction on `firstTime`.

When adding a new entry point that reports crashes, route it through `CrashReportHelper.report` (not directly through `CrashReporter.reportCrash`) so the limiter and ignore policy apply.

### Ignore policy — `CrashExceptionPolicy` (`lib/src/crash_exception_policy.dart`)

Currently hard-codes two ignored messages: `"Looking up a deactivated widget"` and `"setState() called after dispose"`. Also strips a `path_` prefix from context strings before they're used as the limiter's context key. Add new ignore rules here rather than at call sites.

### Notifiers (`lib/src/notifiers/`)

All extend `BaseNotifier` and implement `sendCrashReport` / `sendEvent` / `sendAppStartup` / `testConnection` / `dispose`. Message formatting is centralized in `lib/src/message_builder.dart`, which produces HTML, Markdown, plain-text, and (for webhooks) JSON variants; the `ParseMode` enum in `lib/src/models/parse_mode.dart` selects between them. Note the enum's `None` value is PascalCase (Dart style lint ignored) — matches the wire protocol string `"None"`.

`WebhookNotifier` is the only notifier that signs requests (`md5(appId + ts)` in headers `appid` / `ts` / `key`) and the only one that supports switchable `ParseMode`. The three chat-platform notifiers hardcode their own formatting.

## Conventions

- Dart comments and debug strings in this codebase mix English and Chinese — keep the existing language of any block you're editing, don't translate wholesale.
- `debugPrint` is threaded through every class as `Function(String)` dependency injection rather than called directly, so tests can capture it. Preserve that pattern when adding new components.
- The package targets Dart SDK `>=2.17.0 <4.0.0`. Avoid features that require a higher floor (records, patterns, etc.) unless you also bump the SDK constraint.
