import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/notification_config.dart';
import 'base_notifier.dart';

class SlackNotifier extends BaseNotifier {
  final SlackConfig config;
  final HttpClient _httpClient;

  SlackNotifier({
    required this.config,
    required Function(String) debugPrint,
  })  : _httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10),
        super(debugPrint: debugPrint, notifierName: 'SlackNotifier');

  @override
  Future<void> sendCrashReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) async {
    final truncatedStack = stackTrace.toString().length > 1000
        ? '${stackTrace.toString().substring(0, 1000)}...'
        : stackTrace.toString();

    // Initialize fields as a properly typed list
    final fields = <Map<String, dynamic>>[
      {
        'title': 'Error',
        'value': '```${error.toString()}```',
        'short': false,
      },
      {
        'title': 'Platform',
        'value':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'short': true,
      },
      {
        'title': 'Debug Mode',
        'value': kDebugMode ? 'YES' : 'NO',
        'short': true,
      },
      {
        'title': 'Stack Trace',
        'value': '```$truncatedStack```',
        'short': false,
      },
    ];

    // Add extra data fields
    if (extraData != null && extraData.isNotEmpty) {
      final extraFields = extraData.entries
          .map((entry) => {
                'title': entry.key,
                'value': entry.value.toString(),
                'short': true,
              })
          .toList();
      fields.addAll(extraFields);
    }

    final attachments = [
      {
        'color': fatal ? '#ff0000' : '#ffaa00',
        'title':
            '${fatal ? '🚨 FATAL CRASH' : '⚠️ ERROR'} - ${context ?? 'Unknown'}',
        'fields': fields,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ];

    await _sendToSlack(attachments);
  }

  @override
  Future<void> sendEvent({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
  }) async {
    // Initialize fields as a properly typed list
    final fields = <Map<String, dynamic>>[
      {
        'title': 'Context',
        'value': context ?? 'General',
        'short': true,
      },
      {
        'title': 'Platform',
        'value': Platform.operatingSystem,
        'short': true,
      },
    ];

    // Add extra data fields
    if (extraData != null && extraData.isNotEmpty) {
      final dataFields = extraData.entries
          .map((entry) => {
                'title': entry.key,
                'value': entry.value.toString(),
                'short': true,
              })
          .toList();
      fields.addAll(dataFields);
    }

    final attachments = [
      {
        'color': '#36a64f',
        'title': '📊 Event: $message',
        'fields': fields,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ];

    await _sendToSlack(attachments);
  }

  @override
  Future<void> sendAppStartup() async {
    final attachments = [
      {
        'color': '#00b0f4',
        'title': '🚀 App Started',
        'fields': [
          {
            'title': 'Platform',
            'value':
                '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
            'short': true,
          },
          {
            'title': 'Debug Mode',
            'value': kDebugMode ? 'YES' : 'NO',
            'short': true,
          },
        ],
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ];

    await _sendToSlack(attachments);
  }

  Future<void> _sendToSlack(List<Map<String, dynamic>> attachments) async {
    HttpClientRequest? request;
    try {
      final uri = Uri.parse(config.webhookUrl);
      request = await _httpClient.postUrl(uri);

      final payload = {
        'channel': config.channel,
        'username': config.username,
        'attachments': attachments,
        if (config.iconEmoji != null) 'icon_emoji': config.iconEmoji,
      };

      final jsonString = jsonEncode(payload);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.write(jsonString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        log('✅ Message sent to Slack successfully');
      } else {
        throw Exception('Slack API ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      log('❌ Failed to send to Slack: $e');
      rethrow;
    } finally {
      request?.abort();
    }
  }

  @override
  Future<void> testConnection() async {
    final testAttachments = [
      {
        'color': '#00b0f4',
        'title': 'Test Connection',
        'text': 'This is a test message from Flutter Crash Reporter',
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ];

    await _sendToSlack(testAttachments);
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}
