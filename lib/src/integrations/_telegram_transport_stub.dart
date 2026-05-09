// Telegram HTTP 传输层的 **web 空实现**。
//
// SDK 定位是 mobile 为主，web 上只需要能**编译过**就行 —— Telegram 通道
// 在 web 下直接 no-op。若真的有 web→Telegram 的需求，把此文件替换成基于
// `package:http` 或 `dart:html HttpRequest` 的实现即可（条件导入的目标文件
// 就在 telegram_sender.dart 顶部）。

/// 发送 Telegram 消息。Web 上直接静默忽略。
/// 返回值永远是 void；失败语义由调用方决定（当前实现：吞掉）。
Future<void> postTelegram({
  required Uri uri,
  required String body,
  required Duration timeout,
  required String botToken,
}) async {
  // no-op
}
