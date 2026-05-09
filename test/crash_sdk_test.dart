import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcrash/src/crash_persistence.dart';
import 'package:xcrash/src/report_limiter.dart';
import 'package:xcrash/xcrash.dart';

void main() {
  late List<String> captured;
  late ContentSender captureSender;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    captured = <String>[];
    captureSender = (content) async => captured.add(content);

    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: captureSender,
      userProvider: () => {'uid': 'u1'},
      appData: {'version': '9.9.9'},
      deviceData: {'platform': 'test', 'model': 'testbench'},
    );
  });

  tearDown(XCrashSDK.debugReset);

  Map<String, dynamic> _decode(String s) =>
      jsonDecode(s) as Map<String, dynamic>;

  test('report 调用 sender 一次并输出 JSON', () async {
    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'payment_failed',
      severity: Severity.error,
      message: '支付失败',
      data: {'orderId': 'o1'},
    );

    expect(captured.length, 1);
    final p = _decode(captured.single);
    expect(p['eventType'], 'business');
    expect(p['subKey'], 'payment_failed');
    expect(p['severity'], 'error');
    expect(p['message'], '支付失败');
    expect(p['data'], {'orderId': 'o1'});
    expect(p['user'], {'uid': 'u1'});
    expect(p['app'], {'version': '9.9.9'});
    expect(p['device']['platform'], 'test');
    expect(p['session']['id'], isA<String>());
    expect(p['breadcrumbs'], isA<List>());
  });

  test('error + stack 被序列化进 payload.error', () async {
    try {
      throw StateError('bad state');
    } catch (e, s) {
      await XCrashSDK.report(
        type: EventType.crash,
        subKey: e.runtimeType.toString(),
        severity: Severity.fatal,
        message: e.toString(),
        error: e,
        stack: s,
      );
    }
    final p = _decode(captured.single);
    expect(p['error']['type'], 'StateError');
    expect(p['error']['message'], contains('bad state'));
    expect(p['error']['stack'], isA<String>());
  });

  test('被忽略的异常不触发 sender', () async {
    final ignored =
        StateError('Looking up a deactivated widget ancestor is unsafe.');
    await XCrashSDK.report(
      type: EventType.crash,
      subKey: 'StateError',
      severity: Severity.fatal,
      message: ignored.toString(),
      error: ignored,
      stack: StackTrace.current,
    );
    expect(captured, isEmpty);
  });

  test('sender 抛异常被吞掉，不影响调用者', () async {
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: (_) async => throw Exception('network down'),
      userProvider: () => null,
    );

    // 不应 rethrow
    await XCrashSDK.report(
      type: EventType.api,
      subKey: '/foo:500',
      severity: Severity.warning,
      message: 'oops',
    );
    // 没有 captured 可断言，能走到这里就够了
    expect(true, isTrue);
  });

  test('leaveBreadcrumb 在上报时随 payload 一起发出', () async {
    XCrashSDK.leaveBreadcrumb(category: 'custom', message: 'clicked A');
    XCrashSDK.leaveBreadcrumb(category: 'custom', message: 'clicked B');

    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'scene',
      severity: Severity.info,
      message: 'hi',
    );
    final p = _decode(captured.single);
    final crumbs = (p['breadcrumbs'] as List).cast<Map>();
    // 除了手动加的两条，report 结束时 SDK 也会把自己写成一条，所以 >= 2
    expect(crumbs.length, greaterThanOrEqualTo(2));
    expect(crumbs.first['message'], 'clicked A');
  });

  test('限频生效：相同 key 在间隔内不重复上报', () async {
    // 先发一条，把 lastReportTime 占住
    await XCrashSDK.report(
      type: EventType.api,
      subKey: '/feed:500',
      severity: Severity.warning,
      message: 'a',
    );
    // 再发一条相同 key 的，应被压制
    await XCrashSDK.report(
      type: EventType.api,
      subKey: '/feed:500',
      severity: Severity.warning,
      message: 'b',
    );
    expect(captured.length, 1);
    final p = _decode(captured.single);
    expect(p['message'], 'a');
  });

  test('起步阈值：达到前都不上报', () async {
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: captureSender);
    ErrorReportLimiter.setStartReportThresholds({'video:buffer_stall': 3});

    for (var i = 0; i < 2; i++) {
      await XCrashSDK.reportVideoError(
        subKey: 'buffer_stall',
        videoUrl: 'http://foo/a.mp4',
      );
    }
    expect(captured, isEmpty);

    await XCrashSDK.reportVideoError(
      subKey: 'buffer_stall',
      videoUrl: 'http://foo/a.mp4',
    );
    expect(captured.length, 1);
  });

  test('limiterKey 与 ErrorReportLimiter.keyOf 等价', () {
    expect(
      XCrashSDK.limiterKey(EventType.video, 'buffer_stall'),
      'video:buffer_stall',
    );
    expect(
      XCrashSDK.limiterKey(EventType.business, 'login_risk'),
      ErrorReportLimiter.keyOf('business', 'login_risk'),
    );
  });

  test('sender 成功后 pending 队列被清空', () async {
    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'ok_case',
      severity: Severity.info,
      message: 'hi',
    );
    expect(captured.length, 1);
    expect(await CrashPersistence.loadPending(), isEmpty);
  });

  test('sender 失败时 payload 留在 pending（下次重发）', () async {
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: (_) async => throw Exception('network down'),
    );

    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'failed_case',
      severity: Severity.info,
      message: 'hi',
    );
    final pending = await CrashPersistence.loadPending();
    expect(pending.length, 1);
    expect(pending.single.payload['subKey'], 'failed_case');
  });

  test('上次有心跳但无 cleanShutdown → 合成 suspected_native_crash', () async {
    // 1. 模拟"上一轮运行"：写心跳、不写 cleanShutdown
    await CrashPersistence.writeHeartbeat(
      {'type': 'video', 'url': 'http://foo/a.mp4'},
      breadcrumbs: [
        {'ts': 1, 'category': 'nav', 'message': 'push /player'},
      ],
    );

    // 2. 本轮冷启动模拟：debugForceEnable + 手动驱动 detect 步骤
    XCrashSDK.debugReset();
    captured.clear();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();

    expect(captured.length, 1);
    final p = _decode(captured.single);
    expect(p['subKey'], 'suspected_native_crash');
    expect(p['data']['lastHeartbeatState'],
        {'type': 'video', 'url': 'http://foo/a.mp4'});
    expect((p['data']['lastBreadcrumbs'] as List).single['message'],
        'push /player');
  });

  test('上次正常退出（有 cleanShutdown）→ 不合成 suspected_native_crash',
      () async {
    await CrashPersistence.writeHeartbeat({'type': 'boot'});
    await CrashPersistence.markCleanShutdown();

    XCrashSDK.debugReset();
    captured.clear();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();

    expect(captured, isEmpty);
  });

  test('裸 boot 心跳（无面包屑）→ 视为 swipe-kill，不合成 suspected_native_crash',
      () async {
    // 模拟：上次冷启 → init 写了 boot 心跳 → 用户立刻 swipe-kill，
    // 没来得及触发 paused/markCleanShutdown，也没产生任何业务面包屑。
    await CrashPersistence.writeHeartbeat({'type': 'boot', 'sessionId': 'x'});

    XCrashSDK.debugReset();
    captured.clear();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();

    expect(captured, isEmpty);
  });

  test('boot 心跳但带了面包屑 → 仍然合成 suspected_native_crash', () async {
    // 反例：boot 心跳之后业务有动作（攒到面包屑），随后才挂掉，
    // 这种是真崩溃信号，不应该被裸 boot 过滤吞掉。
    await CrashPersistence.writeHeartbeat(
      {'type': 'boot', 'sessionId': 'x'},
      breadcrumbs: [
        {'ts': 1, 'category': 'nav', 'message': 'push /home'},
      ],
    );

    XCrashSDK.debugReset();
    captured.clear();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();

    expect(captured.length, 1);
    expect(_decode(captured.single)['subKey'], 'suspected_native_crash');
  });

  test('启动时把 pending 补发完并从队列里移除', () async {
    // 直接往 pending 里塞一条，模拟上次进程没送完
    final pendingId = await CrashPersistence.addPending({
      'eventType': 'api',
      'subKey': '/feed:500',
      'severity': 'warning',
      'message': 'pending from last run',
    });
    expect(pendingId, isNotNull);
    expect((await CrashPersistence.loadPending()).length, 1);

    XCrashSDK.debugReset();
    captured.clear();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();

    // sender 被喂了上次那条
    expect(captured.length, 1);
    expect(_decode(captured.single)['message'], 'pending from last run');
    // pending 队列已清空
    expect(await CrashPersistence.loadPending(), isEmpty);
  });

  test('flush 把 pending 全发掉并清空队列', () async {
    // 先制造两条 pending（sender 失败时会留下来）
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: (_) async => throw Exception('boom'),
    );
    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'a',
      severity: Severity.info,
      message: 'one',
    );
    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'b',
      severity: Severity.info,
      message: 'two',
    );
    expect((await CrashPersistence.loadPending()).length, 2);

    // 换一个会成功的 sender，flush 应该把两条都发掉并清空
    captured.clear();
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: captureSender);
    await XCrashSDK.flush();

    expect(captured.length, 2);
    expect(await CrashPersistence.loadPending(), isEmpty);
  });

  test('flush 不会 bump attempt（多次调用不会把 payload 推向毒丸）', () async {
    // 直接塞 1 条到 pending
    await CrashPersistence.addPending({'eventType': 'api', 'subKey': 'k'});

    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: (_) async => throw Exception('still down'),
    );

    // flush 5 次都失败 —— 由于不 bump attempt，毒丸保护不会触发
    for (var i = 0; i < 5; i++) {
      await XCrashSDK.flush();
    }
    final pending = await CrashPersistence.loadPending();
    expect(pending.length, 1);
    expect(pending.single.attempt, 0);
  });

  test('clearPersistence 清掉 pending / heartbeat / cleanShutdown', () async {
    await CrashPersistence.addPending({'eventType': 'api', 'subKey': 'k'});
    await CrashPersistence.writeHeartbeat({'type': 'video'});
    await CrashPersistence.markCleanShutdown();

    await XCrashSDK.clearPersistence();

    expect(await CrashPersistence.loadPending(), isEmpty);
    expect(await CrashPersistence.readHeartbeat(), isNull);
    expect(await CrashPersistence.wasCleanShutdown(), isFalse);
  });

  test('pending 重发失败 3 次后被当作毒丸丢弃', () async {
    await CrashPersistence.addPending({'m': 'poison'});

    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: (_) async => throw Exception('always fail'),
    );

    // 第 1 / 2 次失败：bumpPendingAttempt 把 attempt 从 0→1→2，仍未达毒丸阈值
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();
    expect((await CrashPersistence.loadPending()).length, 1);

    // 第 3 次失败时 bump 把 attempt 推到 _maxAttempts（=3），毒丸丢弃
    await XCrashSDK.debugFlushPendingAndDetectLastCrash();
    expect(await CrashPersistence.loadPending(), isEmpty);
  });

  test('userProvider 抛异常被吞掉，user 字段为 null，主 sender 仍然收到 payload',
      () async {
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(
      sender: captureSender,
      userProvider: () => throw StateError('provider boom'),
    );

    await XCrashSDK.report(
      type: EventType.business,
      subKey: 'k',
      severity: Severity.info,
      message: 'hi',
    );

    expect(captured.length, 1);
    final p = _decode(captured.single);
    expect(p['user'], isNull);
    // 其它字段不受影响
    expect(p['message'], 'hi');
  });
}

