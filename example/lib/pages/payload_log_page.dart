import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sender_log.dart';

/// 把 sender 收到的 JSON 字符串直接列出来，解决「不看 IDE console 也能看到上报内容」。
class PayloadLogPage extends StatefulWidget {
  static const route = '/payload-log';
  const PayloadLogPage({super.key});

  @override
  State<PayloadLogPage> createState() => _PayloadLogPageState();
}

class _PayloadLogPageState extends State<PayloadLogPage> {
  @override
  void initState() {
    super.initState();
    SenderLog.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    SenderLog.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = SenderLog.instance.entries.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender payload'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: SenderLog.instance.clear,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('暂无上报。触发一个 demo 按钮后回来看。'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _PayloadTile(entry: entries[i]),
            ),
    );
  }
}

class _PayloadTile extends StatefulWidget {
  final SenderLogEntry entry;
  const _PayloadTile({required this.entry});

  @override
  State<_PayloadTile> createState() => _PayloadTileState();
}

class _PayloadTileState extends State<_PayloadTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final decoded = _tryDecode(widget.entry.content);
    final eventType = decoded?['eventType'] ?? '(unknown)';
    final subKey = decoded?['subKey'] ?? '';
    final severity = decoded?['severity'] ?? '';
    final message = decoded?['message'] ?? '';
    final ts = widget.entry.ts;

    return ExpansionTile(
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      title: Text('$eventType · $subKey',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '[$severity] $message\n'
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _pretty(widget.entry.content),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.entry.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制原始 JSON'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制 JSON'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final parsed = jsonDecode(raw);
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  static String _pretty(String raw) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}
