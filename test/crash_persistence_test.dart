import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcrash/src/crash_persistence.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Pending', () {
    test('addPending 返回 id；loadPending 按写入顺序给回', () async {
      final id1 = await CrashPersistence.addPending({'n': 1});
      final id2 = await CrashPersistence.addPending({'n': 2});
      expect(id1, isNotNull);
      expect(id2, isNotNull);
      expect(id1, isNot(id2));

      final list = await CrashPersistence.loadPending();
      expect(list.length, 2);
      expect(list[0].payload['n'], 1);
      expect(list[1].payload['n'], 2);
    });

    test('removePending 按 id 删除', () async {
      final id1 = await CrashPersistence.addPending({'n': 1});
      await CrashPersistence.addPending({'n': 2});
      await CrashPersistence.removePending(id1!);

      final list = await CrashPersistence.loadPending();
      expect(list.length, 1);
      expect(list.single.payload['n'], 2);
    });

    test('超过 20 条时按 FIFO 淘汰最早', () async {
      for (var i = 0; i < 25; i++) {
        await CrashPersistence.addPending({'n': i});
      }
      final list = await CrashPersistence.loadPending();
      expect(list.length, 20);
      expect(list.first.payload['n'], 5);
      expect(list.last.payload['n'], 24);
    });

    test('loadPending 忽略损坏的条目', () async {
      // 先写一条合法的
      await CrashPersistence.addPending({'n': 1});
      // 然后手动污染存储（模拟半残数据）
      final prefs = await SharedPreferences.getInstance();
      final corrupt = prefs.getStringList('xcrash.pending.v1')!.toList()
        ..insert(0, 'not json');
      await prefs.setStringList('xcrash.pending.v1', corrupt);

      final list = await CrashPersistence.loadPending();
      expect(list.length, 1);
      expect(list.single.payload['n'], 1);
    });

    test('并发 addPending 得到不同 id 且都不丢', () async {
      // 并发发 10 条，确保串行化 + id 随机后缀把 race 和微秒碰撞都挡住了
      final ids = await Future.wait(List.generate(
        10,
        (i) => CrashPersistence.addPending({'n': i}),
      ));
      expect(ids.whereType<String>().toSet().length, 10); // 全部唯一
      final list = await CrashPersistence.loadPending();
      expect(list.length, 10);
      // payload 不应该丢（顺序无所谓，Future.wait 并不保证）
      expect(
        list.map((e) => e.payload['n']).toSet(),
        List.generate(10, (i) => i).toSet(),
      );
    });

    test('loadPendingForRetry 不会 bump attempt（推迟到 dispatch 失败后由调用方显式 bump）',
        () async {
      await CrashPersistence.addPending({'n': 1});

      // 反复 retry 也不会改 attempt 计数 —— bump 时机已经迁移到 bumpPendingAttempt
      for (var i = 0; i < 5; i++) {
        final out = await CrashPersistence.loadPendingForRetry();
        expect(out.single.attempt, 0);
      }
    });

    test('bumpPendingAttempt 显式 +1，达到 _maxAttempts 即丢弃', () async {
      final id = await CrashPersistence.addPending({'n': 1});

      await CrashPersistence.bumpPendingAttempt(id!);
      expect((await CrashPersistence.loadPending()).single.attempt, 1);

      await CrashPersistence.bumpPendingAttempt(id);
      expect((await CrashPersistence.loadPending()).single.attempt, 2);

      // 第 3 次 bump 达到 _maxAttempts，毒丸丢弃
      await CrashPersistence.bumpPendingAttempt(id);
      expect(await CrashPersistence.loadPending(), isEmpty);
    });

    test('bumpPendingAttempt 找不到 id 也不会崩', () async {
      await CrashPersistence.addPending({'n': 1});
      await CrashPersistence.bumpPendingAttempt('nonexistent.id');
      // 原本那条不动
      final list = await CrashPersistence.loadPending();
      expect(list.length, 1);
      expect(list.single.attempt, 0);
    });

    test('loadPendingForRetry 丢弃超过 7 天的过期条目', () async {
      // 手动塞一条 8 天前的脏数据，模拟一个长期占位的老 payload
      final prefs = await SharedPreferences.getInstance();
      final ancient = DateTime.now().millisecondsSinceEpoch -
          8 * 24 * 60 * 60 * 1000;
      await prefs.setStringList('xcrash.pending.v1', [
        '{"id":"old.1","payload":{"n":1},"attempt":0,"addedAtMs":$ancient}',
      ]);

      final out = await CrashPersistence.loadPendingForRetry();
      expect(out, isEmpty);
      expect(await CrashPersistence.loadPending(), isEmpty);
    });

    test('loadPendingForRetry 对没有 addedAtMs 字段的旧条目不会误判过期', () async {
      // 模拟旧版本写入：没有 addedAtMs 字段
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('xcrash.pending.v1', [
        '{"id":"legacy.1","payload":{"n":1},"attempt":0}',
      ]);

      final out = await CrashPersistence.loadPendingForRetry();
      expect(out.length, 1);
      expect(out.single.payload['n'], 1);
    });
  });

  group('Heartbeat + clean shutdown', () {
    test('writeHeartbeat → readHeartbeat 返回带 ts/state', () async {
      await CrashPersistence.writeHeartbeat({'video': '/a.mp4'});
      final hb = await CrashPersistence.readHeartbeat();
      expect(hb, isNotNull);
      expect(hb!['state'], {'video': '/a.mp4'});
      expect(hb['ts'], isA<int>());
    });

    test('writeHeartbeat 会清掉上一轮的 cleanShutdown', () async {
      await CrashPersistence.markCleanShutdown();
      expect(await CrashPersistence.wasCleanShutdown(), isTrue);

      await CrashPersistence.writeHeartbeat({'x': 1});
      expect(await CrashPersistence.wasCleanShutdown(), isFalse);
    });

    test('首次启动无心跳时 readHeartbeat 返回 null', () async {
      expect(await CrashPersistence.readHeartbeat(), isNull);
    });

    test('markCleanShutdown 后 wasCleanShutdown 为 true', () async {
      await CrashPersistence.markCleanShutdown();
      expect(await CrashPersistence.wasCleanShutdown(), isTrue);
    });

    test('clearCleanShutdown 只清标记，保留心跳', () async {
      await CrashPersistence.writeHeartbeat({'x': 1});
      await CrashPersistence.markCleanShutdown();

      await CrashPersistence.clearCleanShutdown();

      expect(await CrashPersistence.wasCleanShutdown(), isFalse);
      expect(await CrashPersistence.readHeartbeat(), isNotNull);
    });

    test('writeHeartbeat 带 breadcrumbs 时会一并落盘', () async {
      await CrashPersistence.writeHeartbeat(
        {'type': 'boot'},
        breadcrumbs: [
          {'ts': 1, 'category': 'nav', 'message': 'push /home'},
          {'ts': 2, 'category': 'custom', 'message': 'tap play'},
        ],
      );
      final hb = await CrashPersistence.readHeartbeat();
      expect(hb!['breadcrumbs'], isA<List>());
      expect((hb['breadcrumbs'] as List).length, 2);
      expect((hb['breadcrumbs'] as List).last['message'], 'tap play');
    });

    test('writeHeartbeat 不传 breadcrumbs 则心跳里没有该字段', () async {
      await CrashPersistence.writeHeartbeat({'type': 'boot'});
      final hb = await CrashPersistence.readHeartbeat();
      expect(hb!.containsKey('breadcrumbs'), isFalse);
    });
  });

  test('clearAll 清空所有键', () async {
    await CrashPersistence.addPending({'n': 1});
    await CrashPersistence.writeHeartbeat({'x': 1});
    await CrashPersistence.markCleanShutdown();

    await CrashPersistence.clearAll();

    expect(await CrashPersistence.loadPending(), isEmpty);
    expect(await CrashPersistence.readHeartbeat(), isNull);
    expect(await CrashPersistence.wasCleanShutdown(), isFalse);
  });
}
