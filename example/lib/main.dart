import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:crash_reporter/crash_reporter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with your credentials
  CrashReporter.initialize(
    showDebugPrint: true,

    // Telegram
    telegramConfig: TelegramConfig(
      botToken: '123456:XXXXXX',
      chatId: -123,
      parseMode: 'HTML',
      disableWebPagePreview: true,
      disableNotification: false,
    ),

    // Slack
    slackConfig: SlackConfig(
      webhookUrl: 'https://hooks.slack.com/services/XXX/XXX/XXX',
    ),

    // Discord
    discordConfig: DiscordConfig(
      webhookUrl: 'https://discord.com/api/webhooks/XXX/XXX',
      username: '🚨 Crash Reporter',
      avatarUrl: 'https://randomuser.me/api/portraits/lego/8.jpg',
    ),

    // Webhook
    webhookConfig: WebhookConfig(
      url: 'http://example.com/api/webhook/test',
      headers: {'Authorization': 'Bearer your_token'},
    ),

    // Configuration - ENABLE the services you want
    notificationConfig: NotificationConfig(
      enableTelegram: true,
      enableSlack: true,
      enableDiscord: true,
      enableWebhook: true,
      sendCrashReports: true,
      sendEvents: true,
      sendStartupEvents: true,
    ),
  );

  // Send startup notification
  CrashReporter.sendAppStartup();

  // Catch Flutter UI framework errors
  FlutterError.onError = (details) {
    CrashReporter.reportCrash(
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      context: 'Flutter UI Error: ${details.library}',
      fatal: true,
      extraData: {
        'library': details.library,
        'stackFiltered': details.stackFilter,
      },
    );
  };

  // Catch unhandled Dart runtime errors
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporter.reportCrash(
      error: error,
      stackTrace: stack,
      context: 'Dart Runtime Error',
      fatal: true,
    );
    return true; // Keep app running
  };

  // Optional: Catch errors in the widget tree
  ErrorWidget.builder = (errorDetails) {
    CrashReporter.reportCrash(
      error: errorDetails.exception,
      stackTrace: errorDetails.stack!,
      context: 'Error Widget',
      fatal: false,
    );
    return ErrorWidget(errorDetails.exception);
  };

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crash Reporter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  @override
  _DemoPageState createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Crash Reporter Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                try {
                  throw Exception('Test exception from demo app');
                } catch (e, stack) {
                  CrashReporter.reportCrash(
                    error: e,
                    stackTrace: stack,
                    context: 'Demo Button',
                  );
                }
              },
              child: Text('Test Crash Report'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                CrashReporter.sendEvent(
                  message: 'User pressed event button',
                  context: 'Demo Screen',
                  extraData: {'button': 'event_test', 'time': DateTime.now()},
                );
              },
              child: Text('Send Custom Event'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await CrashReporter.testAllConnections();
              },
              child: Text('Test All Connections'),
            ),
          ],
        ),
      ),
    );
  }
}
