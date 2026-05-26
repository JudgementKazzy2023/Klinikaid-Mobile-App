enum FeedbackType {
  helpful,
  unhelpful;

  static FeedbackType? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'helpful':
        return FeedbackType.helpful;
      case 'unhelpful':
        return FeedbackType.unhelpful;
      default:
        return null;
    }
  }

  String toJsonValue() {
    return name;
  }
}

class ChatbotLog {
  final int id;
  final String? userId;
  final String sessionId;
  final String userMessage;
  final String botResponse;
  final int tokensUsed;
  final FeedbackType? feedback;
  final DateTime createdAt;

  ChatbotLog({
    required this.id,
    this.userId,
    required this.sessionId,
    required this.userMessage,
    required this.botResponse,
    required this.tokensUsed,
    this.feedback,
    required this.createdAt,
  });

  factory ChatbotLog.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final parsedId = rawId is int ? rawId : int.parse(rawId.toString());

    return ChatbotLog(
      id: parsedId,
      userId: json['user_id'] as String?,
      sessionId: json['session_id'] as String? ?? '',
      userMessage: json['user_message'] as String? ?? '',
      botResponse: json['bot_response'] as String? ?? '',
      tokensUsed: json['tokens_used'] as int? ?? 0,
      feedback: FeedbackType.fromString(json['feedback'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'session_id': sessionId,
      'user_message': userMessage,
      'bot_response': botResponse,
      'tokens_used': tokensUsed,
      'feedback': feedback?.toJsonValue(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
