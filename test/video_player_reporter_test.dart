import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:xcrash/xcrash.dart';

/// 用 noSuchMethod 兜底实现 VideoPlayerController 接口，避免引入
/// mocktail / 不开 native channel。我们其实只用到 ValueNotifier 那部分
/// （addListener / removeListener / value），其余方法被 noSuchMethod 接住。
class _FakeVideoController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  _FakeVideoController([VideoPlayerValue? initial])
      : super(initial ?? const VideoPlayerValue(duration: Duration.zero));

  void emit(VideoPlayerValue v) {
    value = v;
    notifyListeners();
  }

  // VideoPlayerController.dispose 返回 Future<void>，与 ChangeNotifier.dispose
  // (void) 签名不一致，必须显式 override。
  @override
  Future<void> dispose() async {
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

VideoPlayerValue _value({
  Duration position = Duration.zero,
  bool isPlaying = false,
  String? errorDescription,
  bool isInitialized = true,
  bool isBuffering = false,
}) {
  return VideoPlayerValue(
    duration: const Duration(seconds: 100),
    position: position,
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    isInitialized: isInitialized,
    errorDescription: errorDescription,
  );
}

/// listener 触发的 reportVideoError 是 fire-and-forget，本身不返回 Future。
/// 测试需要等 sender 那一路 microtask + 持久化队列排干才能断言 captured。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late List<String> captured;
  late _FakeVideoController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    captured = <String>[];
    XCrashSDK.debugReset();
    XCrashSDK.debugForceEnable(sender: (s) async => captured.add(s));
    controller = _FakeVideoController();
  });

  tearDown(XCrashSDK.debugReset);

  Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  List<Map<String, dynamic>> _byKey(String subKey) => captured
      .map(_decode)
      .where((p) => p['subKey'] == subKey)
      .toList();

  test('attach 幂等：重复 attach 不会装多份 listener', () async {
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    );
    reporter.attach();
    reporter.attach();
    reporter.attach();
    expect(reporter.isAttached, isTrue);

    controller.emit(_value(errorDescription: 'boom'));
    await _settle();
    expect(_byKey('playback_error').length, 1);
  });

  test('value.hasError → playback_error 一次后短路（同一 controller 不刷屏）',
      () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    ).attach();

    controller.emit(_value(errorDescription: 'decode failed'));
    await _settle();
    controller.emit(_value(errorDescription: 'still failed'));
    await _settle();
    controller.emit(_value(errorDescription: 'and again'));
    await _settle();

    final errs = _byKey('playback_error');
    expect(errs.length, 1, reason: 'should only fire once per attach');
    expect(errs.single['data']['errorDescription'], 'decode failed');
  });

  test('isPlaying + position 不推进达阈值 → buffer_stall', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
      bufferStallThreshold: const Duration(milliseconds: 50),
    ).attach();

    // 首次 onChange：标记 lastPositionChangeMs
    controller.emit(_value(
      isPlaying: true,
      position: const Duration(seconds: 5),
    ));
    await _settle();
    expect(_byKey('buffer_stall'), isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    // 同一 position 再触发一次 onChange
    controller.emit(_value(
      isPlaying: true,
      position: const Duration(seconds: 5),
    ));
    await _settle();
    expect(_byKey('buffer_stall').length, 1);
  });

  test('isPlaying 但 position 推进 → 不报 buffer_stall', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
      bufferStallThreshold: const Duration(milliseconds: 30),
    ).attach();

    controller.emit(_value(
      isPlaying: true,
      position: const Duration(seconds: 1),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.emit(_value(
      isPlaying: true,
      position: const Duration(seconds: 2), // position 推进了
    ));
    await _settle();
    expect(_byKey('buffer_stall'), isEmpty);
  });

  test('attach 后未拿到首帧 → first_frame_timeout', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
      firstFrameTimeout: const Duration(milliseconds: 30),
    ).attach();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(_byKey('first_frame_timeout').length, 1);
    expect(_byKey('first_frame_timeout').single['data']['timeoutMs'], 30);
  });

  test('在 firstFrameTimeout 内拿到首帧 → 不报 first_frame_timeout', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
      firstFrameTimeout: const Duration(milliseconds: 60),
    ).attach();

    // 在 timer 触发之前 emit 一帧
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.emit(_value(
      isPlaying: true,
      position: const Duration(milliseconds: 1),
    ));
    // 等过 timeout 时间
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(_byKey('first_frame_timeout'), isEmpty);
  });

  test('detach 后 listener 不再触发', () async {
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    )..attach();
    reporter.detach();
    expect(reporter.isAttached, isFalse);

    controller.emit(_value(errorDescription: 'boom'));
    await _settle();
    expect(_byKey('playback_error'), isEmpty);
  });

  test('detach 是幂等的（重复调不抛）', () {
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    )..attach();
    reporter.detach();
    reporter.detach();
    reporter.detach();
    expect(reporter.isAttached, isFalse);
  });

  test('reportVisualGlitch attach 后能上报 visual_glitch + 当前 position',
      () async {
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    )..attach();

    controller.emit(_value(
      position: const Duration(seconds: 12),
      isPlaying: true,
    ));
    await _settle();
    captured.clear();

    await reporter.reportVisualGlitch(extra: {'feedback': '画面花屏'});

    final glitch = _byKey('visual_glitch');
    expect(glitch.length, 1);
    expect(glitch.single['data']['positionMs'], 12000);
    expect(glitch.single['data']['feedback'], '画面花屏');
  });

  test('未 attach 时 reportVisualGlitch 静默忽略（不抛、不上报）', () async {
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
    );
    await reporter.reportVisualGlitch();
    expect(_byKey('visual_glitch'), isEmpty);
  });

  test('payload.context = videoUrl，方便后端按视频源聚合', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://cdn/movie.m3u8',
    ).attach();

    controller.emit(_value(errorDescription: 'x'));
    await _settle();

    final p = _byKey('playback_error').single;
    expect(p['context'], 'http://cdn/movie.m3u8');
    expect(p['data']['videoUrl'], 'http://cdn/movie.m3u8');
  });

  test('metadata 透传到 data', () async {
    VideoPlayerReporter(
      controller: controller,
      videoUrl: 'http://test/a.mp4',
      metadata: {'albumId': 'A123', 'episode': 7},
    ).attach();

    controller.emit(_value(errorDescription: 'x'));
    await _settle();

    final p = _byKey('playback_error').single;
    expect(p['data']['albumId'], 'A123');
    expect(p['data']['episode'], 7);
  });
}
