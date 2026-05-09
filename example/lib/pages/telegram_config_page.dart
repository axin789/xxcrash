import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';

/// 展示当前 Telegram 旁路配置，并给出接入方法。
///
/// 这里没有做运行时动态启用——SDK 的 init 是一次性的，Telegram 配置必须在
/// `XCrashSDK.init` 的那一刻传进去。真的要运行时改，需要重启 app。
class TelegramConfigPage extends StatelessWidget {
  static const route = '/telegram';
  const TelegramConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final enabled = AppConfig.telegramEnabled;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Telegram 旁路配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: enabled
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    enabled ? Icons.check_circle : Icons.info_outline,
                    color: enabled ? theme.colorScheme.primary : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      enabled
                          ? '已启用：所有上报会并联发到 chatId ${AppConfig.tgChatId}'
                          : '未启用：需要通过 --dart-define 注入 TG_BOT_TOKEN / TG_CHAT_ID',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('运行示例', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _CodeBlock(
            '''flutter run \\
  --dart-define=TG_BOT_TOKEN=1234:ABC... \\
  --dart-define=TG_CHAT_ID=-1001234567890''',
          ),
          const SizedBox(height: 20),
          Text('配置说明', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '• Bot Token：@BotFather 发 /newbot 得到，形如 1234:ABC...\n'
            '• Chat ID：\n'
            '    - 发私聊：先给 bot 发一条消息，然后打开 '
            'https://api.telegram.org/bot<token>/getUpdates 拿里面的 chat.id\n'
            '    - 发群：把 bot 拉进群，群里发一条消息，同上，群 id 一般是负数\n'
            '    - 发频道：把 bot 设为频道管理员，chat id 写 @channelname 或 -100...\n'
            '\n'
            'Token 等同密码，严禁入库。demo 用 --dart-define 注入只是演示手段，\n'
            '生产建议走远程配置 / 运行时下发。',
          ),
          const SizedBox(height: 20),
          Text('SDK 入口示例', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _CodeBlock(
            '''XCrashSDK.init(
  sender: ...,
  userProvider: ...,
  appRunner: ...,
  telegram: const TelegramConfig(
    botToken: String.fromEnvironment('TG_BOT_TOKEN'),
    chatId: String.fromEnvironment('TG_CHAT_ID'),
  ),
);''',
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
            ),
          ),
          IconButton(
            iconSize: 18,
            tooltip: '复制',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
