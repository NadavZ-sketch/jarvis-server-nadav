class UserContext {
  final int memoryCount;
  final int activeProposals;
  final int pendingProposals;

  const UserContext({
    this.memoryCount = 0,
    this.activeProposals = 0,
    this.pendingProposals = 0,
  });
}

class ProposalScoreResult {
  final double score;
  final double impact;
  final double effort;
  final double urgency;
  final double userSignal;
  final double privacyRisk;
  final double confidence;
  final double quickWinRatio;
  final String whyNow;

  const ProposalScoreResult({
    required this.score,
    required this.impact,
    required this.effort,
    required this.urgency,
    required this.userSignal,
    required this.privacyRisk,
    required this.confidence,
    required this.quickWinRatio,
    required this.whyNow,
  });
}

double _toScale5(dynamic value, {double fallback = 3}) {
  final parsed = switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s) ?? fallback,
    _ => fallback,
  };
  if (parsed <= 1.0) {
    return (parsed * 5).clamp(0.0, 5.0).toDouble();
  }
  return parsed.clamp(0.0, 5.0).toDouble();
}

ProposalScoreResult scoreProposal(Map<String, dynamic> proposal, UserContext context) {
  final impact = _toScale5(proposal['impact'], fallback: 3.5);
  final effort = _toScale5(proposal['effort'], fallback: 2.5);
  final urgency = _toScale5(proposal['urgency'], fallback: 3.0);
  final userSignal = _toScale5(proposal['user_signal'] ?? proposal['userSignal'], fallback: 2.5);
  final privacyRisk = _toScale5(proposal['privacy_risk'] ?? proposal['privacyRisk'], fallback: 1.8);
  final confidence = _toScale5(proposal['confidence'], fallback: 3.0);

  const weightImpact = 0.34;
  const weightEffort = 0.20;
  const weightUrgency = 0.16;
  const weightUserSignal = 0.14;
  const weightPrivacyRisk = 0.10;
  const weightConfidence = 0.06;

  final normalizedEffortBenefit = 5 - effort;
  final rawScore =
      (impact * weightImpact) +
      (normalizedEffortBenefit * weightEffort) +
      (urgency * weightUrgency) +
      (userSignal * weightUserSignal) -
      (privacyRisk * weightPrivacyRisk) +
      (confidence * weightConfidence);
  final score = ((rawScore / 5.0) * 100).clamp(0.0, 100.0).toDouble();
  final quickWinRatio = impact / effort.clamp(1.0, 5.0);

  final whyNow = _buildWhyNow(
    impact: impact,
    effort: effort,
    urgency: urgency,
    userSignal: userSignal,
    privacyRisk: privacyRisk,
    confidence: confidence,
    context: context,
  );

  return ProposalScoreResult(
    score: score,
    impact: impact,
    effort: effort,
    urgency: urgency,
    userSignal: userSignal,
    privacyRisk: privacyRisk,
    confidence: confidence,
    quickWinRatio: quickWinRatio,
    whyNow: whyNow,
  );
}

String _buildWhyNow({
  required double impact,
  required double effort,
  required double urgency,
  required double userSignal,
  required double privacyRisk,
  required double confidence,
  required UserContext context,
}) {
  final parts = <String>[];
  if (impact >= 4) parts.add('ההשפעה למשתמש גבוהה');
  if (urgency >= 3.8) parts.add('הצורך דחוף עכשיו');
  if (effort <= 2.4) parts.add('המאמץ נמוך יחסית');
  if (userSignal >= 3.5) parts.add('יש איתות ברור מהרגלי המשתמש');
  if (privacyRisk >= 3.6) parts.add('נדרש תכנון פרטיות לפני ביצוע');
  if (confidence < 2.4) parts.add('כדאי להתחיל כפיילוט קטן');
  if (context.activeProposals == 0) parts.add('אין כרגע יוזמה פעילה ולכן זה זמן טוב להתחיל');

  if (parts.isEmpty) {
    return 'כדאי לקדם עכשיו כדי לייצר ערך מדורג ולשמור על קצב שיפור יציב.';
  }
  return '${parts.take(2).join(' ו')}. מומלץ להתחיל בצעד ראשון קטן וברור.';
}

bool isQuickWin(ProposalScoreResult score, {double minRatio = 1.4}) {
  return score.quickWinRatio >= minRatio;
}
