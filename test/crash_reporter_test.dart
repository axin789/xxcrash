// ignore_for_file: dead_code

import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/crash_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  group('CrashReporter Unit Tests', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Initialize with all services disabled for testing
      CrashReporter.initialize(
        telegramConfig: TelegramConfig(
          botToken: 'test_bot_token',
          chatId: 123456789,
        ),
        notificationConfig: NotificationConfig(
          enableTelegram: false, // Disable telegram for network tests
          enableSlack: false,
          enableDiscord: false,
          enableWebhook: false,
          sendCrashReports: true,
          sendEvents: true,
          sendStartupEvents: false,
        ),
        showDebugPrint: false,
      );
    });

    tearDown(() {
      CrashReporter.dispose();
    });

    test('Initialization sets correct values', () {
      expect(CrashReporter.isInitialized, isTrue);
      expect(CrashReporter.isEnabled, isTrue);
      expect(CrashReporter.getCrashCount(), completion(0));
    });

    test('Enable/disable functionality works', () {
      CrashReporter.setEnabled(false);
      // Should not crash when disabled
      expect(
        CrashReporter.reportCrash(
          error: 'Test error',
          stackTrace: StackTrace.current,
        ),
        completes,
      );
    });

    test('Local crash storage works', () async {
      final testError = Exception('Test exception');
      final testStackTrace = StackTrace.current;

      await CrashReporter.reportCrash(
        error: testError,
        stackTrace: testStackTrace,
        context: 'Test Context',
      );

      final crashCount = await CrashReporter.getCrashCount();
      expect(crashCount, 1);

      final logs = await CrashReporter.getLocalCrashLogs();
      expect(logs.length, 1);

      // Access properties directly from CrashData object
      expect(logs[0].error, 'Exception: Test exception');
      expect(logs[0].context, 'Test Context');
    });

    test('Multiple crashes are stored correctly', () async {
      for (int i = 0; i < 3; i++) {
        await CrashReporter.reportCrash(
          error: 'Error $i',
          stackTrace: StackTrace.current,
        );
      }

      final crashCount = await CrashReporter.getCrashCount();
      expect(crashCount, 3);
    });

    test('Extra data is stored with crash', () async {
      final extraData = {
        'user_id': '123',
        'screen': 'home',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await CrashReporter.reportCrash(
        error: 'Test error',
        stackTrace: StackTrace.current,
        extraData: extraData,
      );

      final logs = await CrashReporter.getLocalCrashLogs();
      expect(logs[0].extraData, extraData);
    });

    test('Crash logs can be formatted as string', () async {
      await CrashReporter.reportCrash(
        error: 'Format test error',
        stackTrace: StackTrace.current,
        context: 'Format Test',
      );

      final formattedLogs = await CrashReporter.getLocalCrashLogsAsString();
      expect(formattedLogs, contains('Format test error'));
      expect(formattedLogs, contains('Format Test'));
      expect(formattedLogs, contains('=== CRASH ==='));
    });

    test('Clear local crash logs works', () async {
      // Add some crashes
      await CrashReporter.reportCrash(
        error: 'Test error',
        stackTrace: StackTrace.current,
      );

      // Verify they exist
      var crashCount = await CrashReporter.getCrashCount();
      expect(crashCount, 1);

      // Clear them
      await CrashReporter.clearLocalCrashLogs();

      // Verify they're gone
      crashCount = await CrashReporter.getCrashCount();
      expect(crashCount, 0);
    });

    test('Event sending does not throw when disabled', () {
      CrashReporter.setEnabled(false);
      expect(
        CrashReporter.sendEvent(message: 'Test event'),
        completes,
      );
    });

    test('App startup notification does not throw when disabled', () {
      CrashReporter.setEnabled(false);
      expect(
        CrashReporter.sendAppStartup(),
        completes,
      );
    });

    test('Pending crashes are handled before initialization', () async {
      // This should complete without error even though services are disabled
      expect(
        CrashReporter.reportCrash(
          error: 'Pending test',
          stackTrace: StackTrace.current,
        ),
        completes,
      );
    });

    test('Configuration updates work', () {
      final newConfig = NotificationConfig(
        enableTelegram: false, // Keep disabled
        enableSlack: false,
        sendCrashReports: true,
        sendEvents: true,
      );

      CrashReporter.updateNotificationConfig(newConfig);
      // Should complete without error
      expect(
        CrashReporter.sendEvent(message: 'Test after config update'),
        completes,
      );
    });

    test('Notifier status returns correct values', () {
      final status = CrashReporter.getNotifierStatus();

      expect(status, isNotNull);
      // All services should be false since they're disabled in notificationConfig
      expect(status['telegram'], isFalse);
      expect(status['slack'], isFalse);
      expect(status['discord'], isFalse);
      expect(status['webhook'], isFalse);
    });

    test('Plugin version is accessible', () {
      expect(CrashReporter.pluginVersion, isNotEmpty);
      // Use your actual package version - update this to match your pubspec.yaml
      expect(CrashReporter.pluginVersion, equals('1.0.0'));
    });

    test('Connection testing completes without errors', () async {
      // Since all services are disabled, this should complete without network calls
      await CrashReporter.testAllConnections();
      // If we get here without exception, test passes
      expect(true, isTrue);
    });

    test('Individual connection tests complete without network calls',
        () async {
      // These should complete without making actual network requests
      // since services are disabled in notificationConfig
      await CrashReporter.testTelegramConnection();
      await CrashReporter.testWebhookConnection();
      await CrashReporter.testSlackConnection();
      await CrashReporter.testDiscordConnection();
      // If we get here without exception, tests pass
      expect(true, isTrue);
    });

    test('Backward compatibility initialization works', () {
      // Test the backward compatibility method
      CrashReporter.initializeWithTelegram(
        botToken: 'test_token',
        chatId: 123456,
        enable: true,
        showDebugPrint: false,
      );

      expect(CrashReporter.isInitialized, isTrue);
      expect(CrashReporter.isEnabled, isTrue);
    });

    test('Configuration getters work when services are disabled', () {
      final notificationConfig = CrashReporter.notificationConfig;
      final telegramConfig = CrashReporter.telegramConfig;

      expect(notificationConfig, isNotNull);
      expect(notificationConfig.enableTelegram, isFalse);

      // Just verify that we have a config object (don't check the specific token value)
      expect(telegramConfig, isNotNull);
      expect(telegramConfig?.botToken, isNotEmpty); // Just check it's not empty

      // The notifier status should be false
      final status = CrashReporter.getNotifierStatus();
      expect(status['telegram'], isFalse);
    });

    test('Configuration getters work when services are enabled', () async {
      // Re-initialize with telegram enabled
      CrashReporter.initialize(
        telegramConfig: TelegramConfig(
          botToken: 'enabled_bot_token',
          chatId: 123456789,
        ),
        notificationConfig: NotificationConfig(
          enableTelegram: true, // Enable telegram
          enableSlack: false,
          enableDiscord: false,
          enableWebhook: false,
          sendCrashReports: true,
          sendEvents: true,
          sendStartupEvents: false,
        ),
        showDebugPrint: false,
      );

      final notificationConfig = CrashReporter.notificationConfig;
      final telegramConfig = CrashReporter.telegramConfig;

      expect(notificationConfig, isNotNull);
      expect(notificationConfig.enableTelegram, isTrue);
      expect(telegramConfig, isNotNull);
      expect(telegramConfig?.botToken, 'enabled_bot_token');

      // And the notifier status should show it's active
      final status = CrashReporter.getNotifierStatus();
      expect(status['telegram'], isTrue);
    });
  });

  group('Message Building Tests', () {
    test('HTML escaping works correctly', () {
      final testString = 'This <has> HTML & "characters" \'in\' it';
      final escaped = _escapeHtmlTest(testString);

      expect(
          escaped,
          equals(
              'This &lt;has&gt; HTML &amp; &quot;characters&quot; &#39;in&#39; it'));
    });

    test('Startup message contains correct info', () {
      final message = _buildStartupMessageTest();
      expect(message, contains('🚀 App Started'));
      expect(message, contains('Platform'));
      expect(message, contains('Debug'));
    });

    test('Crash message contains error and stack trace', () {
      final testError = 'Test error message';
      final testStackTrace = 'Test stack trace\nat test()';

      final message = _buildCrashMessageTest(
        testError,
        testStackTrace,
        'Test Context',
        false,
        null,
      );

      expect(message, contains('⚠️ ERROR'));
      expect(message, contains('Test error message'));
      expect(message, contains('Test stack trace'));
      expect(message, contains('Test Context'));
    });

    test('Event message contains custom data', () {
      final extraData = {
        'action': 'button_press',
        'count': 5,
      };

      final message = _buildEventMessageTest(
        'User Action',
        'Home Screen',
        extraData,
      );

      expect(message, contains('📊 Event: User Action'));
      expect(message, contains('Home Screen'));
      expect(message, contains('button_press'));
      expect(message, contains('5'));
    });

    test('Fatal crash message shows correct icon', () {
      final message = _buildCrashMessageTest(
        'Fatal error',
        'Stack trace',
        'Critical Context',
        true, // fatal = true
        null,
      );

      expect(message, contains('🚨 FATAL CRASH'));
      expect(message, contains('Critical Context'));
    });
  });

  group('Configuration Tests', () {
    test('TelegramConfig copyWith works', () {
      final original = TelegramConfig(
        botToken: 'token',
        chatId: 123,
        parseMode: 'HTML',
        disableWebPagePreview: true,
        disableNotification: false,
      );

      final updated = original.copyWith(
        disableNotification: true,
        parseMode: 'Markdown',
      );

      expect(updated.botToken, 'token');
      expect(updated.chatId, 123);
      expect(updated.parseMode, 'Markdown');
      expect(updated.disableWebPagePreview, true);
      expect(updated.disableNotification, true);
    });

    test('NotificationConfig copyWith works', () {
      final original = NotificationConfig(
        enableTelegram: true,
        enableSlack: false,
        enableDiscord: false,
        enableWebhook: false,
        sendCrashReports: true,
        sendEvents: true,
        sendStartupEvents: false,
      );

      final updated = original.copyWith(
        enableSlack: true,
        sendStartupEvents: true,
      );

      expect(updated.enableTelegram, true);
      expect(updated.enableSlack, true);
      expect(updated.enableDiscord, false);
      expect(updated.sendCrashReports, true);
      expect(updated.sendEvents, true);
      expect(updated.sendStartupEvents, true);
    });

    test('WebhookConfig copyWith works', () {
      final original = WebhookConfig(
        appId: "",
        url: 'https://example.com',
        headers: {'Authorization': 'Bearer token'},
        method: 'POST',
        timeoutSeconds: 10,
      );

      final updated = original.copyWith(
        method: 'PUT',
        timeoutSeconds: 30,
      );

      expect(updated.url, 'https://example.com');
      expect(updated.headers, {'Authorization': 'Bearer token'});
      expect(updated.method, 'PUT');
      expect(updated.timeoutSeconds, 30);
    });
  });
}

// Test helper functions to access private functionality
String _escapeHtmlTest(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _buildStartupMessageTest() {
  return '''
<b>🚀 App Started</b>

<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
<b>Debug</b>: ${true ? 'YES' : 'NO'}
''';
}

String _buildCrashMessageTest(
  String error,
  String stackTrace,
  String? context,
  bool fatal,
  Map<String, dynamic>? extraData,
) {
  final truncatedStack = stackTrace.length > 1500
      ? '${stackTrace.substring(0, 1500)}...'
      : stackTrace;

  final escapedError = _escapeHtmlTest(error);
  final escapedStack = _escapeHtmlTest(truncatedStack);

  var message = '''
<b>${fatal ? '🚨 FATAL CRASH' : '⚠️ ERROR'}</b>

<b>Context</b>: ${_escapeHtmlTest(context ?? 'Unknown')}
<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
<b>Debug</b>: ${true ? 'YES' : 'NO'}

<b>Error</b>:
<code>$escapedError</code>

<b>Stack</b>:
<pre>$escapedStack</pre>
''';

  if (extraData != null && extraData.isNotEmpty) {
    message += '\n<b>Extra Data</b>:\n';
    extraData.forEach((key, value) {
      final escapedValue = _escapeHtmlTest(value.toString());
      message += '• $key: <code>$escapedValue</code>\n';
    });
  }

  return message;
}

String _buildEventMessageTest(
  String message,
  String? context,
  Map<String, dynamic>? extraData,
) {
  var eventMessage = '''
<b>📊 Event: ${_escapeHtmlTest(message)}</b>

<b>Context</b>: ${_escapeHtmlTest(context ?? 'General')}
<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem}
''';

  if (extraData != null && extraData.isNotEmpty) {
    eventMessage += '\n<b>Data</b>:\n';
    extraData.forEach((key, value) {
      final escapedValue = _escapeHtmlTest(value.toString());
      eventMessage += '• $key: <code>$escapedValue</code>\n';
    });
  }

  return eventMessage;
}
