import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/src/session.dart';

void main() {
  setUp(Session.debugReset);

  test('init 会产生非空的 16 字节 hex id', () {
    Session.init();
    expect(Session.id.length, 32);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(Session.id), isTrue);
  });

  test('init 幂等：多次调用 id 不变', () {
    Session.init();
    final id1 = Session.id;
    Session.init();
    expect(Session.id, id1);
  });

  test('debugReset 后会重新生成新 id', () {
    Session.init();
    final id1 = Session.id;
    Session.debugReset();
    Session.init();
    expect(Session.id, isNot(id1));
  });

  test('markForeground 累加 foregroundCount', () {
    Session.init();
    Session.markForeground();
    Session.markForeground();
    expect(Session.toMap()['foregroundCount'], 2);
  });

  test('toMap 带齐四个字段', () {
    Session.init();
    final map = Session.toMap();
    expect(map.keys.toSet(),
        {'id', 'startTimeMs', 'durationMs', 'foregroundCount'});
  });
}
