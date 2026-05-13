class TelemetryPolicy {
  static const int standardTtlDays = 30;
  static const int sensitiveTtlDays = 90;

  static const String policySummary = '''
Telemetry Data Policy (mobile)
- What we collect: only event enums/counters (no free user text), compact pseudonymous user id, timestamp, and bounded metadata enums.
- Why we collect: improve UX flows and prioritize product work.
- Retention: standard events 30 days; sensitive flow events up to 90 days.
- Deletion: automatic by TTL, plus explicit user reset from Settings.
''';

  static String ttlForEvent(String eventName) {
    const sensitiveEvents = {'proposal_outcome'};
    return sensitiveEvents.contains(eventName)
        ? '${sensitiveTtlDays}d'
        : '${standardTtlDays}d';
  }
}
