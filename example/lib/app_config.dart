import 'package:xcrash/xcrash.dart';

/// 构建期注入的运行配置。
///
/// Telegram Bot Token / Chat ID 通过 `--dart-define` 传进来，不入库：
///
/// ```
/// flutter run \
///   --dart-define=TG_BOT_TOKEN=1234:ABC... \
///   --dart-define=TG_CHAT_ID=-1001234567890
/// ```
///
/// 两个都没配时 [telegramConfig] 返回 null，SDK 自动跳过 Telegram 旁路。
class AppConfig {
  AppConfig._();

  static const String tgBotToken = String.fromEnvironment('TG_BOT_TOKEN');
  static const String tgChatId = String.fromEnvironment('TG_CHAT_ID');

  static bool get telegramEnabled =>
      tgBotToken.isNotEmpty && tgChatId.isNotEmpty;

  static TelegramConfig? get telegramConfig {
    if (!telegramEnabled) return null;
    return const TelegramConfig(
      botToken: tgBotToken,
      chatId: tgChatId,
      parseMode: 'HTML',
      disableWebPagePreview: true,
      disableNotification: false,
    );
  }
}
