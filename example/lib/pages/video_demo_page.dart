import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:xcrash/xcrash.dart';

/// `VideoPlayerReporter` 的完整演示：
///
/// - 加载示例视频 → attach
/// - 自动 `playback_error` / `buffer_stall` / `first_frame_timeout` 都会走 sender
/// - 播放源可以切到「故意坏掉的 URL」触发 playback_error
/// - 按钮手动触发 `reportVisualGlitch`
class VideoDemoPage extends StatefulWidget {
  static const route = '/video';
  const VideoDemoPage({super.key});

  @override
  State<VideoDemoPage> createState() => _VideoDemoPageState();
}

class _VideoDemoPageState extends State<VideoDemoPage> {
  static const _goodUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
  static const _badUrl = 'https://invalid.example.com/broken.mp4';

  VideoPlayerController? _controller;
  VideoPlayerReporter? _reporter;
  String? _loadingUrl;

  Future<void> _load(String url) async {
    setState(() => _loadingUrl = url);

    // 切源之前先清掉旧的 controller / reporter，避免 listener 泄漏。
    await _teardown();

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    final reporter = VideoPlayerReporter(
      controller: controller,
      videoUrl: url,
      metadata: const {'source': 'xcrash_demo'},
      // demo 里故意把阈值压小一点，方便演示卡顿/首帧超时。
      bufferStallThreshold: const Duration(seconds: 2),
      firstFrameTimeout: const Duration(seconds: 6),
    );
    reporter.attach();

    // 切源前写一次心跳：native 层如果此刻炸掉，下次启动能看到 "死在播这个 URL"。
    await XCrashSDK.updateHeartbeat({
      'type': 'video',
      'url': url,
      'enteredAt': DateTime.now().toIso8601String(),
    });

    try {
      await controller.initialize();
      await controller.play();
    } catch (_) {
      // 坏 URL 会在 initialize 里抛；listener 那边也会捕获到 hasError。
      // 这里什么都不做，让 VideoPlayerReporter 通过 hasError 上报。
    }

    if (!mounted) {
      controller.dispose();
      reporter.detach();
      return;
    }
    setState(() {
      _controller = controller;
      _reporter = reporter;
      _loadingUrl = null;
    });
  }

  Future<void> _teardown() async {
    _reporter?.detach();
    _reporter = null;
    await _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    // 必须成对 detach；否则 listener 随 controller 一起被 GC 时会警告。
    _reporter?.detach();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('VideoPlayerReporter demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: controller?.value.isInitialized == true
                ? controller!.value.aspectRatio
                : 16 / 9,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: controller == null
                  ? const Text('尚未加载', style: TextStyle(color: Colors.white70))
                  : controller.value.isInitialized
                      ? VideoPlayer(controller)
                      : controller.value.hasError
                          ? Text(
                              'ERROR: ${controller.value.errorDescription}',
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            )
                          : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _loadingUrl != null ? null : () => _load(_goodUrl),
            child: const Text('加载可用视频（butterfly.mp4）'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _loadingUrl != null ? null : () => _load(_badUrl),
            child: const Text('加载损坏 URL（触发 playback_error）'),
          ),
          const Divider(),
          OutlinedButton.icon(
            onPressed: controller != null &&
                    controller.value.isInitialized &&
                    controller.value.isPlaying
                ? () => controller.pause()
                : null,
            icon: const Icon(Icons.pause),
            label: const Text('暂停'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller != null &&
                    controller.value.isInitialized &&
                    !controller.value.isPlaying
                ? () => controller.play()
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放'),
          ),
          const Divider(),
          FilledButton.icon(
            onPressed: _reporter == null
                ? null
                : () {
                    _reporter!.reportVisualGlitch(
                      extra: const {'feedback': '用户反馈花屏'},
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('visual_glitch 已上报'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('手动上报 visual_glitch（花屏）'),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：buffer_stall 依赖网络抖动触发，本地网络顺畅时较难复现；'
            'first_frame_timeout 可以通过在弱网代理下加载体现。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
