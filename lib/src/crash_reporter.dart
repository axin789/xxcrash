import 'dart:io';
import 'package:flutter/foundation.dart';
import 'crash_storage.dart';
import 'models/crash_data.dart';
import 'models/notification_config.dart';
import 'notifiers/telegram_notifier.dart';
import 'notifiers/webhook_notifier.dart';
import 'notifiers/slack_notifier.dart';
import 'notifiers/discord_notifier.dart';

class CrashReporter {
  static const String version = '1.0.0'; //NOTE - Manual

  static bool _isInitialized = false;
  static bool _isEnabled = true;
  static bool _showDebugPrint = true;

  static final List<Map<String, dynamic>> _pendingCrashes = [];
  static late CrashStorage _crashStorage;

  // Notifiers
  static TelegramNotifier? _telegramNotifier;
  static WebhookNotifier? _webhookNotifier;
  static SlackNotifier? _slackNotifier;
  static DiscordNotifier? _discordNotifier;

  // Configuration
  static NotificationConfig _notificationConfig = const NotificationConfig();

  static void initialize({
    // Telegram configuration
    TelegramConfig? telegramConfig,

    // Webhook configuration
    WebhookConfig? webhookConfig,

    // Slack configuration
    SlackConfig? slackConfig,

    // Discord configuration
    DiscordConfig? discordConfig,

    // General configuration
    bool enable = true,
    NotificationConfig notificationConfig = const NotificationConfig(),
    bool showDebugPrint = true,
  }) {
    _isInitialized = true;
    _isEnabled = enable;
    _showDebugPrint = showDebugPrint;
    _notificationConfig = notificationConfig;

    _crashStorage = CrashStorage(debugPrint: _debugPrint);

    // Initialize notifiers based on configuration
    if (telegramConfig != null && notificationConfig.enableTelegram) {
      _telegramNotifier = TelegramNotifier(
        config: telegramConfig,
        debugPrint: _debugPrint,
      );
    }

    if (webhookConfig != null && notificationConfig.enableWebhook) {
      _webhookNotifier = WebhookNotifier(
        config: webhookConfig,
        debugPrint: _debugPrint,
      );
    }

    if (slackConfig != null && notificationConfig.enableSlack) {
      _slackNotifier = SlackNotifier(
        config: slackConfig,
        debugPrint: _debugPrint,
      );
    }

    if (discordConfig != null && notificationConfig.enableDiscord) {
      _discordNotifier = DiscordNotifier(
        config: discordConfig,
        debugPrint: _debugPrint,
      );
    }

    _sendPendingCrashes();

    _debugPrint('🚀 Crash Reporter v$version initialized with:');
    _debugPrint(
        '  • Telegram: ${_telegramNotifier != null ? "Enabled" : "Disabled"}');
    _debugPrint(
        '  • Webhook: ${_webhookNotifier != null ? "Enabled" : "Disabled"}');
    _debugPrint(
        '  • Slack: ${_slackNotifier != null ? "Enabled" : "Disabled"}');
    _debugPrint(
        '  • Discord: ${_discordNotifier != null ? "Enabled" : "Disabled"}');
  }

  // Backward compatibility method
  static void initializeWithTelegram({
    required String botToken,
    required int chatId,
    bool enable = false,
    bool showDebugPrint = true,
  }) {
    initialize(
      telegramConfig: TelegramConfig(
        botToken: botToken,
        chatId: chatId,
      ),
      notificationConfig: const NotificationConfig(
        enableTelegram: true,
        sendCrashReports: true,
        sendEvents: true,
        sendStartupEvents: false,
      ),
      enable: enable,
      showDebugPrint: showDebugPrint,
    );
  }

  // Configuration update methods
  static void updateNotificationConfig(NotificationConfig config) {
    _notificationConfig = config;
    _debugPrint('📋 Notification config updated');
  }

  static void updateTelegramConfig(TelegramConfig config) {
    if (_telegramNotifier != null) {
      _telegramNotifier!.updateConfig(config);
    } else {
      _telegramNotifier = TelegramNotifier(
        config: config,
        debugPrint: _debugPrint,
      );
    }
    _debugPrint('📋 Telegram config updated');
  }

  static void updateWebhookConfig(WebhookConfig config) {
    _webhookNotifier?.dispose();
    _webhookNotifier = WebhookNotifier(
      config: config,
      debugPrint: _debugPrint,
    );
    _debugPrint('📋 Webhook config updated');
  }

  static void updateSlackConfig(SlackConfig config) {
    _slackNotifier?.dispose();
    _slackNotifier = SlackNotifier(
      config: config,
      debugPrint: _debugPrint,
    );
    _debugPrint('📋 Slack config updated');
  }

  static void updateDiscordConfig(DiscordConfig config) {
    _discordNotifier?.dispose();
    _discordNotifier = DiscordNotifier(
      config: config,
      debugPrint: _debugPrint,
    );
    _debugPrint('📋 Discord config updated');
  }

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _debugPrint(
        '${enabled ? "✅" : "❌"} Crash Reporter ${enabled ? "enabled" : "disabled"}');
  }

  static void setShowDebugPrint(bool showDebug) {
    _showDebugPrint = showDebug;
  }

  static void _debugPrint(String message) {
    if (_showDebugPrint) {
      debugPrint('[CrashReporter] ==> $message');
    }
  }

  static Future<void> reportCrash({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
    NotificationConfig? configOverride,
  }) async {
    if (!_isEnabled) return;

    // Use override config or default config
    final config = configOverride ?? _notificationConfig;
    if (!config.sendCrashReports) {
      _debugPrint('📋 Crash report skipped (sendCrashReports: false)');
      return;
    }

    // Always debugPrint to console for local debugging
    _debugPrintToConsole(error, stackTrace, context, fatal);

    // Save to local storage immediately
    final crashData = CrashData(
      error: error.toString(),
      stackTrace: stackTrace.toString(),
      context: context,
      extraData: extraData,
      platform:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      debugMode: kDebugMode,
    );

    await _crashStorage.saveCrashLocally(crashData);

    // If not initialized, queue the crash for later
    if (!_isInitialized) {
      _pendingCrashes.add({
        'error': error,
        'stackTrace': stackTrace,
        'context': context,
        'fatal': fatal,
        'extraData': extraData,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _debugPrint('💾 Crash queued (${_pendingCrashes.length} pending)');
      return;
    }

    // Send to all enabled notifiers
    await _sendToAllNotifiers(
      error: error,
      stackTrace: stackTrace,
      context: context,
      fatal: fatal,
      extraData: extraData,
      config: config,
    );
  }

  static Future<void> sendEvent({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
    NotificationConfig? configOverride,
  }) async {
    if (!_isEnabled || !_isInitialized) return;

    final config = configOverride ?? _notificationConfig;
    if (!config.sendEvents) {
      _debugPrint('📋 Event skipped (sendEvents: false)');
      return;
    }

    try {
      await _sendEventToAllNotifiers(
        message: message,
        context: context,
        extraData: extraData,
        config: config,
      );
      _debugPrint('✅ Event sent: $message');
    } catch (e) {
      _debugPrint('❌ Failed to send event: $e');
    }
  }

  static Future<void> sendAppStartup({
    NotificationConfig? configOverride,
  }) async {
    if (!_isEnabled || !_isInitialized) return;

    final config = configOverride ?? _notificationConfig;
    if (!config.sendStartupEvents) {
      _debugPrint('📋 Startup notification skipped (sendStartupEvents: false)');
      return;
    }

    try {
      await _sendStartupToAllNotifiers(config: config);
      _debugPrint('✅ Startup notification sent');
    } catch (e) {
      _debugPrint('❌ Failed to send startup notification: $e');
    }
  }

  // PRIVATE METHODS

  static Future<void> _sendToAllNotifiers({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
    required NotificationConfig config,
  }) async {
    final futures = <Future>[];

    if (config.enableTelegram && _telegramNotifier != null) {
      futures.add(_telegramNotifier!
          .sendCrashReport(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Telegram error: $e')));
    }

    if (config.enableWebhook && _webhookNotifier != null) {
      futures.add(_webhookNotifier!
          .sendCrashReport(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Webhook error: $e')));
    }

    if (config.enableSlack && _slackNotifier != null) {
      futures.add(_slackNotifier!
          .sendCrashReport(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Slack error: $e')));
    }

    if (config.enableDiscord && _discordNotifier != null) {
      futures.add(_discordNotifier!
          .sendCrashReport(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Discord error: $e')));
    }

    if (futures.isEmpty) {
      _debugPrint('📋 No notifiers enabled for crash report');
      return;
    }

    await Future.wait(futures, eagerError: false);
    _debugPrint('✅ Crash report sent to ${futures.length} notifier(s)');
  }

  static Future<void> _sendEventToAllNotifiers({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
    required NotificationConfig config,
  }) async {
    final futures = <Future>[];

    if (config.enableTelegram && _telegramNotifier != null) {
      futures.add(_telegramNotifier!
          .sendEvent(
            message: message,
            context: context,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Telegram event error: $e')));
    }

    if (config.enableWebhook && _webhookNotifier != null) {
      futures.add(_webhookNotifier!
          .sendEvent(
            message: message,
            context: context,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Webhook event error: $e')));
    }

    if (config.enableSlack && _slackNotifier != null) {
      futures.add(_slackNotifier!
          .sendEvent(
            message: message,
            context: context,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Slack event error: $e')));
    }

    if (config.enableDiscord && _discordNotifier != null) {
      futures.add(_discordNotifier!
          .sendEvent(
            message: message,
            context: context,
            extraData: extraData,
          )
          .catchError((e) => _debugPrint('❌ Discord event error: $e')));
    }

    if (futures.isEmpty) {
      _debugPrint('📋 No notifiers enabled for event');
      return;
    }

    await Future.wait(futures, eagerError: false);
  }

  static Future<void> _sendStartupToAllNotifiers({
    required NotificationConfig config,
  }) async {
    final futures = <Future>[];

    if (config.enableTelegram && _telegramNotifier != null) {
      futures.add(_telegramNotifier!
          .sendAppStartup()
          .catchError((e) => _debugPrint('❌ Telegram startup error: $e')));
    }

    if (config.enableWebhook && _webhookNotifier != null) {
      futures.add(_webhookNotifier!
          .sendAppStartup()
          .catchError((e) => _debugPrint('❌ Webhook startup error: $e')));
    }

    if (config.enableSlack && _slackNotifier != null) {
      futures.add(_slackNotifier!
          .sendAppStartup()
          .catchError((e) => _debugPrint('❌ Slack startup error: $e')));
    }

    if (config.enableDiscord && _discordNotifier != null) {
      futures.add(_discordNotifier!
          .sendAppStartup()
          .catchError((e) => _debugPrint('❌ Discord startup error: $e')));
    }

    if (futures.isEmpty) {
      _debugPrint('📋 No notifiers enabled for startup');
      return;
    }

    await Future.wait(futures, eagerError: false);
  }

  static void _debugPrintToConsole(
    dynamic error,
    StackTrace stackTrace,
    String? context,
    bool fatal,
  ) {
    if (_showDebugPrint) {
      debugPrint('''
=== CRASH REPORT ===
Context: $context
Fatal: $fatal
Error: $error
Stack: $stackTrace
====================
''');
    }
  }

  static Future<void> _sendPendingCrashes() async {
    if (_pendingCrashes.isEmpty) return;

    _debugPrint('📤 Sending ${_pendingCrashes.length} pending crashes...');

    for (final crash in _pendingCrashes) {
      await _sendToAllNotifiers(
        error: crash['error'],
        stackTrace: crash['stackTrace'],
        context: crash['context'],
        fatal: crash['fatal'],
        extraData: crash['extraData'],
        config: _notificationConfig,
      );
      // Small delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _pendingCrashes.clear();
    _debugPrint('✅ All pending crashes sent');
  }

  // PUBLIC METHODS

  static Future<List<CrashData>> getLocalCrashLogs() async {
    return await _crashStorage.getLocalCrashLogs();
  }

  static Future<String> getLocalCrashLogsAsString() async {
    try {
      final crashes = await getLocalCrashLogs();
      if (crashes.isEmpty) return 'No crash logs found';

      final buffer = StringBuffer();
      for (final crash in crashes) {
        buffer.writeln('=== CRASH ===');
        buffer.writeln('Time: ${crash.timestamp}');
        buffer.writeln('Context: ${crash.context}');
        buffer.writeln('Error: ${crash.error}');
        buffer.writeln('Platform: ${crash.platform}');
        buffer.writeln('Debug: ${crash.debugMode}');

        if (crash.extraData != null) {
          buffer.writeln('Extra Data: ${crash.extraData}');
        }
        buffer.writeln('---');
      }

      return buffer.toString();
    } catch (e) {
      return 'Error formatting crash logs: $e';
    }
  }

  static Future<void> clearLocalCrashLogs() async {
    await _crashStorage.clearLocalCrashLogs();
    _debugPrint('🗑️ Local crash logs cleared');
  }

  static Future<int> getCrashCount() async {
    final crashes = await getLocalCrashLogs();
    return crashes.length;
  }

  // Test methods
  static Future<void> testAllConnections() async {
    if (!_isInitialized) {
      _debugPrint('❌ Not initialized');
      return;
    }

    _debugPrint('=== TESTING ALL CONNECTIONS ===');

    final futures = <Future>[];

    if (_telegramNotifier != null) {
      futures.add(_telegramNotifier!
          .testConnection()
          .catchError((e) => _debugPrint('❌ Telegram test failed: $e')));
    }

    if (_webhookNotifier != null) {
      futures.add(_webhookNotifier!
          .testConnection()
          .catchError((e) => _debugPrint('❌ Webhook test failed: $e')));
    }

    if (_slackNotifier != null) {
      futures.add(_slackNotifier!
          .testConnection()
          .catchError((e) => _debugPrint('❌ Slack test failed: $e')));
    }

    if (_discordNotifier != null) {
      futures.add(_discordNotifier!
          .testConnection()
          .catchError((e) => _debugPrint('❌ Discord test failed: $e')));
    }

    if (futures.isEmpty) {
      _debugPrint('📋 No notifiers configured for testing');
      return;
    }

    await Future.wait(futures, eagerError: false);
    _debugPrint('✅ All connection tests completed');
  }

  static Future<void> testTelegramConnection() async {
    if (_telegramNotifier == null) {
      _debugPrint('❌ Telegram not configured');
      return;
    }
    await _telegramNotifier!.testConnection();
  }

  static Future<void> testWebhookConnection() async {
    if (_webhookNotifier == null) {
      _debugPrint('❌ Webhook not configured');
      return;
    }
    await _webhookNotifier!.testConnection();
  }

  static Future<void> testSlackConnection() async {
    if (_slackNotifier == null) {
      _debugPrint('❌ Slack not configured');
      return;
    }
    await _slackNotifier!.testConnection();
  }

  static Future<void> testDiscordConnection() async {
    if (_discordNotifier == null) {
      _debugPrint('❌ Discord not configured');
      return;
    }
    await _discordNotifier!.testConnection();
  }

  // Status methods
  static bool get isInitialized => _isInitialized;
  static bool get isEnabled => _isEnabled;
  static String get pluginVersion => version;

  static Map<String, bool> getNotifierStatus() {
    return {
      'telegram':
          _notificationConfig.enableTelegram && _telegramNotifier != null,
      'webhook': _notificationConfig.enableWebhook && _webhookNotifier != null,
      'slack': _notificationConfig.enableSlack && _slackNotifier != null,
      'discord': _notificationConfig.enableDiscord && _discordNotifier != null,
    };
  }

  // Configuration getters
  static NotificationConfig get notificationConfig => _notificationConfig;
  static TelegramConfig? get telegramConfig => _telegramNotifier?.currentConfig;
  static WebhookConfig? get webhookConfig => _webhookNotifier?.config;
  static SlackConfig? get slackConfig => _slackNotifier?.config;
  static DiscordConfig? get discordConfig => _discordNotifier?.config;

  // Clean up resources
  static void dispose() {
    _telegramNotifier?.dispose();
    _webhookNotifier?.dispose();
    _slackNotifier?.dispose();
    _discordNotifier?.dispose();
    _debugPrint('🔚 Crash Reporter disposed');
  }
}
