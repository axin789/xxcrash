import 'package:flutter_test/flutter_test.dart';
// Limiter is not exported in the public barrel on purpose — import directly.
import 'package:xcrash/src/report_limiter.dart';

void main() {
  setUp(() {
    ErrorReportLimiter.clear();
    ErrorReportLimiter.setReportEnabled(true);
    ErrorReportLimiter.setIntervalMs(60 * 1000);
  });

  test('reportEnabled=false 时一律拒绝', () {
    ErrorReportLimiter.setReportEnabled(false);
    expect(ErrorReportLimiter.shouldReport('any'), isNull);
  });

  test('首次命中即放行（threshold=0）', () {
    final r = ErrorReportLimiter.shouldReport('video:playback_error');
    expect(r, isNotNull);
    expect(r, 0);
  });

  test('起步阈值：未达到前全部压制', () {
    ErrorReportLimiter.setStartReportThresholds({'video:buffer_stall': 3});

    // 1, 2 次都被压
    expect(ErrorReportLimiter.shouldReport('video:buffer_stall'), isNull);
    expect(ErrorReportLimiter.shouldReport('video:buffer_stall'), isNull);
    // 第 3 次刚达到阈值，放行
    final r = ErrorReportLimiter.shouldReport('video:buffer_stall');
    expect(r, isNotNull);
    // 此时应已累积 2 次被压的 suppressedCount
    expect(r, 2);
  });

  test('threshold 回落 errorType（兼容旧配置）', () {
    // 用 FormatException 作为测试目标：它的 runtimeType.toString() == "FormatException"
    ErrorReportLimiter.setStartReportThresholds({'FormatException': 2});

    final error = const FormatException('boom');
    // 传入的 key 与 config key 不同，但 errorType 命中
    expect(
        ErrorReportLimiter.shouldReport('crash:FormatException', error: error),
        isNull);
    final r = ErrorReportLimiter.shouldReport('crash:FormatException',
        error: error);
    expect(r, isNotNull);
  });

  test('时间窗口：放行后 interval 内只记不报', () {
    ErrorReportLimiter.setIntervalMs(10 * 1000);
    // 第一次放行
    expect(ErrorReportLimiter.shouldReport('api:/foo:500'), isNotNull);
    // 紧接着 4 次都被压
    for (var i = 0; i < 4; i++) {
      expect(ErrorReportLimiter.shouldReport('api:/foo:500'), isNull);
    }
    expect(ErrorReportLimiter.suppressedCount('api:/foo:500'), 4);
  });

  test('takeSuppressedContexts 返回并清空', () {
    ErrorReportLimiter.setIntervalMs(10 * 1000);
    ErrorReportLimiter.shouldReport('x', context: '/a'); // 首次放行
    ErrorReportLimiter.shouldReport('x', context: '/b'); // 被压
    ErrorReportLimiter.shouldReport('x', context: '/c'); // 被压

    final taken = ErrorReportLimiter.takeSuppressedContexts('x');
    expect(taken.toSet(), {'/b', '/c'});
    // 二次取空
    expect(ErrorReportLimiter.takeSuppressedContexts('x'), isEmpty);
  });

  test('suppressedContexts 保持插入顺序并允许重复', () {
    ErrorReportLimiter.setIntervalMs(10 * 1000);
    ErrorReportLimiter.shouldReport('x', context: '/a'); // 首次放行
    ErrorReportLimiter.shouldReport('x', context: '/dup'); // 被压
    ErrorReportLimiter.shouldReport('x', context: '/dup'); // 被压（重复）
    ErrorReportLimiter.shouldReport('x', context: '/other'); // 被压

    final taken = ErrorReportLimiter.takeSuppressedContexts('x');
    expect(taken, ['/dup', '/dup', '/other']); // 顺序保留，重复也保留
  });

  test('keyOf 拼接规范', () {
    expect(ErrorReportLimiter.keyOf('video', 'buffer_stall'),
        'video:buffer_stall');
  });

  test('key 数量超出上限时按 FIFO 淘汰最早的', () {
    // 假设上限 500。灌 500 个不同 key，把它们都插入；
    // 第 501 个新 key 来的时候应该踢掉最早那个。
    for (var i = 0; i < 500; i++) {
      ErrorReportLimiter.shouldReport('k$i');
    }
    // 最早的 k0 现在还在，再命中它一次，之前的 _totalHits 应该累加到 2
    ErrorReportLimiter.shouldReport('k0');

    // 插入一个全新 key 触发淘汰：最老的应该是 k1（因为 k0 刚被刷新插入顺序到最末？）
    // 注意：我们的实现里 `_totalHits[key] = ...` 对已存在 key 不重排序
    // （只有首次插入才算"最早"）。所以 k0 还是最早的，会被淘汰。
    ErrorReportLimiter.shouldReport('new_key');

    // k0 应已被淘汰：它的计数应该归零重来
    expect(ErrorReportLimiter.suppressedCount('k0'), 0);
  });
}
