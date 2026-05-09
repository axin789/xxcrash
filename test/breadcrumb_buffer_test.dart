import 'package:flutter_test/flutter_test.dart';
import 'package:xcrash/src/breadcrumb/breadcrumb.dart';
import 'package:xcrash/src/breadcrumb/breadcrumb_buffer.dart';

void main() {
  test('add + snapshot 返回可序列化的 map 列表', () {
    final buf = BreadcrumbBuffer(capacity: 10);
    buf.add(Breadcrumb(category: 'nav', message: 'push /home'));
    buf.add(Breadcrumb(
      category: 'network',
      message: 'GET /foo 200',
      level: 'info',
      data: {'path': '/foo'},
    ));

    final snap = buf.snapshot();
    expect(snap.length, 2);
    expect(snap[0]['category'], 'nav');
    expect(snap[1]['data'], {'path': '/foo'});
    expect(snap[0].containsKey('ts'), isTrue);
  });

  test('超出容量时按 FIFO 丢弃最早', () {
    final buf = BreadcrumbBuffer(capacity: 3);
    for (var i = 0; i < 5; i++) {
      buf.add(Breadcrumb(category: 'c', message: 'm$i'));
    }
    final snap = buf.snapshot();
    expect(snap.length, 3);
    expect(snap.map((e) => e['message']).toList(), ['m2', 'm3', 'm4']);
  });

  test('clear 清空', () {
    final buf = BreadcrumbBuffer(capacity: 3);
    buf.add(Breadcrumb(category: 'c', message: 'a'));
    buf.clear();
    expect(buf.length, 0);
    expect(buf.snapshot(), isEmpty);
  });
}
