/// 事件上报限频器。按 key（通常是 `"${eventType}:${subKey}"`）节流。
///
/// 两道门：
/// 1. **起步阈值**：key 累计出现 N 次才允许首次上报（防冷启动噪音）
/// 2. **时间窗口**：允许一次后，`intervalMs` 内后续全部压制、累计
///
/// 被压制期间出现过的 `context` 字符串会收集起来（保持出现顺序、允许重复，
/// 单 key 最多 [_maxSuppressedPerKey] 条），
/// 下次允许上报时通过 [takeSuppressedContexts] 取出，随事件一起上报。
///
/// Key 总数有 [_maxTrackedKeys] 上限，超出时按插入顺序淘汰最早的 key，
/// 避免业务在 subKey 里塞未模板化的动态内容（如 URL 带 query）导致 Map 无界增长。
class ErrorReportLimiter {
  static bool _enabled = false;
  static int _intervalMs = 60 * 1000;

  /// 最多同时跟踪多少个不同 key。超出按插入顺序（FIFO）淘汰最早的。
  static const int _maxTrackedKeys = 500;

  /// 单个 key 最多收集多少条被压制的 context，防止被 flood 撑爆内存。
  static const int _maxSuppressedPerKey = 20;

  static final Map<String, int> _startThreshold = {};
  static final Map<String, int> _lastReportMs = {};
  static final Map<String, int> _totalHits = {};
  static final Map<String, int> _suppressed = {};
  static final Map<String, List<String>> _suppressedContexts = {};

  static void setReportEnabled(bool enabled) => _enabled = enabled;

  static void setIntervalMs(int ms) {
    if (ms > 0) _intervalMs = ms;
  }

  static void setStartReportThresholds(Map<String, int> configs) {
    _startThreshold.clear();
    for (final entry in configs.entries) {
      if (entry.value >= 0) _startThreshold[entry.key] = entry.value;
    }
  }

  /// 拼接限频 key 的规范方法，避免调用方手写字符串拼错。
  static String keyOf(String eventType, String subKey) => '$eventType:$subKey';

  /// 返回 null 表示压制；否则返回自上次允许以来被压制的次数。
  static int? shouldReport(String key, {String? context, Object? error}) {
    if (!_enabled) return null;

    // LRU-ish 淘汰：新 key 撞上限时，踢掉最早插入的那个
    if (!_totalHits.containsKey(key) && _totalHits.length >= _maxTrackedKeys) {
      final oldest = _totalHits.keys.first;
      _totalHits.remove(oldest);
      _lastReportMs.remove(oldest);
      _suppressed.remove(oldest);
      _suppressedContexts.remove(oldest);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _totalHits[key] = (_totalHits[key] ?? 0) + 1;

    // 起步阈值：优先按完整 key，再回落到 error 的 runtimeType
    final errorType = error?.runtimeType.toString();
    final threshold = _startThreshold[key] ??
        (errorType != null ? _startThreshold[errorType] ?? 0 : 0);
    if (_totalHits[key]! < threshold) {
      return _suppress(key, context);
    }

    final last = _lastReportMs[key];
    if (last == null || now - last >= _intervalMs) {
      final count = _suppressed[key] ?? 0;
      _lastReportMs[key] = now;
      _suppressed[key] = 0;
      return count;
    }
    return _suppress(key, context);
  }

  static int? _suppress(String key, String? context) {
    _suppressed[key] = (_suppressed[key] ?? 0) + 1;
    if (context != null) {
      final list = _suppressedContexts.putIfAbsent(key, () => <String>[]);
      if (list.length < _maxSuppressedPerKey) {
        list.add(context);
      }
    }
    return null;
  }

  /// 当前被压制次数（主要给测试用）。
  static int suppressedCount(String key) => _suppressed[key] ?? 0;

  /// 取出并清空被压制期间收集到的 context 列表。
  /// 保持插入顺序、允许重复（便于下游统计"反复打同一 URL"）。
  static List<String> takeSuppressedContexts(String key) =>
      _suppressedContexts.remove(key) ?? const [];

  /// 清空所有内部状态（用户切换等场景调用）。
  static void clear() {
    _lastReportMs.clear();
    _totalHits.clear();
    _suppressed.clear();
    _suppressedContexts.clear();
  }
}
