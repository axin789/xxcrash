import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/notification_config.dart';
import 'base_notifier.dart';

class DiscordNotifier extends BaseNotifier {
  final DiscordConfig config;
  final HttpClient _httpClient;

  DiscordNotifier({
    required this.config,
    required Function(String) debugPrint,
  })  : _httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10),
        super(debugPrint: debugPrint, notifierName: 'DiscordNotifier');

  @override
  Future<void> sendCrashReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) async {
    final truncatedError = error.toString().length > 1000
        ? '${error.toString().substring(0, 1000)}...'
        : error.toString();

    final truncatedStack = stackTrace.toString().length > 1000
        ? '${stackTrace.toString().substring(0, 1000)}...'
        : stackTrace.toString();

    // Initialize fields as a properly typed list
    final fields = <Map<String, dynamic>>[
      {
        'name': 'Context',
        'value': context ?? 'Unknown',
        'inline': true,
      },
      {
        'name': 'Platform',
        'value':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'inline': true,
      },
      {
        'name': 'Debug Mode',
        'value': kDebugMode ? 'YES' : 'NO',
        'inline': true,
      },
      {
        'name': 'Error',
        'value': '```$truncatedError```',
      },
      {
        'name': 'Stack Trace',
        'value': '```$truncatedStack```',
      },
    ];

    // Add extra data fields
    if (extraData != null && extraData.isNotEmpty) {
      final extraFields = extraData.entries
          .map((entry) => {
                'name': entry.key,
                'value': entry.value.toString(),
                'inline': true,
              })
          .toList();
      fields.addAll(extraFields);
    }

    final embed = {
      'title': '${fatal ? '🚨 FATAL CRASH' : '⚠️ ERROR'}',
      'color': fatal ? 0xff0000 : 0xffaa00,
      'fields': fields,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _sendToDiscord(embed);
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
        'name': 'Context',
        'value': context ?? 'General',
        'inline': true,
      },
      {
        'name': 'Platform',
        'value': Platform.operatingSystem,
        'inline': true,
      },
    ];

    // Add extra data fields
    if (extraData != null && extraData.isNotEmpty) {
      final dataFields = extraData.entries
          .map((entry) => {
                'name': entry.key,
                'value': entry.value.toString(),
                'inline': true,
              })
          .toList();
      fields.addAll(dataFields);
    }

    final embed = {
      'title': '📊 Event: $message',
      'color': 0x36a64f,
      'fields': fields,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _sendToDiscord(embed);
  }

  @override
  Future<void> sendAppStartup() async {
    final embed = {
      'title': '🚀 App Started',
      'color': 0x00b0f4,
      'fields': [
        {
          'name': 'Platform',
          'value':
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'inline': true,
        },
        {
          'name': 'Debug Mode',
          'value': kDebugMode ? 'YES' : 'NO',
          'inline': true,
        },
      ],
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _sendToDiscord(embed);
  }

  Future<void> _sendToDiscord(Map<String, dynamic> embed) async {
    HttpClientRequest? request;
    try {
      final uri = Uri.parse(config.webhookUrl);
      request = await _httpClient.postUrl(uri);

      final payload = {
        'username': config.username,
        'embeds': [embed],
        if (config.avatarUrl != null) 'avatar_url': config.avatarUrl,
      };

      final jsonString = jsonEncode(payload);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.write(jsonString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 204) {
        log('✅ Message sent to Discord successfully');
      } else {
        throw Exception('Discord API ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      log('❌ Failed to send to Discord: $e');
      rethrow;
    } finally {
      request?.abort();
    }
  }

  @override
  Future<void> testConnection() async {
    final testEmbed = {
      'title': 'Test Connection',
      'description': 'This is a test message from Flutter Crash Reporter',
      'color': 0x00b0f4,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _sendToDiscord(testEmbed);
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}
