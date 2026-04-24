
class ErrorReportLimiter {
  /// 是否允许真正上报（由 SDK 初始化控制）
  static bool _reportEnabled = false;
  static bool get reportEnabled => _reportEnabled;
  /// SDK 内部调用
  static void setReportEnabled(bool enable) {
    _reportEnabled = enable;
  }
  /// 上一次真正上报时间
  static final Map<String, int> _lastReportTime = {};

  /// 被限频压制的次数（会清零）
  static final Map<String, int> _suppressedCount = {};

  /// 异常累计出现次数（不会清零，用于起步阈值）
  static final Map<String, int> _totalHitCount = {};

  /// 被压制期间出现过的 context / path
  static final Map<String, Set<String>> _suppressedContexts = {};

  /// 异常详情快照（每个 key 一份）
  static final Map<String, _ErrorSnapshot> _errorSnapshots = {};

  /// 限频时间（1 分钟）
  static int _intervalMs = 1 * 60 * 1000;

  static int get intervalMs => _intervalMs;

  /// 最多记录多少种异常
  static const int _maxSnapshots = 50;

  /// ⭐ 起步上报阈值（按异常类型）
  /// key = runtimeType.toString()
  static final Map<String, int> _startReportThreshold = {};

  /// 判断是否允许上报
  ///
  /// 返回值：
  /// - int  : 允许上报，返回被压制次数
  /// - null : 不允许上报
  static int? shouldReport(
      String key, {
        String? context,
        Object? error,
        StackTrace? stackTrace,
      }) {
    /// ❌ 未开启上报 → 一律不允许
    if (!_reportEnabled) {
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastReportTime[key];

    final errorType = error?.runtimeType.toString() ?? 'Unknown';

    /// 📈 累计出现次数（不会清零）
    _totalHitCount[key] = (_totalHitCount[key] ?? 0) + 1;

    /// 🧠 首次出现 → 创建快照
    _errorSnapshots.putIfAbsent(key, () {
      _ensureCapacity();

      return _ErrorSnapshot(
        errorType: errorType,
        message: error?.toString() ?? 'No message',
        stackSample: _buildStackSample(stackTrace),
        firstTime: now,
        lastTime: now,
      );
    });

    /// 每次命中更新最近发生时间
    _errorSnapshots[key]?.lastTime = now;

    /// 🚫 起步阈值判断（未达到 → 一律压制）
    final threshold = _startReportThreshold[errorType] ?? 0;
    if (_totalHitCount[key]! < threshold) {
      _suppressedCount[key] = (_suppressedCount[key] ?? 0) + 1;

      if (context != null) {
        _suppressedContexts
            .putIfAbsent(key, () => <String>{})
            .add(context);
      }
      return null;
    }

    /// ⏱ 正常限频逻辑
    if (last == null || now - last >= _intervalMs) {
      final count = _suppressedCount[key] ?? 0;
      _lastReportTime[key] = now;
      _suppressedCount[key] = 0;
      return count;
    } else {
      _suppressedCount[key] = (_suppressedCount[key] ?? 0) + 1;

      if (context != null) {
        _suppressedContexts
            .putIfAbsent(key, () => <String>{})
            .add(context);
      }
      return null;
    }
  }

  /// 起步上报阈值（按异常类型）
  static void setStartReportThresholds(
      Map<String, int> configs,
      ) {
    for (final entry in configs.entries) {
      if (entry.value >= 0) {
        _startReportThreshold[entry.key] = entry.value;
      }
    }
  }

  /// 🔓 SDK 内部配置入口
  static void setIntervalMs(int intervalMs) {
    if (intervalMs <= 0) return;
    _intervalMs = intervalMs;
  }

  /// 确保容量，超出时淘汰最早的异常
  static void _ensureCapacity() {
    if (_errorSnapshots.length < _maxSnapshots) return;

    String? oldestKey;
    int? oldestTime;

    for (final entry in _errorSnapshots.entries) {
      final t = entry.value.firstTime;
      if (oldestTime == null || t < oldestTime) {
        oldestTime = t;
        oldestKey = entry.key;
      }
    }

    if (oldestKey == null) return;

    _errorSnapshots.remove(oldestKey);
    _suppressedContexts.remove(oldestKey);
    _suppressedCount.remove(oldestKey);
    _lastReportTime.remove(oldestKey);
    _totalHitCount.remove(oldestKey);
  }

  /// 获取被压制次数
  static int suppressedCount(String key) {
    return _suppressedCount[key] ?? 0;
  }

  /// 只查看被压制的 context（不清空）
  static List<String> peekSuppressedContexts(String key) {
    return _suppressedContexts[key]?.toList() ?? const [];
  }

  /// 允许上报时取出并清空 context
  static List<String> takeSuppressedContexts(String key) {
    final list = _suppressedContexts[key]?.toList() ?? const [];
    _suppressedContexts.remove(key);
    return list;
  }

  /// 🚀 导出所有异常（用于“导出异常 / 分享”）
  static Map<String, Map<String, dynamic>> exportAll() {
    final result = <String, Map<String, dynamic>>{};

    for (final key in _errorSnapshots.keys) {
      final snapshot = _errorSnapshots[key];

      result[key] = {
        'errorType': snapshot?.errorType,
        'message': snapshot?.message,
        'stackSample': snapshot?.stackSample,
        'firstTime': snapshot?.firstTime,
        'lastTime': snapshot?.lastTime,
        'suppressedCount': _suppressedCount[key] ?? 0,
        'totalHitCount': _totalHitCount[key] ?? 0,
        'contexts': _suppressedContexts[key]?.toList() ?? [],
      };
    }

    return result;
  }

  /// 🧹 手动清空
  static void clear() {
    _lastReportTime.clear();
    _suppressedCount.clear();
    _suppressedContexts.clear();
    _errorSnapshots.clear();
    _totalHitCount.clear();
  }

  /// 取 stack 前几行
  static String? _buildStackSample(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final lines = stackTrace.toString().split('\n');
    return lines.take(5).join('\n');
  }
}

/// ================================
/// 内部异常快照模型（私有）
/// ================================
class _ErrorSnapshot {
  final String errorType;
  final String message;
  final String? stackSample;
  final int firstTime;
  int lastTime;

  _ErrorSnapshot({
    required this.errorType,
    required this.message,
    this.stackSample,
    required this.firstTime,
    required this.lastTime,
  });
}
