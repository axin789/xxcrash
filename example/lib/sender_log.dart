import 'package:flutter/foundation.dart';

/// 把每次 sender 收到的 JSON 字符串留个副本，方便 demo UI 实时展示。
///
/// 真实工程里当然不需要这层——直接把 content 塞进自家 HTTP 层就完了。
class SenderLog extends ChangeNotifier {
  SenderLog._();
  static final SenderLog instance = SenderLog._();

  /// 限制在最近 50 条，避免长时间跑 demo 内存飘起来。
  static const int _capacity = 50;

  final List<SenderLogEntry> _entries = <SenderLogEntry>[];

  List<SenderLogEntry> get entries => List.unmodifiable(_entries);
  SenderLogEntry? get latest => _entries.isEmpty ? null : _entries.last;

  void add(String content) {
    _entries.add(SenderLogEntry(DateTime.now(), content));
    if (_entries.length > _capacity) {
      _entries.removeRange(0, _entries.length - _capacity);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

class SenderLogEntry {
  final DateTime ts;
  final String content;

  SenderLogEntry(this.ts, this.content);
}
