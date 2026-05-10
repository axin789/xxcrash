import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../crash_sdk.dart';
import '../event_type.dart';

/// 给 `video_player` 的 `VideoPlayerController` 套一层监听，自动采集并上报：
///
/// - `playback_error`      —— 播放器 `value.hasError` 变 true
/// - `buffer_stall`        —— 正在播放但 position 连续 N 秒没推进
/// - `first_frame_timeout` —— attach 后 N 秒还没拿到第一帧（position 仍为 0）
///
/// 画面花屏（`visual_glitch`）无法从 `video_player` 自动检测，
/// 通常由用户按"画面异常"按钮触发，对应方法：[reportVisualGlitch]。
///
/// 典型用法：
/// ```dart
/// final controller = VideoPlayerController.networkUrl(Uri.parse(url));
/// final reporter = VideoPlayerReporter(
///   controller: controller,
///   videoUrl: url,
///   metadata: {'albumId': 123},
/// );
/// reporter.attach();
///
/// // dispose:
/// reporter.detach();
/// controller.dispose();
/// ```
class VideoPlayerReporter {
  final VideoPlayerController controller;
  final String videoUrl;
  final Map<String, dynamic>? metadata;

  /// 卡顿判定阈值：isPlaying 但 position 超过这段时间没变化就算卡顿。
  final Duration bufferStallThreshold;

  /// 首帧超时：attach 后这段时间还没开始播就上报。
  final Duration firstFrameTimeout;

  bool _attached = false;
  bool _firstFrameReceived = false;
  bool _errorReported = false;
  Duration _lastPosition = Duration.zero;
  int _lastPositionChangeMs = 0;
  int _lastStallReportMs = 0;
  Timer? _firstFrameTimer;

  VideoPlayerReporter({
    required this.controller,
    required this.videoUrl,
    this.metadata,
    this.bufferStallThreshold = const Duration(seconds: 3),
    this.firstFrameTimeout = const Duration(seconds: 10),
  });

  /// 当前是否已 attach（尚未 detach）。
  bool get isAttached => _attached;

  void attach() {
    if (_attached) return;
    _attached = true;
    controller.addListener(_onChange);

    _firstFrameTimer = Timer(firstFrameTimeout, () {
      if (!_attached || _firstFrameReceived || _errorReported) return;
      // controller 有可能已经被上层 dispose —— value 访问在个别 video_player
      // 版本里会抛，这里兜底，不让 Timer 回调把异常抛到 zone handler。
      try {
        XCrashSDK.reportVideoError(
          subKey: 'first_frame_timeout',
          videoUrl: videoUrl,
          severity: Severity.error,
          extra: {
            'timeoutMs': firstFrameTimeout.inMilliseconds,
            'isInitialized': controller.value.isInitialized,
            if (metadata != null) ...metadata!,
          },
        );
      } catch (_) {}
    });
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    try {
      controller.removeListener(_onChange);
    } catch (_) {
      // controller 可能已 dispose，忽略
    }
    // 重置内部状态，允许同一 reporter 对象重新 attach 使用
    _firstFrameReceived = false;
    _errorReported = false;
    _lastPosition = Duration.zero;
    _lastPositionChangeMs = 0;
    _lastStallReportMs = 0;
  }

  void _onChange() {
    if (!_attached) return;
    final v = controller.value;

    if (!_firstFrameReceived && v.position > Duration.zero) {
      _firstFrameReceived = true;
    }

    // 播放错误：只报一次，避免 listener 被反复回调时刷屏
    if (v.hasError && !_errorReported) {
      _errorReported = true;
      XCrashSDK.reportVideoError(
        subKey: 'playback_error',
        videoUrl: videoUrl,
        severity: Severity.error,
        extra: {
          'errorDescription': v.errorDescription,
          'positionMs': v.position.inMilliseconds,
          'isInitialized': v.isInitialized,
          if (metadata != null) ...metadata!,
        },
      );
      return;
    }

    // 卡顿检测：isPlaying=true && 非 buffering 预期态 && position 没推进
    final now = DateTime.now().millisecondsSinceEpoch;
    if (v.isPlaying) {
      if (v.position != _lastPosition) {
        _lastPosition = v.position;
        _lastPositionChangeMs = now;
        return;
      }

      if (_lastPositionChangeMs == 0) {
        _lastPositionChangeMs = now;
        return;
      }

      final stalledMs = now - _lastPositionChangeMs;
      final reportedRecently = now - _lastStallReportMs < bufferStallThreshold.inMilliseconds;
      if (stalledMs >= bufferStallThreshold.inMilliseconds && !reportedRecently) {
        _lastStallReportMs = now;
        XCrashSDK.reportVideoError(
          subKey: 'buffer_stall',
          videoUrl: videoUrl,
          extra: {
            'stallMs': stalledMs,
            'positionMs': v.position.inMilliseconds,
            'bufferedEndMs':
                v.buffered.isEmpty ? 0 : v.buffered.last.end.inMilliseconds,
            'isBuffering': v.isBuffering,
            if (metadata != null) ...metadata!,
          },
        );
      }
    } else {
      _lastPositionChangeMs = 0;
    }
  }

  /// 用户手动触发的花屏/画面异常反馈。
  /// 建议在 UI 里放一个"画面异常"按钮让用户主动上报，附带时段快照。
  ///
  /// 返回 Future 让调用方能 await 上报完成（典型场景：弹一个"反馈已提交"
  /// 提示要等真发出去）。未 attach 时静默忽略，返回已 resolve 的 Future。
  Future<void> reportVisualGlitch({Map<String, dynamic>? extra}) {
    if (!_attached) {
      debugPrint('[VideoPlayerReporter] reportVisualGlitch ignored: not attached');
      return Future.value();
    }
    final v = controller.value;
    return XCrashSDK.reportVideoError(
      subKey: 'visual_glitch',
      videoUrl: videoUrl,
      severity: Severity.warning,
      extra: {
        'positionMs': v.position.inMilliseconds,
        'durationMs': v.duration.inMilliseconds,
        'size': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'playbackSpeed': v.playbackSpeed,
        if (metadata != null) ...metadata!,
        if (extra != null) ...extra,
      },
    );
  }
}
