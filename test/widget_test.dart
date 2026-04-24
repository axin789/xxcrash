import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/crash_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CrashReporter Widget Tests', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Initialize with all services disabled by default
      CrashReporter.initialize(
        telegramConfig: TelegramConfig(
          botToken: 'test_bot_token',
          chatId: 123456789,
        ),
        notificationConfig: NotificationConfig(
          enableTelegram: false, // Disable for tests
          enableSlack: false,
          enableDiscord: false,
          enableWebhook: false,
          sendCrashReports: true,
          sendEvents: true,
          sendStartupEvents: false,
        ),
        showDebugPrint: false, // Disable debug print for cleaner test output
      );
    });

    tearDown(() {
      CrashReporter.dispose();
    });

    testWidgets('Plugin can be used in widget tree without errors',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // This should not throw even if services are disabled
                      CrashReporter.sendEvent(
                        message: 'Button pressed',
                        context: 'Widget Test',
                      );
                    },
                    child: Text('Test Button'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Tap the button and ensure no errors
      await tester.tap(find.text('Test Button'));
      await tester.pump();

      // Verify the button is still there (no crashes)
      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('Crash reporting works in widget context',
        (WidgetTester tester) async {
      bool crashReported = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  try {
                    throw Exception('Widget test exception');
                  } catch (e, stack) {
                    await CrashReporter.reportCrash(
                      error: e,
                      stackTrace: stack,
                      context: 'Widget Test',
                    );
                    crashReported = true; // This should execute
                  }
                },
                child: Text('Cause Crash'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cause Crash'));
      await tester.pumpAndSettle(); // Wait for async operations

      expect(crashReported, isTrue);
    });

    testWidgets('Multiple rapid events dont cause issues',
        (WidgetTester tester) async {
      int eventCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  for (int i = 0; i < 5; i++) {
                    await CrashReporter.sendEvent(
                      message: 'Rapid event $i',
                    );
                    eventCount++;
                  }
                },
                child: Text('Rapid Events'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Rapid Events'));
      await tester.pumpAndSettle(); // Wait for all events

      expect(eventCount, 5);
    });

    testWidgets('Plugin works with async widget operations',
        (WidgetTester tester) async {
      final results = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      results.add('start');

                      await Future.delayed(Duration(milliseconds: 100));

                      await CrashReporter.sendEvent(
                        message: 'Async event',
                      );

                      results.add('end');
                    },
                    child: Text('Async Test'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Async Test'));
      await tester.pumpAndSettle(Duration(milliseconds: 200));

      expect(results, contains('start'));
      expect(results, contains('end'));
    });

    testWidgets('Local storage works in widget context',
        (WidgetTester tester) async {
      int? finalCrashCount;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await CrashReporter.reportCrash(
                    error: 'Widget storage test',
                    stackTrace: StackTrace.current,
                  );

                  finalCrashCount = await CrashReporter.getCrashCount();
                },
                child: Text('Test Storage'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test Storage'));
      await tester.pumpAndSettle();

      expect(finalCrashCount, 1);
    });

    testWidgets('Configuration updates work in widget context',
        (WidgetTester tester) async {
      bool configUpdated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  CrashReporter.updateNotificationConfig(
                    NotificationConfig(
                      enableTelegram: true,
                      sendCrashReports: true,
                      sendEvents: true,
                    ),
                  );
                  configUpdated = true;
                },
                child: Text('Update Config'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Update Config'));
      await tester.pump();

      expect(configUpdated, isTrue);
    });

    testWidgets('Connection testing works in widget context',
        (WidgetTester tester) async {
      bool testStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  testStarted = true;
                  // This should complete without errors (services are disabled)
                  await CrashReporter.testAllConnections();
                },
                child: Text('Test Connections'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test Connections'));
      await tester.pumpAndSettle();

      expect(testStarted, isTrue);
    });

    testWidgets('Status checking works in widget context',
        (WidgetTester tester) async {
      Map<String, bool>? notifierStatus;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  notifierStatus = CrashReporter.getNotifierStatus();
                },
                child: Text('Check Status'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Check Status'));
      await tester.pump();

      expect(notifierStatus, isNotNull);
      expect(notifierStatus!['telegram'], isFalse); // Disabled in setup
      expect(notifierStatus!['slack'], isFalse);
      expect(notifierStatus!['discord'], isFalse);
      expect(notifierStatus!['webhook'], isFalse);
    });

    testWidgets('App startup notification works in widget context',
        (WidgetTester tester) async {
      bool startupSent = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await CrashReporter.sendAppStartup();
                  startupSent = true;
                },
                child: Text('Send Startup'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Send Startup'));
      await tester.pumpAndSettle();

      expect(startupSent, isTrue);
    });

    testWidgets('Clear logs works in widget context',
        (WidgetTester tester) async {
      int? crashCountAfterClear;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      // First report a crash
                      await CrashReporter.reportCrash(
                        error: 'Test error',
                        stackTrace: StackTrace.current,
                      );

                      // Then clear logs
                      await CrashReporter.clearLocalCrashLogs();

                      // Check count after clear
                      crashCountAfterClear =
                          await CrashReporter.getCrashCount();
                    },
                    child: Text('Clear Logs'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Clear Logs'));
      await tester.pumpAndSettle();

      expect(crashCountAfterClear, 0);
    });
  });
}
