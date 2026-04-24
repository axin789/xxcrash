/// 面包屑：崩溃/错误发生前的一条行为痕迹。
///
/// 典型 category：
/// - `navigation`  页面跳转
/// - `network`     HTTP 请求
/// - `video`       播放器事件
/// - `custom`      业务自定义
class Breadcrumb {
  final int timestampMs;
  final String category;
  final String level; // info / warning / error
  final String message;
  final Map<String, dynamic>? data;

  Breadcrumb({
    required this.category,
    required this.message,
    this.level = 'info',
    this.data,
    int? timestampMs,
  }) : timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'ts': timestampMs,
        'category': category,
        'level': level,
        'message': message,
        if (data != null) 'data': data,
      };
}
