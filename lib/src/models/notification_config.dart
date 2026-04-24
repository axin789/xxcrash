import 'package:xcrash/src/models/parse_mode.dart';

class NotificationConfig {
  final bool enableTelegram;
  final bool enableWebhook;
  final bool enableSlack;
  final bool enableDiscord;
  final bool sendCrashReports;
  final bool sendEvents;
  final bool sendStartupEvents;

  const NotificationConfig({
    this.enableTelegram = true,
    this.enableWebhook = false,
    this.enableSlack = false,
    this.enableDiscord = false,
    this.sendCrashReports = true,
    this.sendEvents = true,
    this.sendStartupEvents = false,
  });

  NotificationConfig copyWith({
    bool? enableTelegram,
    bool? enableWebhook,
    bool? enableSlack,
    bool? enableDiscord,
    bool? sendCrashReports,
    bool? sendEvents,
    bool? sendStartupEvents,
  }) {
    return NotificationConfig(
      enableTelegram: enableTelegram ?? this.enableTelegram,
      enableWebhook: enableWebhook ?? this.enableWebhook,
      enableSlack: enableSlack ?? this.enableSlack,
      enableDiscord: enableDiscord ?? this.enableDiscord,
      sendCrashReports: sendCrashReports ?? this.sendCrashReports,
      sendEvents: sendEvents ?? this.sendEvents,
      sendStartupEvents: sendStartupEvents ?? this.sendStartupEvents,
    );
  }
}

class TelegramConfig {
  final String botToken;
  final int chatId;
  final String? parseMode; // HTML, Markdown, etc.
  final bool disableWebPagePreview;
  final bool disableNotification;

  const TelegramConfig({
    required this.botToken,
    required this.chatId,
    this.parseMode = 'HTML',
    this.disableWebPagePreview = true,
    this.disableNotification = false,
  });

  TelegramConfig copyWith({
    String? botToken,
    int? chatId,
    String? parseMode,
    bool? disableWebPagePreview,
    bool? disableNotification,
  }) {
    return TelegramConfig(
      botToken: botToken ?? this.botToken,
      chatId: chatId ?? this.chatId,
      parseMode: parseMode ?? this.parseMode,
      disableWebPagePreview:
          disableWebPagePreview ?? this.disableWebPagePreview,
      disableNotification: disableNotification ?? this.disableNotification,
    );
  }
}

class WebhookConfig {
  final String url;
  final ParseMode parseMode;
  final Map<String, String> headers;
  final String method; // POST, PUT, etc.
  final int timeoutSeconds;
  final String appId;

  const WebhookConfig({
    required this.url,
    required this.appId,
    this.parseMode = ParseMode.html,
    this.headers = const {},
    this.method = 'POST',
    this.timeoutSeconds = 10,
  });

  WebhookConfig copyWith({
    String? url,
    String? appId,
    Map<String, String>? headers,
    String? method,
    int? timeoutSeconds,
  }) {
    return WebhookConfig(
      url: url ?? this.url,
      appId: appId ?? this.appId,
      headers: headers ?? this.headers,
      method: method ?? this.method,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }
}

class SlackConfig {
  final String webhookUrl;
  final String channel;
  final String username;
  final String? iconEmoji;
  final String? iconUrl;

  const SlackConfig({
    required this.webhookUrl,
    this.channel = '#general',
    this.username = 'Crash Reporter',
    this.iconEmoji,
    this.iconUrl,
  });

  SlackConfig copyWith({
    String? webhookUrl,
    String? channel,
    String? username,
    String? iconEmoji,
    String? iconUrl,
  }) {
    return SlackConfig(
      webhookUrl: webhookUrl ?? this.webhookUrl,
      channel: channel ?? this.channel,
      username: username ?? this.username,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      iconUrl: iconUrl ?? this.iconUrl,
    );
  }
}

class DiscordConfig {
  final String webhookUrl;
  final String username;
  final String? avatarUrl;
  final bool tts; // text-to-speech

  const DiscordConfig({
    required this.webhookUrl,
    this.username = 'Crash Reporter',
    this.avatarUrl,
    this.tts = false,
  });

  DiscordConfig copyWith({
    String? webhookUrl,
    String? username,
    String? avatarUrl,
    bool? tts,
  }) {
    return DiscordConfig(
      webhookUrl: webhookUrl ?? this.webhookUrl,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      tts: tts ?? this.tts,
    );
  }
}
