class ExceptionDecision {
  final bool shouldReport;
  final int suppressedCount;
  final String type;

  ExceptionDecision({
    required this.shouldReport,
    required this.suppressedCount,
    required this.type,
  });
}
