import 'package:flutter/material.dart';

enum QualityVerdict {
  good,
  marginal,
  poor,
}

enum QualityIssueType {
  blur,
  illegibleText,
  incompleteInfo,
  lowTextDensity,
  other,
}

enum QualityIssueSeverity {
  low,
  medium,
  high,
}

class QualityIssue {
  final QualityIssueType type;
  final QualityIssueSeverity severity;
  final String description;

  QualityIssue({
    required this.type,
    required this.severity,
    required this.description,
  });

  factory QualityIssue.fromJson(Map<String, dynamic> json) {
    return QualityIssue(
      type: _parseType(json['type'] as String?),
      severity: _parseSeverity(json['severity'] as String?),
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'severity': severity.name,
      'description': description,
    };
  }

  static QualityIssueType _parseType(String? value) {
    switch (value?.toLowerCase()) {
      case 'blur':
        return QualityIssueType.blur;
      case 'illegible_text':
      case 'illegibletext':
        return QualityIssueType.illegibleText;
      case 'incomplete_info':
      case 'incompleteinfo':
        return QualityIssueType.incompleteInfo;
      case 'low_text_density':
      case 'lowtextdensity':
        return QualityIssueType.lowTextDensity;
      case 'other':
      default:
        return QualityIssueType.other;
    }
  }

  static QualityIssueSeverity _parseSeverity(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return QualityIssueSeverity.high;
      case 'medium':
        return QualityIssueSeverity.medium;
      case 'low':
      default:
        return QualityIssueSeverity.low;
    }
  }
}

class QualityAssessment {
  final int score;
  final QualityVerdict verdict;
  final List<QualityIssue> issues;

  QualityAssessment({
    required this.score,
    required this.verdict,
    required this.issues,
  });

  factory QualityAssessment.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'] as List<dynamic>? ?? [];
    return QualityAssessment(
      score: json['score'] as int? ?? 50,
      verdict: _parseVerdict(json['verdict'] as String?),
      issues: rawIssues
          .map((e) => QualityIssue.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'verdict': verdict.name,
      'issues': issues.map((e) => e.toJson()).toList(),
    };
  }

  static QualityVerdict _parseVerdict(String? value) {
    switch (value?.toLowerCase()) {
      case 'good':
        return QualityVerdict.good;
      case 'poor':
        return QualityVerdict.poor;
      case 'marginal':
      default:
        return QualityVerdict.marginal;
    }
  }

  Color get verdictColor => score >= 85 ? Colors.green : Colors.orange;

  String get verdictLabel => score >= 85 ? 'Looks good' : 'Low quality';
}
