abstract class BaseNotifier {
  final Function(String) debugPrint;
  final String notifierName;

  BaseNotifier({
    required this.debugPrint,
    required this.notifierName,
  });

  Future<void> sendCrashReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extraData,
  });

  Future<void> sendEvent({
    required String message,
    String? context,
    Map<String, dynamic>? extraData,
  });

  Future<void> sendAppStartup();

  Future<void> testConnection();

  void dispose();

  void log(String message) {
    debugPrint('[$notifierName] $message');
  }
}
