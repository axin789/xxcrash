import 'package:xcrash/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import '../telegram_api.dart';
import '../message_builder.dart';
import '../models/notification_config.dart';
import 'base_notifier.dart';

class TelegramNotifier extends BaseNotifier {
  final TelegramConfig config;
  late TelegramApi _telegramApi;

  TelegramNotifier({
    required this.config,
    required Function(String) debugPrint,
  }) : super(debugPrint: debugPrint, notifierName: 'TelegramNotifier') {
    _telegramApi = TelegramApi(
      botToken: config.botToken,
      chatId: config.chatId,
      debugPrint: debugPrint,
    );
  }

  @override
  Future<void> sendCrashReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final message;
      if(config.parseMode == ParseMode.markdown.value){
         message = MessageBuilder.buildCrashMarkdownMessage(
          error: error,
          stackTrace: stackTrace,
          context: context,
          fatal: fatal,
          extraData: extraData,
        );
      }else{
         message = MessageBuilder.buildCrashHtmlMessage(
          error: error,
          stackTrace: stackTrace,
          context: context,
          fatal: fatal,
          extraData: extraData,
        );
      }
      await _telegramApi.sendMessage(
        // "test---${config.parseMode}\n$message",
        message,
        parseMode: config.parseMode,
        disableWebPagePreview: config.disableWebPagePreview,
        disableNotification: config.disableNotification,
      );

      log('✅ Crash report sent successfully');
    } catch (e) {
      log('❌ Failed to send crash report: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendEvent({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final fullMessage = MessageBuilder.buildEventMessage(
        message: message,
        context: context,
        extraData: extraData,
      );

      await _telegramApi.sendMessage(
        fullMessage,
        parseMode: config.parseMode,
        disableWebPagePreview: config.disableWebPagePreview,
        disableNotification: config.disableNotification,
      );

      log('✅ Event sent successfully');
    } catch (e) {
      log('❌ Failed to send event: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendAppStartup() async {
    try {
      final message = MessageBuilder.buildStartupMessage();

      await _telegramApi.sendMessage(
        message,
        parseMode: config.parseMode,
        disableWebPagePreview: config.disableWebPagePreview,
        disableNotification: config.disableNotification,
      );

      log('✅ Startup notification sent successfully');
    } catch (e) {
      log('❌ Failed to send startup notification: $e');
      rethrow;
    }
  }

  @override
  Future<void> testConnection() async {
    try {
      await _telegramApi.sendMessage(
        '<b>🧪 Test Connection</b>\n\nThis is a test message from Flutter Crash Reporter v${CrashReporter.version}',
        parseMode: config.parseMode,
        disableWebPagePreview: config.disableWebPagePreview,
        disableNotification: config.disableNotification,
      );
      log('✅ Telegram connection test passed!');
    } catch (e) {
      log('❌ Telegram connection test failed: $e');
      rethrow;
    }
  }

  // Method to update configuration
  void updateConfig(TelegramConfig newConfig) {
    _telegramApi.dispose();
    _telegramApi = TelegramApi(
      botToken: newConfig.botToken,
      chatId: newConfig.chatId,
      debugPrint: debugPrint,
    );
    log('📋 Telegram configuration updated');
  }

  // Get current configuration
  TelegramConfig get currentConfig => config;

  @override
  void dispose() {
    _telegramApi.dispose();
    log('🔚 Telegram notifier disposed');
  }
}
