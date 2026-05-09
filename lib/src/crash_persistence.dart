import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 崩溃 payload 的本地持久化层。
///
/// 解决的问题：进程死掉时已经在飞的 HTTP 请求会断，
/// 之前已经组装好但没送出去的 payload 全部丢失。
///
/// 方案：
/// 1. **Pending 队列** —— `report()` 在发网络之前先把 payload 写盘；
///    发成功后删；下次启动把上次没送完的捞出来重发。
/// 2. **Heartbeat** —— 关键时机写"我现在正在做 X"；
///    下次启动如果看到心跳但没"正常退出"标记，合成一条疑似崩溃事件。
/// 3. **串行化** —— 所有 read-modify-write 都排队跑（`_queue` Future 链），
///    多路并发 `report()` 不会互相覆盖或丢条目。
///
/// 失败只 debugPrint，不抛。
class CrashPersistence {
  static const _kPending = 'xcrash.pending.v1';
  static const _kHeartbeat = 'xcrash.heartbeat.v1';
  static const _kCleanShutdown = 'xcrash.clean_shutdown.v1';

  /// 最多保留多少条未送出的 payload；超出按 FIFO 淘汰最早的。
  static const int _maxPending = 20;

  /// 一条 payload 被重试上限，避免"毒丸"条目无限霸占队列。
  /// 调用方在每次 dispatch 失败后调 [bumpPendingAttempt] 增计数；
  /// [loadPendingForRetry] 在加载时把已经达到此上限的条目丢弃。
  static const int _maxAttempts = 3;

  /// 单条 payload 在队列里的最长寿命。超过即视为过期丢弃 ——
  /// 一条 7 天前的崩溃用今天的 sessionId / token / 服务端 schema
  /// 重发对后端是脏数据，宁可不报也别污染统计。
  static const int _maxAgeMs = 7 * 24 * 60 * 60 * 1000;

  /// 所有读写串行化在这一条 Future 链上，
  /// 避免 read-modify-write 竞态（多个 `addPending` 并发覆盖）。
  static Future<void> _queue = Future.value();

  static final Random _rnd = _createRng();

  static Random _createRng() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static Future<T> _serialize<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  // ---------- Pending ----------

  /// 新增一条待上报 payload。返回存储 id（删除时用）。失败返回 null。
  static Future<String?> addPending(Map<String, dynamic> payload) {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList(_kPending) ?? <String>[];
        final id = _newId();
        list.add(jsonEncode({
          'id': id,
          'payload': payload,
          'attempt': 0,
          'addedAtMs': DateTime.now().millisecondsSinceEpoch,
        }));
        while (list.length > _maxPending) {
          list.removeAt(0);
        }
        await prefs.setStringList(_kPending, list);
        return id;
      } catch (e) {
        debugPrint('[CrashPersistence] addPending failed: $e');
        return null;
      }
    });
  }

  /// 删除指定 id 的 payload（发送成功后调）。
  static Future<void> removePending(String id) {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList(_kPending) ?? <String>[];
        list.removeWhere((raw) {
          try {
            return (jsonDecode(raw) as Map)['id'] == id;
          } catch (_) {
            return false;
          }
        });
        await prefs.setStringList(_kPending, list);
      } catch (e) {
        debugPrint('[CrashPersistence] removePending failed: $e');
      }
    });
  }

  /// 读出全部未送出的 payload（只读，不改动状态）。
  static Future<List<PendingEntry>> loadPending() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList(_kPending) ?? const <String>[];
        return list.map(_parseEntry).whereType<PendingEntry>().toList();
      } catch (e) {
        debugPrint('[CrashPersistence] loadPending failed: $e');
        return const <PendingEntry>[];
      }
    });
  }

  /// 为"启动时重试未送出"路径专用：原子地读取 pending，丢弃毒丸 / 过期条目。
  ///
  /// 与 [loadPending] 的区别：会顺手清理已经达到 [_maxAttempts] / 寿命超过
  /// [_maxAgeMs] 的条目。**不**自增 attempt 计数 —— 那一步推迟到调用方
  /// 在每次 dispatch 失败之后再调 [bumpPendingAttempt] 完成。
  ///
  /// 这样可以避免一个常见的恶劣情况：进程死在 dispatch 中途时，旧实现已经
  /// 把 attempt +1 写盘了，下次启动又 +1 …… 结果"启动到一半就崩 3 次"
  /// 就把 payload 直接判了死刑。新实现下，attempt 只在确认本轮失败后才递增。
  static Future<List<PendingEntry>> loadPendingForRetry() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raws = prefs.getStringList(_kPending) ?? const <String>[];
        final survivors = <String>[];
        final out = <PendingEntry>[];
        var changed = false;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final raw in raws) {
          final entry = _parseEntry(raw);
          if (entry == null) {
            changed = true; // 坏数据顺手清掉
            continue;
          }
          if (entry.attempt >= _maxAttempts) {
            debugPrint(
              '[CrashPersistence] drop poison pending ${entry.id} '
              'after ${entry.attempt} attempts',
            );
            changed = true;
            continue;
          }
          if (entry.addedAtMs != null &&
              now - entry.addedAtMs! > _maxAgeMs) {
            debugPrint(
              '[CrashPersistence] drop expired pending ${entry.id} '
              '(age ${now - entry.addedAtMs!}ms > $_maxAgeMs)',
            );
            changed = true;
            continue;
          }
          survivors.add(raw);
          out.add(entry);
        }
        if (changed) {
          await prefs.setStringList(_kPending, survivors);
        }
        return out;
      } catch (e) {
        debugPrint('[CrashPersistence] loadPendingForRetry failed: $e');
        return const <PendingEntry>[];
      }
    });
  }

  /// 把指定 id 条目的 attempt 计数 +1。调用方在每次 dispatch 失败后调用。
  /// 失败次数达到 [_maxAttempts] 时直接丢弃（与 [loadPendingForRetry] 的
  /// 毒丸判定形成双保险，避免 attempt=_maxAttempts 的条目下次还能被取出）。
  static Future<void> bumpPendingAttempt(String id) {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raws = prefs.getStringList(_kPending) ?? const <String>[];
        final survivors = <String>[];
        var changed = false;
        for (final raw in raws) {
          final entry = _parseEntry(raw);
          if (entry == null) {
            changed = true;
            continue;
          }
          if (entry.id != id) {
            survivors.add(raw);
            continue;
          }
          final next = entry.attempt + 1;
          if (next >= _maxAttempts) {
            debugPrint(
              '[CrashPersistence] drop poison pending ${entry.id} '
              'after $next attempts',
            );
            changed = true;
            continue;
          }
          survivors.add(jsonEncode({
            'id': entry.id,
            'payload': entry.payload,
            'attempt': next,
            if (entry.addedAtMs != null) 'addedAtMs': entry.addedAtMs,
          }));
          changed = true;
        }
        if (changed) {
          await prefs.setStringList(_kPending, survivors);
        }
      } catch (e) {
        debugPrint('[CrashPersistence] bumpPendingAttempt failed: $e');
      }
    });
  }

  // ---------- Heartbeat ----------

  /// 写一条心跳（记录当前正在做什么）。
  /// 同时会清掉 clean_shutdown 标记，等下次 [markCleanShutdown] 才恢复。
  ///
  /// [state]       业务语义快照，如 `{'type':'video', 'url':'...'}`
  /// [breadcrumbs] 可选的面包屑快照（通常是 `BreadcrumbBuffer.snapshot()`），
  ///               会一起落盘；下次疑似崩溃检测时把它当作"死前时间轴"上报。
  static Future<void> writeHeartbeat(
    Map<String, dynamic> state, {
    List<Map<String, dynamic>>? breadcrumbs,
  }) {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _kHeartbeat,
          jsonEncode({
            'ts': DateTime.now().millisecondsSinceEpoch,
            'state': state,
            if (breadcrumbs != null && breadcrumbs.isNotEmpty)
              'breadcrumbs': breadcrumbs,
          }),
        );
        await prefs.remove(_kCleanShutdown);
      } catch (e) {
        debugPrint('[CrashPersistence] writeHeartbeat failed: $e');
      }
    });
  }

  /// 单独清掉 clean_shutdown 标记（app 重新 resumed 时调），
  /// 避免上一次 paused 写的标记"粘"到这次运行里，导致真崩被误判。
  static Future<void> clearCleanShutdown() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kCleanShutdown);
      } catch (e) {
        debugPrint('[CrashPersistence] clearCleanShutdown failed: $e');
      }
    });
  }

  /// 读上次运行的最后心跳。没写过返回 null。
  static Future<Map<String, dynamic>?> readHeartbeat() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kHeartbeat);
        if (raw == null) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
        return null;
      } catch (e) {
        debugPrint('[CrashPersistence] readHeartbeat failed: $e');
        return null;
      }
    });
  }

  // ---------- Clean shutdown ----------

  /// 标记本次运行是正常退出（lifecycle paused/detached 时调）。
  static Future<void> markCleanShutdown() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kCleanShutdown, true);
      } catch (e) {
        debugPrint('[CrashPersistence] markCleanShutdown failed: $e');
      }
    });
  }

  /// 上次是否是正常退出？读不到或读失败默认 false（保守偏向"疑似崩溃"）。
  static Future<bool> wasCleanShutdown() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(_kCleanShutdown) ?? false;
      } catch (e) {
        debugPrint('[CrashPersistence] wasCleanShutdown failed: $e');
        return false;
      }
    });
  }

  /// 测试/切账号时重置全部状态。
  static Future<void> clearAll() {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kPending);
        await prefs.remove(_kHeartbeat);
        await prefs.remove(_kCleanShutdown);
      } catch (_) {}
    });
  }

  // ---------- 内部 ----------

  /// `<microseconds>.<8-hex-random>`；同微秒并发 addPending 也不会碰撞。
  static String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = _rnd.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$ts.$rand';
  }

  static PendingEntry? _parseEntry(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = m['id']?.toString();
      final payload = m['payload'];
      if (id == null || payload is! Map) return null;
      return PendingEntry(
        id: id,
        payload: payload.cast<String, dynamic>(),
        attempt: (m['attempt'] as int?) ?? 0,
        addedAtMs: m['addedAtMs'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

class PendingEntry {
  final String id;
  final Map<String, dynamic> payload;

  /// 已经被启动流程尝试重发过多少次（不含"本次 report 首次发送"）。
  final int attempt;

  /// 写入队列时的墙上时间戳。用于"超过 7 天就丢弃"的过期判定。
  /// 旧版本写入的条目可能没有此字段，按 null 处理 = 永不过期。
  final int? addedAtMs;

  PendingEntry({
    required this.id,
    required this.payload,
    this.attempt = 0,
    this.addedAtMs,
  });
}
