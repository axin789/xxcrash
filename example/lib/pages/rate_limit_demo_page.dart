import 'package:flutter/material.dart';
import 'package:xcrash/xcrash.dart';

import '../sender_log.dart';

/// 限频行为的直观演示：同一个 `business:demo_rate_limit` 连打 50 次，
/// 观察 sender 实际收到几条（由 `reportConfigs` 里的起步阈值 + `intervalMs` 决定）。
///
/// main.dart 里把 `business:demo_rate_limit` 起步阈值设为 10，
/// 所以首次放行需要累计 10 次；放行后 60 秒内再打不会再上报，
/// 但 suppressedCount / suppressedContexts 会搭车下次放行的事件。
class RateLimitDemoPage extends StatefulWidget {
  static const route = '/rate-limit';
  const RateLimitDemoPage({super.key});

  @override
  State<RateLimitDemoPage> createState() => _RateLimitDemoPageState();
}

class _RateLimitDemoPageState extends State<RateLimitDemoPage> {
  int _clicks = 0;
  int _sentBefore = 0;
  int _sentNow = 0;

  Future<void> _fireBurst(int times) async {
    _sentBefore = SenderLog.instance.entries.length;
    for (var i = 0; i < times; i++) {
      await XCrashSDK.reportBusinessError(
        scene: 'demo_rate_limit',
        message: 'burst #$i',
        extra: {'i': i},
      );
    }
    if (!mounted) return;
    setState(() {
      _clicks += times;
      _sentNow = SenderLog.instance.entries.length - _sentBefore;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('限频 demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'key = "business:demo_rate_limit"',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('起步阈值 10 · intervalMs 60s'),
                    const Divider(),
                    Text('累计调用次数：$_clicks'),
                    Text('最近一次 burst 里真正到达 sender 的条数：$_sentNow'),
                    const SizedBox(height: 8),
                    Text(
                      '第一次 burst 10 次应该放行 1 条；之后 60s 内再 burst 都会被压制。'
                      '等压制窗口过去再打一次，之前被压住的 context 会出现在新事件的 suppressedContexts 里。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _fireBurst(50),
              child: const Text('一键打 50 次同 key 错误'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _fireBurst(1),
              child: const Text('再打 1 次（观察 suppressedCount 累加）'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/payload-log'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('去看 sender 收到了哪些 payload'),
            ),
          ],
        ),
      ),
    );
  }
}
