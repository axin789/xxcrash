enum ParseMode {
  html,
  markdown,
  json,
  None,
}
// "HTML"
// "Markdown"
// "MarkdownV2"
extension ParseModeExt on ParseMode {
  /// 发送给接口 / webhook 的字符串值
  String get value {
    switch (this) {
      case ParseMode.html:
        return 'HTML';
      case ParseMode.markdown:
        return 'Markdown';
      case ParseMode.json:
        return 'JSON';
      case ParseMode.None:
        return 'None';
    }
  }
}
