import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xcrash/xcrash.dart';

import 'app_config.dart';
import 'pages/crash_demo_page.dart';
import 'pages/home_page.dart';
import 'pages/payload_log_page.dart';
import 'pages/rate_limit_demo_page.dart';
import 'pages/report_demo_page.dart';
import 'pages/telegram_config_page.dart';
import 'pages/video_demo_page.dart';
import 'sender_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 把每次 sender 收到的 JSON 镜像到内存日志里，UI 可以直接看到。
  // 真实工程里这里应该是 HttpUtils.post('/system/track', data: {'content': content})。
  Future<void> demoSender(String content) async {
    SenderLog.instance.add(content);
    debugPrint('[xcrash.sender] ${content.length} chars');
  }

  XCrashSDK.init(
    appRunner: () async => runApp(const DemoApp()),
    userProvider: () => const {'uid': 'demo-user-001', 'role': 'qa'},
    sender: demoSender,
    // 这里故意把门槛调低，方便 demo 里按一两下就能看到上报。
    // 生产环境一般把 buffer_stall / DioException 设成 5~10。
    reportConfigs: const {
      'video:buffer_stall': 3,
      'video:playback_error': 1,
      'business:demo_rate_limit': 10, // 配合限频 demo：前 9 次累计，第 10 次才放行
    },
    intervalMs: 60 * 1000,
    telegram: AppConfig.telegramConfig, // 未配置 TG_BOT_TOKEN 时返回 null，自动跳过
  );
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xcrash demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      // Observer 挂上来以后，pushNamed / pop 都会自动写一条 navigation 面包屑。
      navigatorObservers: [BreadcrumbNavigatorObserver()],
      initialRoute: HomePage.route,
      routes: {
        HomePage.route: (_) => const HomePage(),
        CrashDemoPage.route: (_) => const CrashDemoPage(),
        ReportDemoPage.route: (_) => const ReportDemoPage(),
        RateLimitDemoPage.route: (_) => const RateLimitDemoPage(),
        VideoDemoPage.route: (_) => const VideoDemoPage(),
        PayloadLogPage.route: (_) => const PayloadLogPage(),
        TelegramConfigPage.route: (_) => const TelegramConfigPage(),
      },
    );
  }
}
