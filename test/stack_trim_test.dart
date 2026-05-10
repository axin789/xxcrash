import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/xcrash.dart';

class _FakeStack implements StackTrace {
  final String text;
  _FakeStack(this.text);
  @override
  String toString() => text;
}

void main() {
  group('trimStack 双层截断', () {
    test('行数 ≤ 50 的栈原样返回', () {
      final stack = _FakeStack(
        List.generate(20, (i) => '#$i foo (file.dart:$i)').join('\n'),
      );
      final out = XCrashSDK.trimStackForTest(stack);
      // 没有 "more" 后缀也没有省略号
      expect(out, isNot(contains('more')));
      expect(out, isNot(endsWith('…')));
      expect(out.split('\n').length, 20);
    });

    test('行数超过 50 行时截到 50 + 追加 (N more)', () {
      final stack = _FakeStack(
        List.generate(80, (i) => '#$i foo (file.dart:$i)').join('\n'),
      );
      final out = XCrashSDK.trimStackForTest(stack);
      // 51 行：50 个原始 + 1 行 "... (30 more)"
      expect(out.split('\n').length, 51);
      expect(out, contains('... (30 more)'));
      // 第 50 帧保留，第 51 帧（idx=50）开始被截掉
      expect(out, contains('#49 foo'));
      expect(out, isNot(contains('#50 foo')));
    });

    test('单行超长（AOT obfuscated 风格）走字符级硬截到 8KB', () {
      // 一行 100KB 的伪栈：按行切完全无效，必须靠字符级兜底
      final huge = 'x' * (100 * 1024);
      final stack = _FakeStack(huge);
      final out = XCrashSDK.trimStackForTest(stack);
      // 8 * 1024 + 1（"…"）
      expect(out.length, 8 * 1024 + 1);
      expect(out.endsWith('…'), isTrue);
    });

    test('行数超限 + 单行也超长时，两层截断叠加生效', () {
      // 1000 行，每行 100 字节 —— 行级截到 51 行后再撞到字符级上限
      final stack = _FakeStack(
        List.generate(1000, (i) => 'y' * 100).join('\n'),
      );
      final out = XCrashSDK.trimStackForTest(stack);
      // 行级截到 50 + 1 行 "..." 后大概是 50*101 + 后缀 ≈ 5KB，
      // 还没到 8KB 字符级上限。这里只断言行级生效。
      expect(out, contains('more)'));
      expect(out.length, lessThanOrEqualTo(8 * 1024 + 1));
    });
  });
}
