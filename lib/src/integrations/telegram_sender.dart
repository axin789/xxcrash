import 'dart:convert';

import 'package:flutter/foundation.dart';

// 条件导入：native 用 HttpClient 真发 HTTP；web 用空实现（不碰 dart:io，能编译过）。
import '_telegram_transport_stub.dart'
    if (dart.library.io) '_telegram_transport_io.dart' as transport;

/// Telegram bot 上报配置。
///
/// [botToken] 从 `@BotFather` 创建 bot 后获得（形如 `1234:ABC...`）。**视同密码，别入库。**
/// [chatId]   接收消息的会话 id。私聊/群/频道的 id 通过
///            `https://api.telegram.org/bot<token>/getUpdates` 获取；频道也可填 `@channelname`。
/// [parseMode] `HTML` / `Markdown` / `MarkdownV2` / `null`（纯文本）。默认 HTML。
///
/// 注：Flutter web 上 Telegram 通道是空实现（no-op），SDK 只保证**能编译**。
/// 见 `_telegram_transport_stub.dart`。
class TelegramConfig {
  final String botToken;
  final String chatId;
  final String? parseMode;
  final bool disableWebPagePreview;
  final bool disableNotification;
  final Duration timeout;

  const TelegramConfig({
    required this.botToken,
    required this.chatId,
    this.parseMode = 'HTML',
    this.disableWebPagePreview = true,
    this.disableNotification = false,
    this.timeout = const Duration(seconds: 10),
  });
}

/// 把 XCrash 的 payload 渲染成 Telegram 消息并 POST 到 Bot API。
///
/// 内部类。SDK 在 `init()` 接到 [TelegramConfig] 后自动实例化，
/// 消费方不需要直接用它。
class TelegramSender {
  final TelegramConfig config;

  TelegramSender(this.config);

  /// 发送一条上报 payload。任何异常都被吞掉（与主 sender 解耦）。
  Future<void> send(Map<String, dynamic> payload) async {
    final text = buildMessage(payload, parseMode: config.parseMode);
    final body = jsonEncode({
      'chat_id': config.chatId,
      'text': text,
      if (config.parseMode != null) 'parse_mode': config.parseMode,
      'disable_web_page_preview': config.disableWebPagePreview,
      'disable_notification': config.disableNotification,
    });

    final uri = Uri.parse(
      'https://api.telegram.org/bot${config.botToken}/sendMessage',
    );

    await transport.postTelegram(
      uri: uri,
      body: body,
      timeout: config.timeout,
      botToken: config.botToken,
    );
  }

  // ---------- 消息格式化（纯函数，易测试） ----------

  /// 把 payload map 渲染成 Telegram 可显示的文本。
  /// 遵守 Telegram 4096 字符上限，超出会截断并追加 `…`。
  @visibleForTesting
  static String buildMessage(
    Map<String, dynamic> p, {
    String? parseMode = 'HTML',
    int maxLength = 4000, // 留一点余量，实际上限是 4096
  }) {
    // 选转义函数：HTML / MarkdownV2 / Markdown / 其它（纯文本不转义）。
    // 不转义 Markdown 的话，subKey 含 `_`（如 `buffer_stall`、`first_frame_timeout`）
    // 就会让 Telegram 返回 400 can't parse entities，整条消息丢。
    final isHtml = parseMode == 'HTML';
    final isMdV2 = parseMode == 'MarkdownV2';
    final isMd = parseMode == 'Markdown';

    String esc(String s) {
      if (isHtml) return _escHtml(s);
      if (isMdV2) return _escMdV2(s);
      if (isMd) return _escMd(s);
      return s;
    }

    String b(String s) {
      if (isHtml) return '<b>${_escHtml(s)}</b>';
      if (isMdV2) return '*${_escMdV2(s)}*';
      if (isMd) return '*${_escMd(s)}*';
      return '*$s*';
    }

    String code(String s) {
      if (isHtml) return '<code>${_escHtml(s)}</code>';
      // inline code 块内 ` 和 \ 必须 escape（V2 / legacy 都一样）。
      if (isMdV2 || isMd) return '`${_escCodeContent(s)}`';
      return '`$s`';
    }

    String pre(String s) {
      if (isHtml) return '<pre>${_escHtml(s)}</pre>';
      // pre 块（``` fence）内同样只需 escape ` 和 \。
      if (isMdV2 || isMd) return '```\n${_escCodeContent(s)}\n```';
      return '```\n$s\n```';
    }

    final severity = (p['severity'] ?? 'info').toString();
    final eventType = (p['eventType'] ?? '').toString();
    final subKey = (p['subKey'] ?? '').toString();
    final message = (p['message'] ?? '').toString();

    final emoji = _emojiFor(severity);

    final buf = StringBuffer()
      ..writeln('$emoji ${b('${severity.toUpperCase()} · $eventType')}')
      ..writeln('${b('subKey:')} ${esc(subKey)}');

    void kv(String key, Object? value) {
      if (value == null) return;
      final s = value.toString();
      if (s.isEmpty) return;
      buf.writeln('${b('$key:')} ${esc(s)}');
    }

    kv('message', message);

    // session / app / device / user —— 只展示少量关键字段，完整信息在 JSON 里
    final session = p['session'] as Map?;
    if (session != null) {
      final id = (session['id'] ?? '').toString();
      final dur = session['durationMs'];
      kv('session', dur == null ? id : '${_short(id)} (${dur}ms)');
    }

    final app = p['app'] as Map?;
    if (app != null) {
      final v = app['version'] ?? app['appVersion'];
      final b1 = app['buildNumber'] ?? app['build'];
      kv('app', '${v ?? ''}${b1 != null ? '+$b1' : ''}'.trim());
    }

    final device = p['device'] as Map?;
    if (device != null) {
      final plat = device['platform'] ?? '';
      final model = device['model'] ?? device['name'] ?? '';
      final ver = device['systemVersion'] ?? device['release'] ?? '';
      kv('device', [plat, model, ver].where((x) => '$x'.isNotEmpty).join(' '));
    }

    final user = p['user'] as Map?;
    if (user != null) {
      kv('user', user['uid'] ?? user['id'] ?? user.toString());
    }

    // context
    kv('context', p['context']);

    // error + stack
    final error = p['error'] as Map?;
    if (error != null) {
      buf.writeln();
      buf.writeln(b('error:'));
      buf.writeln(code('${error['type']}: ${error['message']}'));
      final stack = error['stack']?.toString();
      if (stack != null && stack.isNotEmpty) {
        buf.writeln(pre(stack));
      }
    }

    // breadcrumbs (最近 10 条)
    final crumbs = (p['breadcrumbs'] as List?)?.cast<Map>() ?? const [];
    if (crumbs.isNotEmpty) {
      buf.writeln();
      buf.writeln(b('breadcrumbs:'));
      for (final c in crumbs.take(10)) {
        final cat = c['category'] ?? '';
        final msg = c['message'] ?? '';
        buf.writeln('• ${esc('[$cat] $msg')}');
      }
      if (crumbs.length > 10) {
        buf.writeln('… +${crumbs.length - 10} more');
      }
    }

    // 被压制的次数
    final suppressed = p['suppressedCount'];
    if (suppressed is int && suppressed > 0) {
      buf.writeln();
      buf.writeln('${b('suppressed:')} $suppressed');
    }

    return _truncateSafe(buf.toString(), maxLength, parseMode: parseMode);
  }

  /// 按 [maxLength] 截断，但避免在 HTML 标签或 entity 中间切断 ——
  /// 截到一半的 `<pre`、`&am` 会让 Telegram 整条消息以 400 拒收。
  ///
  /// 算法：
  /// 1. 留出尾部余量（"…" + 可能要补的闭合标签）；
  /// 2. 若结尾在开标签内（最后一个 `<` 在最后一个 `>` 之后），裁掉这段半开 tag；
  /// 3. 若结尾在 HTML entity 内（最后一个 `&` 在最后一个 `;` 之后且距离很近），裁掉这段半开 entity；
  /// 4. 扫一遍 tag 栈，把没闭合的 tag 按后开先关补齐。
  static String _truncateSafe(
    String text,
    int maxLength, {
    String? parseMode,
  }) {
    if (text.length <= maxLength) return text;

    final isHtml = parseMode == 'HTML';
    if (!isHtml) {
      return '${text.substring(0, maxLength)}…';
    }

    // 留足余量给省略号和可能补回来的多重闭合标签
    const reserved = 32;
    final cutAt = (maxLength - reserved).clamp(0, text.length);
    var cut = text.substring(0, cutAt);

    // 截到 `<...` 半开 tag 内：删掉这一段半开
    final lastLt = cut.lastIndexOf('<');
    final lastGt = cut.lastIndexOf('>');
    if (lastLt > lastGt) {
      cut = cut.substring(0, lastLt);
    }

    // 截到 `&xxx` 半开 entity 内：HTML entity 一般 ≤ 8 字符，超过这个距离
    // 大概率是 message 里出现的裸 `&`（已经被 `_escHtml` 转过），不动它。
    final lastAmp = cut.lastIndexOf('&');
    final lastSemi = cut.lastIndexOf(';');
    if (lastAmp > lastSemi && cut.length - lastAmp <= 8) {
      cut = cut.substring(0, lastAmp);
    }

    // 扫 tag 栈：开 tag 入栈，匹配的闭 tag 出栈；剩下的需要在尾部补齐。
    final stack = <String>[];
    final tagRe = RegExp(r'<(/?)(\w+)>');
    for (final m in tagRe.allMatches(cut)) {
      final close = m.group(1) == '/';
      final tag = m.group(2)!;
      if (close) {
        if (stack.isNotEmpty && stack.last == tag) stack.removeLast();
      } else {
        stack.add(tag);
      }
    }
    final tail = stack.reversed.map((t) => '</$t>').join();
    return '$cut…$tail';
  }

  // ---------- 渲染工具 ----------

  static String _emojiFor(String severity) {
    switch (severity) {
      case 'fatal':
        return '🚨';
      case 'error':
        return '❌';
      case 'warning':
        return '⚠️';
      default:
        return 'ℹ️';
    }
  }

  static String _escHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // MarkdownV2 保留字（来自 Telegram 文档）：_*[]()~`>#+-=|{}.!\
  // 任意一个未转义都会让整条消息解析失败。
  static final RegExp _mdV2Reserved = RegExp(r'[_*\[\]()~`>#+\-=|{}.!\\]');
  static String _escMdV2(String s) =>
      s.replaceAllMapped(_mdV2Reserved, (m) => '\\${m[0]}');

  // Legacy Markdown 保留字（更宽松，仅 _*`[\）。
  static final RegExp _mdReserved = RegExp(r'[_*`\[\\]');
  static String _escMd(String s) =>
      s.replaceAllMapped(_mdReserved, (m) => '\\${m[0]}');

  // code/pre 块内部：先 escape \，再 escape `（顺序很重要，否则 \\ 会再被转一次）。
  static String _escCodeContent(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('`', r'\`');

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}
