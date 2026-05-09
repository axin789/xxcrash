import 'dart:math';

import 'package:flutter/foundation.dart';

/// 单次 App 启动的会话。冷启动一次就变一次。
/// 所有上报事件都带上 sessionId，后端可聚合同一用户在同一会话内的行为。
class Session {
  static String? _id;
  static int? _startTimeMs;
  static int _foregroundCount = 0;

  static void init() {
    if (_id != null) return;
    _id = _generateId();
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;
  }

  static String get id {
    // 在极端情况（init 之前就有异常被抛出）也要能出一个合法 id。
    if (_id == null) init();
    return _id!;
  }

  static int get startTimeMs {
    if (_startTimeMs == null) init();
    return _startTimeMs!;
  }

  static void markForeground() => _foregroundCount++;

  static Map<String, dynamic> toMap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'id': id,
      'startTimeMs': startTimeMs,
      'durationMs': now - startTimeMs,
      'foregroundCount': _foregroundCount,
    };
  }

  @visibleForTesting
  static void debugReset() {
    _id = null;
    _startTimeMs = null;
    _foregroundCount = 0;
  }

  static String _generateId() {
    // 优先用密码学安全 RNG（减小同毫秒冷启下的碰撞概率）；
    // 个别不支持的宿主回落到 Random()。
    Random rnd;
    try {
      rnd = Random.secure();
    } catch (_) {
      rnd = Random();
    }
    final bytes = List.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
