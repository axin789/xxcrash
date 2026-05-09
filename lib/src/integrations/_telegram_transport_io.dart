// Telegram HTTP 传输层的 **native 实现**（Android/iOS/macOS/Windows/Linux）。
//
// `telegram_sender.dart` 顶部用 `if (dart.library.io)` 把它挑出来；
// web 上会被替换成 `_telegram_transport_stub.dart`。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 发送 Telegram 消息。任何异常都被吞掉，只 debugPrint（scrub 过 token）。
Future<void> postTelegram({
  required Uri uri,
  required String body,
  required Duration timeout,
  required String botToken,
}) async {
  String scrub(String s) =>
      botToken.isEmpty ? s : s.replaceAll(botToken, '***');

  // `HttpClient.connectionTimeout` 只覆盖 TCP/TLS 握手阶段；之后服务端
  // 接受连接但慢响应（甚至完全 hang）会让 `req.close()` / `.join()` 阻塞
  // 远超 `timeout`，并拖累主上报通道（report() 里 Future.wait 必须等它）。
  // 给每一阶段都套 `.timeout(...)` 兜底。
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.postUrl(uri).timeout(timeout);
    req.headers.set('Content-Type', 'application/json; charset=utf-8');
    req.write(body);
    final res = await req.close().timeout(timeout);
    final respBody =
        await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode >= 300) {
      // Telegram 的 4xx 响应体常包含完整 URL 回显（带 token），先 scrub 再落日志。
      debugPrint('[Telegram] HTTP ${res.statusCode}: ${scrub(respBody)}');
    }
  } catch (e) {
    // HttpException.toString() 在部分 Dart 版本里会把 uri（含 token）带进来。
    // TimeoutException 也走这里。
    debugPrint('[Telegram] send failed: ${scrub(e.toString())}');
  } finally {
    client.close(force: true);
  }
}
