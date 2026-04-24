# crash_reporter

A powerful Flutter plugin that sends **crash reports, errors, and custom logs** to multiple platforms simultaneously — **Telegram**, **Slack**, **Discord**, and **custom webhooks**. Get real-time notifications across all your communication channels without relying on third-party crash analytics.

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Pub Version](https://img.shields.io/pub/v/crash_reporter?color=blue&style=for-the-badge)
![License](https://img.shields.io/github/license/cas8398/crash_reporter?style=for-the-badge)
[![Tests](https://github.com/cas8398/crash_reporter/actions/workflows/test.yml/badge.svg)](https://github.com/cas8398/crash_reporter/actions)
[![Pub Points](https://img.shields.io/pub/points/crash_reporter.svg)](https://pub.dev/packages/crash_reporter/score)

---

## 🚀 Features

- **Multi-platform reporting** — Send to Telegram, Slack, Discord, and custom webhooks
- **Instant crash notifications** with detailed stack traces
- **Flexible configuration** — Enable only the services you need
- Send **custom logs** and **error messages**
- **App startup notifications** to track deployments
- Works with `FlutterError.onError` and `PlatformDispatcher` for uncaught exceptions
- Supports **async error handling**
- **Lightweight** — minimal dependencies
- No external analytics SDKs — full control & privacy

---

## 🧩 Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  crash_reporter: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## ⚙️ Setup

### 1. Configure Your Services

Choose which platforms you want to use (one or multiple):

#### **Telegram Setup**

- Open Telegram and search for [@BotFather](https://t.me/BotFather)
- Send `/newbot` and follow the instructions
- Copy the **Bot Token** (e.g., `123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ`)
- Get your **Chat ID** using [@InstantChatIDBot](https://t.me/InstantChatIDBot)

#### **Slack Setup**

- Go to [Slack API](https://api.slack.com/messaging/webhooks)
- Create an Incoming Webhook for your workspace
- Copy the **Webhook URL** (e.g., `https://hooks.slack.com/services/XXX/XXX/XXX`)

#### **Discord Setup**

- Open your Discord server settings
- Go to **Integrations** → **Webhooks** → **New Webhook**
- Copy the **Webhook URL** (e.g., `https://discord.com/api/webhooks/XXX/XXX`)

#### **Custom Webhook Setup**

- Use any HTTP endpoint that accepts POST requests
- Add custom headers for authentication if needed

---

## 🛠 Initialize in `main.dart`

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:crash_reporter/crash_reporter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with your credentials
  CrashReporter.initialize(
    showDebugPrint: true,

    // Telegram
    telegramConfig: TelegramConfig(
      botToken: '123456:XXXXXX',
      chatId: -123,
      parseMode: 'HTML',
      disableWebPagePreview: true,
      disableNotification: false,
    ),

    // Slack
    slackConfig: SlackConfig(
      webhookUrl: 'https://hooks.slack.com/services/XXX/XXX/XXX',
    ),

    // Discord
    discordConfig: DiscordConfig(
      webhookUrl: 'https://discord.com/api/webhooks/XXX/XXX',
      username: '🚨 Crash Reporter',
      avatarUrl: 'https://randomuser.me/api/portraits/lego/8.jpg',
    ),

    // Webhook
    webhookConfig: WebhookConfig(
      url: 'http://example.com/api/webhook/test',
      headers: {'Authorization': 'Bearer your_token'},
    ),

    // Configuration - ENABLE the services you want
    notificationConfig: NotificationConfig(
      enableTelegram: true,
      enableSlack: true,
      enableDiscord: true,
      enableWebhook: true,
      sendCrashReports: true,
      sendEvents: true,
      sendStartupEvents: true,
    ),
  );

  // Send startup notification
  CrashReporter.sendAppStartup();

  // Catch Flutter UI framework errors
  FlutterError.onError = (details) {
    CrashReporter.reportCrash(
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      context: 'Flutter UI Error: ${details.library}',
      fatal: true,
      extraData: {
        'library': details.library,
        'stackFiltered': details.stackFilter,
      },
    );
  };

  // Catch unhandled Dart runtime errors
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporter.reportCrash(
      error: error,
      stackTrace: stack,
      context: 'Dart Runtime Error',
      fatal: true,
    );
    return true; // Keep app running
  };

  // Optional: Catch errors in the widget tree
  ErrorWidget.builder = (errorDetails) {
    CrashReporter.reportCrash(
      error: errorDetails.exception,
      stackTrace: errorDetails.stack!,
      context: 'Error Widget',
      fatal: false,
    );
    return ErrorWidget(errorDetails.exception);
  };

  runApp(const MyApp());
}
```

---

## 🧠 Usage Examples

### Report a Caught Exception

```dart
try {
  throw Exception("Something went wrong!");
} catch (e, s) {
  CrashReporter.reportCrash(
    error: e,
    stackTrace: s,
    context: 'User Action Failed',
    fatal: false,
  );
}
```

### Send a Custom Event

```dart
CrashReporter.sendEvent("User completed checkout successfully!");
```

### Send App Startup Notification

```dart
CrashReporter.sendAppStartup();
```

### Advanced: Custom Formatting with Extra Data

```dart
CrashReporter.reportCrash(
  error: error,
  stackTrace: stackTrace,
  context: 'Payment Processing',
  fatal: true,
  extraData: {
    'user_id': '12345',
    'screen': 'CheckoutPage',
    'version': '1.2.0',
    'payment_method': 'credit_card',
  },
);
```

---

## 📝 API Reference

| Method                                                        | Description                             |
| ------------------------------------------------------------- | --------------------------------------- |
| `initialize({...configs})`                                    | Initialize with platform configurations |
| `reportCrash({error, stackTrace, context, fatal, extraData})` | Report errors with stack traces         |
| `sendEvent(message)`                                          | Send custom event messages              |
| `sendAppStartup()`                                            | Send app startup notification           |

### Configuration Classes

**TelegramConfig:**

- `botToken` (required) — Your Telegram bot token
- `chatId` (required) — Target chat or channel ID
- `parseMode` — Message formatting (HTML, Markdown)
- `disableWebPagePreview` — Disable link previews
- `disableNotification` — Send silently

**SlackConfig:**

- `webhookUrl` (required) — Your Slack webhook URL

**DiscordConfig:**

- `webhookUrl` (required) — Your Discord webhook URL
- `username` — Custom bot name
- `avatarUrl` — Custom bot avatar

**WebhookConfig:**

- `url` (required) — Your custom webhook endpoint
- `headers` — Custom HTTP headers (for auth, etc.)

**NotificationConfig:**

- `enableTelegram` — Enable/disable Telegram
- `enableSlack` — Enable/disable Slack
- `enableDiscord` — Enable/disable Discord
- `enableWebhook` — Enable/disable custom webhook
- `sendCrashReports` — Enable crash reporting
- `sendEvents` — Enable event messages
- `sendStartupEvents` — Enable startup notifications

---

## 🎯 Use Cases

- **Development & Testing** — Get instant feedback on crashes during testing
- **Production Monitoring** — Track real-time errors in live apps
- **Team Collaboration** — Share crash reports across multiple channels
- **Custom Integrations** — Send reports to your own backend systems
- **Multi-environment Setup** — Different channels for dev, staging, production

---

## 🔒 Privacy & Security

- No data leaves your app except what **you** send
- All credentials stored securely in memory
- No analytics, tracking, or third-party servers
- Full control over what data is sent and where
- GDPR compliant — you own all the data

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License.

---

## 💬 Support

If you encounter any issues or have questions:

- Open an issue on [GitHub](https://github.com/cas8398/crash_reporter)
- Check existing issues for solutions
- Submit feature requests

---

**Made with ❤️ for the Flutter community**
