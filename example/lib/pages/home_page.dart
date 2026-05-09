import 'package:flutter/material.dart';

import '../app_config.dart';
import 'crash_demo_page.dart';
import 'payload_log_page.dart';
import 'rate_limit_demo_page.dart';
import 'report_demo_page.dart';
import 'telegram_config_page.dart';
import 'video_demo_page.dart';

class HomePage extends StatelessWidget {
  static const route = '/';
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('xcrash demo')),
      body: ListView(
        children: [
          const _SectionHeader('崩溃捕获'),
          const _DemoTile(
            title: '三种崩溃入口',
            subtitle: 'FlutterError / runZonedGuarded / PlatformDispatcher',
            icon: Icons.bug_report_outlined,
            route: CrashDemoPage.route,
          ),
          const _SectionHeader('主动上报'),
          const _DemoTile(
            title: '手动 report / 面包屑 / 心跳',
            subtitle: 'reportApiError / reportBusinessError / report / leaveBreadcrumb / updateHeartbeat',
            icon: Icons.note_add_outlined,
            route: ReportDemoPage.route,
          ),
          const _DemoTile(
            title: '限频演示',
            subtitle: '同一个 key 连打 50 次，只会放行其中几条',
            icon: Icons.speed_outlined,
            route: RateLimitDemoPage.route,
          ),
          const _SectionHeader('视频'),
          const _DemoTile(
            title: 'VideoPlayerReporter',
            subtitle: '自动 playback_error / buffer_stall / first_frame_timeout + 手动 visual_glitch',
            icon: Icons.movie_outlined,
            route: VideoDemoPage.route,
          ),
          const _SectionHeader('调试 / 配置'),
          const _DemoTile(
            title: 'Sender 收到的 payload',
            subtitle: '查看 SDK 交给 sender 的 JSON',
            icon: Icons.receipt_long_outlined,
            route: PayloadLogPage.route,
          ),
          _DemoTile(
            title: 'Telegram 旁路',
            subtitle: AppConfig.telegramEnabled
                ? '已配置：chatId=${AppConfig.tgChatId}'
                : '未配置（通过 --dart-define 注入 TG_BOT_TOKEN / TG_CHAT_ID）',
            icon: Icons.send_outlined,
            route: TelegramConfigPage.route,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  const _DemoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }
}
