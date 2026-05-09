import 'package:flutter/material.dart';
import 'package:xcrash/xcrash.dart';

/// 覆盖 SDK 主动上报类 API 的 demo：
///
/// - `reportApiError` / `reportBusinessError`
/// - 通用 `report`（带 error/stack）
/// - `leaveBreadcrumb` 手动面包屑
/// - `updateHeartbeat` 心跳
class ReportDemoPage extends StatefulWidget {
  static const route = '/report';
  const ReportDemoPage({super.key});

  @override
  State<ReportDemoPage> createState() => _ReportDemoPageState();
}

class _ReportDemoPageState extends State<ReportDemoPage> {
  int _breadcrumbCount = 0;
  String? _lastHeartbeat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主动上报 demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: '便捷入口',
            children: [
              FilledButton.tonal(
                onPressed: _reportApiError,
                child: const Text('reportApiError（/payment/pay 500）'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _reportBusinessError,
                child: const Text('reportBusinessError（login_risk_control）'),
              ),
            ],
          ),
          _Section(
            title: '通用入口 report()',
            children: [
              FilledButton.tonal(
                onPressed: _reportGeneric,
                child: const Text('report(EventType.business, 带 error+stack)'),
              ),
            ],
          ),
          _Section(
            title: '面包屑',
            children: [
              Text('累计已写入：$_breadcrumbCount 条（最多保留 50）'),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _leaveBreadcrumb,
                child: const Text('leaveBreadcrumb（custom）'),
              ),
            ],
          ),
          _Section(
            title: '心跳（native 崩溃兜底）',
            children: [
              Text(
                _lastHeartbeat == null
                    ? '暂未写心跳'
                    : '最近一次心跳：$_lastHeartbeat',
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _updateHeartbeat,
                child: const Text('updateHeartbeat（进入关键动作）'),
              ),
              const SizedBox(height: 4),
              Text(
                '心跳会落盘；如果进程此刻死掉，下次启动 SDK 会合成一条 '
                'suspected_native_crash 带上这段上下文。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reportApiError() async {
    await XCrashSDK.reportApiError(
      path: '/payment/pay',
      method: 'POST',
      statusCode: 500,
      durationMs: 820,
      errno: 'PAY_FAIL',
      extra: const {'orderId': 'o-2026-0001'},
    );
    _snack('reportApiError 已上报');
  }

  Future<void> _reportBusinessError() async {
    await XCrashSDK.reportBusinessError(
      scene: 'login_risk_control',
      message: '风控拒绝登录',
      extra: const {'riskCode': 'R03', 'retry': 2},
    );
    _snack('reportBusinessError 已上报');
  }

  Future<void> _reportGeneric() async {
    try {
      throw StateError('demo generic report');
    } catch (e, s) {
      await XCrashSDK.report(
        type: EventType.business,
        subKey: 'payment_refund_failed',
        severity: Severity.error,
        message: '退款失败',
        context: '/order/refund',
        data: const {'orderId': 'o1', 'amount': 9.9},
        error: e,
        stack: s,
      );
    }
    _snack('通用 report 已上报');
  }

  void _leaveBreadcrumb() {
    XCrashSDK.leaveBreadcrumb(
      category: 'custom',
      level: 'info',
      message: '用户点击领取奖励',
      data: {'taskId': 123, 'ts': DateTime.now().toIso8601String()},
    );
    setState(() => _breadcrumbCount++);
  }

  Future<void> _updateHeartbeat() async {
    final state = {
      'type': 'feature',
      'name': 'photo_export',
      'enteredAt': DateTime.now().toIso8601String(),
    };
    await XCrashSDK.updateHeartbeat(state);
    setState(() => _lastHeartbeat = state.toString());
    _snack('心跳已写入 SharedPreferences');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    );
  }
}
