import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/repositories/chatbot_logs_repository.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/uuid_generator.dart';

class ChatMsg {
  final String text;
  final bool isUser;
  final int? logId;
  FeedbackType? feedback;
  final DateTime timestamp;

  ChatMsg({
    required this.text,
    required this.isUser,
    this.logId,
    this.feedback,
    required this.timestamp,
  });
}

class ChatbotProvider extends ChangeNotifier {
  final _logsRepo = ChatbotLogsRepository();

  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  List<ChatMsg> _messages = [];
  late String _sessionId;

  ChatbotProvider() {
    _sessionId = UuidGenerator.generateV4();
    loadHistory();
  }

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  List<ChatMsg> get messages => _messages;
  String get sessionId => _sessionId;

  /// Loads chatbot history for the current authenticated user and maps it to UI messages.
  Future<void> loadHistory() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final logs = await _logsRepo.getLogsForUser(user.id);
      
      // Map ChatbotLog rows to ChatMsg instances in chronological order (oldest first)
      _messages = logs.reversed.map((log) {
        return ChatMsg(
          text: log.userMessage,
          isUser: true,
          timestamp: log.createdAt,
        );
      }).expand((msg) => [
        msg,
        // Since we retrieve user and bot dialogue from a single row,
        // we map it to two UI messages: the user message first, then the bot response
        ChatMsg(
          text: _findBotResponseForMsg(logs, msg.text) ?? "No response generated.",
          isUser: false,
          logId: _findLogIdForMsg(logs, msg.text),
          feedback: _findFeedbackForMsg(logs, msg.text),
          timestamp: msg.timestamp.add(const Duration(milliseconds: 200)),
        )
      ]).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  String? _findBotResponseForMsg(List<ChatbotLog> logs, String userMessage) {
    try {
      return logs.firstWhere((log) => log.userMessage == userMessage).botResponse;
    } catch (_) {
      return null;
    }
  }

  int? _findLogIdForMsg(List<ChatbotLog> logs, String userMessage) {
    try {
      return logs.firstWhere((log) => log.userMessage == userMessage).id;
    } catch (_) {
      return null;
    }
  }

  FeedbackType? _findFeedbackForMsg(List<ChatbotLog> logs, String userMessage) {
    try {
      return logs.firstWhere((log) => log.userMessage == userMessage).feedback;
    } catch (_) {
      return null;
    }
  }

  /// Sends a message via Supabase Edge Function 'chat'.
  Future<bool> sendMessage(String text) async {
    if (text.trim().isEmpty) return false;

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      _errorMessage = "Session expired. Please log in again.";
      notifyListeners();
      return false;
    }

    _isSending = true;
    _errorMessage = null;
    
    // Add user message to UI instantly for natural flow
    final userMsg = ChatMsg(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    notifyListeners();

    try {
      final response = await SupabaseService.client.functions.invoke(
        'chat',
        body: {
          'message': text,
          'session_id': _sessionId,
        },
      );

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Server returned error status ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      final botText = data['response'] as String? ?? "No response generated.";
      final logId = data['log_id'] as int?;

      // Add bot response message
      final botMsg = ChatMsg(
        text: botText,
        isUser: false,
        logId: logId,
        timestamp: DateTime.now(),
      );
      _messages.add(botMsg);

      _isSending = false;
      notifyListeners();
      return true;
    } on SocketException catch (_) {
      _isSending = false;
      _errorMessage = "You are currently offline. Please check your network connection.";
      _messages.removeLast(); // Remove the optimistic user message if call failed
      notifyListeners();
      return false;
    } catch (e) {
      _isSending = false;
      final failure = FailureMapper.fromException(e);
      _errorMessage = failure.message;
      _messages.removeLast(); // Remove optimistic user message on failure
      notifyListeners();
      return false;
    }
  }

  /// Updates feedback for a message log.
  Future<void> submitFeedback(int logId, FeedbackType type) async {
    try {
      // Find the message in UI state and update optimistically
      final index = _messages.indexWhere((msg) => msg.logId == logId);
      if (index != -1) {
        // Toggle behavior: if already selected, set to null; otherwise set to the feedback
        final currentFeedback = _messages[index].feedback;
        final newFeedback = currentFeedback == type ? null : type;
        
        _messages[index].feedback = newFeedback;
        notifyListeners();

        // Send to remote database
        await _logsRepo.updateLogFeedback(logId, newFeedback);
      }
    } catch (e) {
      debugPrint('Failed to submit feedback: $e');
      // Revert local state if DB call failed
      loadHistory();
    }
  }

  /// Clears the chat screen messages and resets session.
  void clearChat() {
    _messages.clear();
    _sessionId = UuidGenerator.generateV4();
    notifyListeners();
  }
}
