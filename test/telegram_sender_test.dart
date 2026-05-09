import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/src/integrations/telegram_sender.dart';

void main() {
  group('TelegramSender.buildMessage (HTML)', () {
    test('包含 severity emoji + eventType + subKey', () {
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'StateError',
        'message': 'bad state',
      });
      expect(text, contains('🚨'));
      expect(text, contains('<b>FATAL · crash</b>'));
      expect(text, contains('StateError'));
      expect(text, contains('bad state'));
    });

    test('HTML 危险字符被转义', () {
      final text = TelegramSender.buildMessage({
        'severity': 'error',
        'eventType': 'crash',
        'subKey': 'X<Y>&Z',
        'message': '',
      });
      expect(text, contains('X&lt;Y&gt;&amp;Z'));
      expect(text, isNot(contains('<Y>')));
    });

    test('error 块包含 type/message/stack', () {
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'StateError',
        'error': {
          'type': 'StateError',
          'message': 'illegal state',
          'stack': '#0 foo (main.dart:10)\n#1 bar',
        },
      });
      expect(text, contains('StateError: illegal state'));
      expect(text, contains('<pre>'));
      expect(text, contains('main.dart:10'));
    });

    test('breadcrumbs 最多 10 条，超出显示 "+N more"', () {
      final crumbs = List.generate(15, (i) => {
            'category': 'nav',
            'message': 'route_$i',
          });
      final text = TelegramSender.buildMessage({
        'severity': 'warning',
        'eventType': 'video',
        'subKey': 'buffer_stall',
        'breadcrumbs': crumbs,
      });
      expect(text, contains('[nav] route_0'));
      expect(text, contains('[nav] route_9'));
      expect(text, isNot(contains('[nav] route_10')));
      expect(text, contains('+5 more'));
    });

    test('超过 maxLength 被截断并加省略号', () {
      final longStack = List.generate(1000, (i) => '#$i some.dart:1').join('\n');
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'X',
        'error': {'type': 'X', 'message': 'y', 'stack': longStack},
      }, maxLength: 500);
      // 留了 32 字节余量给闭合标签 + 省略号；结果可能略短于 500
      expect(text.length, lessThanOrEqualTo(500));
      expect(text, contains('…'));
    });

    test('HTML 截断不会留下半开标签或未闭合 tag（Telegram 否则 400）', () {
      // 构造一个 stack 极长的 payload，迫使截断点落在 <pre>...</pre> 中间
      final longStack = List.generate(1000, (i) => '#$i some.dart:1').join('\n');
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'X',
        'error': {'type': 'X', 'message': 'y', 'stack': longStack},
      }, maxLength: 500);

      // 1. 不能有"开了没关"的 tag
      final opens = '<b>'.allMatches(text).length +
          '<code>'.allMatches(text).length +
          '<pre>'.allMatches(text).length;
      final closes = '</b>'.allMatches(text).length +
          '</code>'.allMatches(text).length +
          '</pre>'.allMatches(text).length;
      expect(opens, closes, reason: 'unbalanced HTML tags after truncate');

      // 2. 不能有半开的 `<xxx`（最后一个 < 必须在最后一个 > 之前）
      final lastLt = text.lastIndexOf('<');
      final lastGt = text.lastIndexOf('>');
      expect(lastLt <= lastGt, isTrue, reason: 'dangling "<" tag start');
    });

    test('plain 模式下截断仍然只是简单 substring + …', () {
      final raw = 'a' * 1000;
      final text = TelegramSender.buildMessage({
        'severity': 'info',
        'eventType': 'business',
        'subKey': 'k',
        'message': raw,
      }, parseMode: null, maxLength: 100);
      expect(text.length, lessThanOrEqualTo(101));
      expect(text.endsWith('…'), isTrue);
    });

    test('null / 缺失字段不报错', () {
      final text = TelegramSender.buildMessage(const <String, dynamic>{});
      expect(text, contains('ℹ️'));
      expect(text, contains('<b>INFO · </b>'));
    });
  });

  group('TelegramSender.buildMessage (plain)', () {
    test('parseMode=null 时不产生 HTML 标签', () {
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'X<Y>&Z',
      }, parseMode: null);
      expect(text, isNot(contains('<b>')));
      expect(text, contains('X<Y>&Z')); // 纯文本模式不转义
    });
  });

  group('TelegramSender.buildMessage (MarkdownV2)', () {
    test('保留字符（_ * . - 等）都被反斜杠转义', () {
      final text = TelegramSender.buildMessage({
        'severity': 'warning',
        'eventType': 'video',
        'subKey': 'buffer_stall', // 含下划线 —— 不转义会让 V2 解析失败
        'message': 'a.b-c (d)',
        'app': {'version': '1.2.3', 'buildNumber': '45'},
      }, parseMode: 'MarkdownV2');

      // subKey 里的 _ 必须被转义
      expect(text, contains(r'buffer\_stall'));
      // message 里的 . - ( ) 都是 V2 保留字
      expect(text, contains(r'a\.b\-c \(d\)'));
      // app 字段的 . + 也得转义
      expect(text, contains(r'1\.2\.3\+45'));
      // 加粗包裹用单星号且没有被多余转义吃掉
      expect(text, contains('*subKey:*'));
    });

    test('error stack 里的反引号 / 反斜杠在 ``` 块内被转义', () {
      final text = TelegramSender.buildMessage({
        'severity': 'fatal',
        'eventType': 'crash',
        'subKey': 'X',
        'error': {
          'type': 'X',
          'message': 'has ` and \\ chars',
          'stack': 'line with ` and \\ here',
        },
      }, parseMode: 'MarkdownV2');

      expect(text, contains('```\n'));
      expect(text, contains(r'\`'));
      expect(text, contains(r'\\'));
    });
  });

  group('TelegramSender.buildMessage (Markdown legacy)', () {
    test('subKey 里的 _ 也会被转义（避免 Telegram 400）', () {
      final text = TelegramSender.buildMessage({
        'severity': 'warning',
        'eventType': 'video',
        'subKey': 'buffer_stall',
      }, parseMode: 'Markdown');

      expect(text, contains(r'buffer\_stall'));
    });
  });
}
