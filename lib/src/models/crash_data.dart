class CrashData {
  final String timestamp;
  final String error;
  final String stackTrace;
  final String? context;
  final Map<String, dynamic>? extraData;
  final String platform;
  final bool debugMode;

  CrashData({
    required this.error,
    required this.stackTrace,
    this.context,
    this.extraData,
    required this.platform,
    required this.debugMode,
  }) : timestamp = DateTime.now().toIso8601String();

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'error': error,
      'stack_trace': stackTrace,
      'context': context,
      'extra_data': extraData,
      'platform': platform,
      'debug_mode': debugMode,
    };
  }

  static CrashData fromJson(Map<String, dynamic> json) {
    return CrashData(
      error: json['error'],
      stackTrace: json['stack_trace'],
      context: json['context'],
      extraData: json['extra_data'],
      platform: json['platform'],
      debugMode: json['debug_mode'],
    );
  }
}
