import 'dart:io';
import 'package:flutter/foundation.dart';

class MessageBuilder {
  static String buildStartupMessage() {
    return '''
<b>🚀 App Started</b>

<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
<b>Debug</b>: ${kDebugMode ? 'YES' : 'NO'}
''';
  }

  static String buildCrashHtmlMessage({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) {
    final truncatedStack = stackTrace.toString().length > 1500
        ? '${stackTrace.toString().substring(0, 1500)}...'
        : stackTrace.toString();

    // Escape HTML characters
    final escapedError = _escapeHtml(error.toString());
    final escapedStack = _escapeHtml(truncatedStack);

    var message = '''
<b>${fatal ? '🚨 FATAL CRASH' : '⚠️ ERROR'}</b>

<b>Context</b>: ${_escapeHtml(context ?? 'Unknown')}
<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
<b>Debug</b>: ${kDebugMode ? 'YES' : 'NO'}

<b>Error</b>:
<code>$escapedError</code>

<b>Stack</b>:
<pre>$escapedStack</pre>
''';

    if (extraData != null && extraData.isNotEmpty) {
      message += '\n<b>Extra Data</b>:\n';
      extraData.forEach((key, value) {
        final escapedValue = _escapeHtml(value.toString());
        message += '• $key: <code>$escapedValue</code>\n';
      });
    }

    return message;
  }

  static String buildEventMessage({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
  }) {
    var eventMessage = '''
<b>📊 Event: ${_escapeHtml(message)}</b>

<b>Context</b>: ${_escapeHtml(context ?? 'General')}
<b>Time</b>: ${DateTime.now()}
<b>Platform</b>: ${Platform.operatingSystem}
''';

    if (extraData != null && extraData.isNotEmpty) {
      eventMessage += '\n<b>Data</b>:\n';
      extraData.forEach((key, value) {
        final escapedValue = _escapeHtml(value.toString());
        eventMessage += '• $key: <code>$escapedValue</code>\n';
      });
    }

    return eventMessage;
  }

  // HTML escaping utility
  static String _escapeHtml(String text) {
    var escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

    escaped =
        escaped.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    return escaped;
  }

  static String buildCrashPlainTextMessage({
    required Object error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) {
    final stackStr = stackTrace.toString();
    final truncatedStack = stackStr.length > 1500
        ? '${stackStr.substring(0, 1500)}...'
        : stackStr;

    final buffer = StringBuffer();

    buffer.writeln(fatal ? '🚨 FATAL CRASH' : '⚠️ ERROR');
    buffer.writeln('');

    buffer.writeln('Context: ${context ?? 'Unknown'}');
    buffer.writeln('Time: ${DateTime.now()}');

    if (!kIsWeb) {
      buffer.writeln(
          'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    }

    buffer.writeln('Debug: ${kDebugMode ? 'YES' : 'NO'}');
    buffer.writeln('');

    buffer.writeln('Error:');
    buffer.writeln(error.toString());
    buffer.writeln('');

    buffer.writeln('Stack:');
    buffer.writeln(truncatedStack);

    if (extraData != null && extraData.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Extra Data:');
      extraData.forEach((key, value) {
        buffer.writeln('- $key: $value');
      });
    }

    return buffer.toString();
  }


  static String buildCrashMarkdownMessage({
    required Object error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  }) {
    final stackStr = stackTrace.toString();
    final truncatedStack = stackStr.length > 1500
        ? '${stackStr.substring(0, 1500)}...'
        : stackStr;

    final buffer = StringBuffer();

    // title
    buffer.writeln(fatal ? '🚨 *FATAL CRASH*' : '⚠️ *ERROR*');
    buffer.writeln('');

    buffer.writeln('*Context*: ${_escapeMarkdown(context ?? 'Unknown')}');
    buffer.writeln('*Time*: ${DateTime.now()}');

    if (!kIsWeb) {
      buffer.writeln(
        '*Platform*: ${_escapeMarkdown(
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        )}',
      );
    }

    buffer.writeln('*Debug*: ${kDebugMode ? 'YES' : 'NO'}');
    buffer.writeln('');

    // error
    buffer.writeln('*Error:*');
    buffer.writeln('```');
    buffer.writeln(error.toString()); // ❗ 不 escape
    buffer.writeln('```');
    buffer.writeln('');

    // stack
    buffer.writeln('*Stack:*');
    buffer.writeln('```');
    buffer.writeln(truncatedStack); // ❗ 不 escape
    buffer.writeln('```');

    // extra
    if (extraData != null && extraData.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('*Extra Data:*');
      extraData.forEach((key, value) {
        buffer.writeln(
          '- ${_escapeMarkdown(key)}: `${_escapeMarkdown(value?.toString() ?? 'null')}`',
        );
      });
    }

    return buffer.toString();
  }

  static String _escapeMarkdown(String input) {
    return input.replaceAllMapped(
      RegExp(r'([_*`\[])'),
          (m) => '\\${m[0]}',
    );
  }


}
