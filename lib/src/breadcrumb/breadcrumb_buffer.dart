import 'breadcrumb.dart';

/// 固定容量的环形缓冲区。超出容量时丢弃最老的一条。
/// 线程安全依赖 Dart 单线程事件循环——不要在 Isolate 中直接共享实例。
class BreadcrumbBuffer {
  final int capacity;
  final List<Breadcrumb> _buffer = [];

  BreadcrumbBuffer({this.capacity = 50});

  void add(Breadcrumb crumb) {
    _buffer.add(crumb);
    if (_buffer.length > capacity) {
      _buffer.removeAt(0);
    }
  }

  /// 快照当前缓冲区，返回可序列化的 Map 列表。
  /// 调用后缓冲区不清空——后续上报仍可复用已有面包屑。
  List<Map<String, dynamic>> snapshot() =>
      _buffer.map((c) => c.toMap()).toList();

  void clear() => _buffer.clear();

  int get length => _buffer.length;
}
