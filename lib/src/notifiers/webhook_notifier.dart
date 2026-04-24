import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xcrash/src/models/parse_mode.dart';
import '../../crash_reporter.dart';
import '../message_builder.dart';
import 'base_notifier.dart';
import 'package:crypto/crypto.dart';

class WebhookNotifier extends BaseNotifier {
  final WebhookConfig config;
  final HttpClient _httpClient;

  WebhookNotifier({required this.config, required Function(String) debugPrint})
    : _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10),
      super(debugPrint: debugPrint, notifierName: 'WebhookNotifier');

  @override
  Future<void> sendCrashReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) async {
    late final Map<String, dynamic> payload;
    switch (config.parseMode) {
      case ParseMode.None:
        payload = {
          'data': MessageBuilder.buildCrashPlainTextMessage(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          ),
        };
        break;
      case ParseMode.html:
        payload = {
          'data': MessageBuilder.buildCrashHtmlMessage(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          ),
        };
        break;
      case ParseMode.markdown:
        payload = {
          'data': MessageBuilder.buildCrashMarkdownMessage(
            error: error,
            stackTrace: stackTrace,
            context: context,
            fatal: fatal,
            extraData: extraData,
          ),
        };
        break;
      case ParseMode.json:
        payload = {
          'type': 'crash_report',
          'timestamp': DateTime.now().toIso8601String(),
          'data': {
            'error': error.toString(),
            'stack_trace': stackTrace.toString(),
            'context': context,
            'fatal': fatal,
            'extra_data': extraData,
            'platform':
                '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
            'debug_mode': kDebugMode,
          },
        };
        break;
    }
    await _sendPayload(payload);
  }

  @override
  Future<void> sendEvent({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
  }) async {
    final payload = {
      'type': 'event',
      'timestamp': DateTime.now().toIso8601String(),
      'data': {
        'message': message,
        'context': context,
        'extra_data': extraData,
        'platform': Platform.operatingSystem,
      },
    };

    await _sendPayload(payload);
  }

  @override
  Future<void> sendAppStartup() async {
    final payload = {
      'type': 'app_startup',
      'timestamp': DateTime.now().toIso8601String(),
      'data': {
        'platform':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'debug_mode': kDebugMode,
      },
    };

    await _sendPayload(payload);
  }

  Future<void> _sendPayload(Map<String, dynamic> payload) async {
    HttpClientRequest? request;
    try {
      final uri = Uri.parse(config.url);
      request = await _httpClient.openUrl(config.method, uri);
      // Set headers
      final _appId = config.appId;
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final key = md5.convert(utf8.encode(_appId + ts)).toString();
      if (config.parseMode == ParseMode.html ||
          config.parseMode == ParseMode.markdown) {

        request.headers.set("parse_mode", config.parseMode.value);
      }
      request.headers.set("ts", ts);
      request.headers.set("key", key);
      request.headers.set("appid", _appId);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      config.headers.forEach((key, value) {
        request!.headers.set(key, value);
      });

      final jsonString = jsonEncode(payload);
      request.write(jsonString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('✅ Payload sent successfully (${response.statusCode})');
      } else {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      log('❌ Failed to send webhook: $e');
      rethrow;
    } finally {
      request?.abort();
    }
  }

  @override
  Future<void> testConnection() async {
    final testPayload = {
      'type': 'test',
      'timestamp': DateTime.now().toIso8601String(),
      'data': {'message': 'Test connection from Flutter Crash Reporter'},
    };

    await _sendPayload(testPayload);
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}
