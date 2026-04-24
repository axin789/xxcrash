import 'dart:convert';
import 'dart:io';

import 'package:xcrash/crash_reporter.dart';

class TelegramApi {
  final String _botToken;
  final int _chatId;
  final HttpClient _httpClient;
  final Function(String) _debugPrint;

  TelegramApi({
    required String botToken,
    required int chatId,
    required Function(String) debugPrint,
  })  : _botToken = botToken,
        _chatId = chatId,
        _debugPrint = debugPrint,
        _httpClient = HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  Future<void> sendMessage(
    String message, {
    String? parseMode,
    bool? disableWebPagePreview,
    bool? disableNotification,
  }) async {
    HttpClientRequest? request;
    try {
      final url = 'https://api.telegram.org/bot$_botToken/sendMessage';

      _debugPrint('🔗 Telegram API URL: $url');
      _debugPrint('💬 Chat ID: $_chatId');
      _debugPrint('📝 Message length: ${message.length}');
      _debugPrint('🎨 Parse mode: ${parseMode ?? 'HTML'}');

      request = await _httpClient.postUrl(Uri.parse(url));

      final payload = {
        'chat_id': _chatId,
        'text': message,
        'parse_mode': parseMode ?? 'HTML',
        'disable_web_page_preview': disableWebPagePreview ?? true,
        'disable_notification': disableNotification ?? false,
      };

      final jsonString = jsonEncode(payload);

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers
          .set('User-Agent', 'FlutterCrashReporter/${_getPackageVersion()}');
      request.write(jsonString);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      _debugPrint('📡 Response status: ${response.statusCode}');
      _debugPrint('📨 Response body: $responseBody');

      if (response.statusCode != 200) {
        String errorMsg;
        try {
          final responseData = jsonDecode(responseBody);
          errorMsg = responseData['description'] ?? 'Unknown error';
        } catch (e) {
          errorMsg = responseBody;
        }

        // Specific error handling
        if (response.statusCode == 404) {
          errorMsg =
              '404 Not Found - Check: 1) Bot token, 2) Chat ID, 3) Bot added to chat';
        } else if (response.statusCode == 400) {
          errorMsg =
              '400 Bad Request - Check chat ID format or message content';
        } else if (response.statusCode == 401) {
          errorMsg = '401 Unauthorized - Invalid bot token';
        } else if (response.statusCode == 429) {
          errorMsg = '429 Rate Limited - Too many requests, try again later';
        }

        throw Exception('Telegram API ${response.statusCode}: $errorMsg');
      }

      _debugPrint('✅ Telegram message sent successfully!');
    } catch (e) {
      _debugPrint('❌ Telegram API Error: $e');

      // Re-throw with more context
      if (e is SocketException) {
        throw Exception(
            'Network error: Unable to connect to Telegram API - ${e.message}');
      } else if (e is HttpException) {
        throw Exception('HTTP error: ${e.message}');
      } else {
        rethrow;
      }
    } finally {
      request?.abort();
    }
  }

  // Method to send a simple text message (convenience method)
  Future<void> sendSimpleMessage(String text) async {
    await sendMessage(text);
  }

  // Method to test bot token validity
  Future<bool> testBotToken() async {
    HttpClientRequest? request;
    try {
      final url = 'https://api.telegram.org/bot$_botToken/getMe';
      request = await _httpClient.getUrl(Uri.parse(url));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final responseData = jsonDecode(responseBody);
        final isOk = responseData['ok'] == true;
        if (isOk) {
          final user = responseData['result'];
          _debugPrint(
              '🤖 Bot info: ${user['username']} (${user['first_name']})');
        }
        return isOk;
      }
      return false;
    } catch (e) {
      _debugPrint('❌ Bot token test failed: $e');
      return false;
    } finally {
      request?.abort();
    }
  }

  // Method to get bot information
  Future<Map<String, dynamic>?> getBotInfo() async {
    HttpClientRequest? request;
    try {
      final url = 'https://api.telegram.org/bot$_botToken/getMe';
      request = await _httpClient.getUrl(Uri.parse(url));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final responseData = jsonDecode(responseBody);
        if (responseData['ok'] == true) {
          return responseData['result'];
        }
      }
      return null;
    } catch (e) {
      _debugPrint('❌ Failed to get bot info: $e');
      return null;
    } finally {
      request?.abort();
    }
  }

  // Method to check if bot can send messages to chat
  Future<bool> canSendToChat() async {
    try {
      await sendMessage(
        '🧪 Permission test message from Flutter Crash Reporter',
        disableNotification: true,
      );
      return true;
    } catch (e) {
      _debugPrint('❌ Cannot send to chat: $e');
      return false;
    }
  }

  // Get API rate limit information (approximate)
  Map<String, dynamic> getRateLimitInfo() {
    return {
      'max_messages_per_second': 30,
      'max_messages_per_minute': 20,
      'max_message_length': 4096,
      'recommended_delay_between_messages': Duration(milliseconds: 1000),
    };
  }

  // Utility method to get package version
  String _getPackageVersion() {
    try {
      // This would typically come from package_info_plus
      // For now, return a placeholder or use CrashReporter.version
      return CrashReporter.version;
    } catch (e) {
      return 'unknown';
    }
  }

  void dispose() {
    _httpClient.close();
    _debugPrint('🔚 Telegram API client disposed');
  }

  // Getters for internal state (useful for debugging)
  String get botToken => _botToken;
  int get chatId => _chatId;
}
