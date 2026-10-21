import 'dart:io';
import 'package:flutter/material.dart';
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
  bool _disposed = false;
  /// Bumped by [clearChat]; in-flight work from an older generation is ignored.
  int _generation = 0;
  /// Bumped by each history load, so a stale load never clears the loading
  /// flag owned by a newer one.
  int _loadSeq = 0;
  /// Bumped by each send, so a stale completion never clears the sending
  /// flag owned by a newer send.
  int _sendSeq = 0;
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

  /// Whether late results may still be applied: not disposed, same [generation]
  /// (not invalidated by [clearChat]) and the same authenticated account.
  bool _isActive(String ownerId, int generation) =>
      !_disposed &&
      generation == _generation &&
      SupabaseService.client.auth.currentUser?.id == ownerId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Loads chatbot history for the current authenticated user and maps it to UI messages.
  Future<void> loadHistory() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final ownerId = user.id;
    final generation = _generation;
    final seq = ++_loadSeq;

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final logs = await _logsRepo.getLogsForUser(ownerId);
      if (seq == _loadSeq) _isLoading = false;
      if (!_isActive(ownerId, generation)) return;

      // Map each ChatbotLog row to its own pair of UI messages, oldest first:
      // the user message, then that row's bot response with its own logId and
      // feedback. Rows are never looked up by prompt text, so repeated prompts
      // keep their distinct responses.
      _messages = [
        for (final log in logs.reversed) ...[
          ChatMsg(
            text: log.userMessage,
            isUser: true,
            timestamp: log.createdAt,
          ),
          ChatMsg(
            text: log.botResponse,
            isUser: false,
            logId: log.id,
            feedback: log.feedback,
            timestamp: log.createdAt.add(const Duration(milliseconds: 200)),
          ),
        ],
      ];
      _notify();
    } catch (e) {
      if (seq == _loadSeq) _isLoading = false;
      if (!_isActive(ownerId, generation)) return;
      _errorMessage = FailureMapper.fromException(e).message;
      _notify();
    }
  }

  /// Sends a message via Supabase Edge Function 'chat'.
  Future<bool> sendMessage(String text) async {
    if (text.trim().isEmpty) return false;
    if (_isSending) return false; // reject a duplicate while one is pending

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      _errorMessage = "Session expired. Please log in again.";
      _notify();
      return false;
    }
    final ownerId = user.id;
    final generation = _generation;
    final seq = ++_sendSeq;

    _isSending = true;
    _errorMessage = null;

    // Add user message to UI instantly for natural flow
    final userMsg = ChatMsg(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _notify();

    // Applies a completed send only when this send's session and account are
    // still current; always releases the sending flag for the latest send.
    bool finish(void Function() apply) {
      if (seq == _sendSeq) _isSending = false;
      if (!_isActive(ownerId, generation)) return false;
      apply();
      _notify();
      return true;
    }

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

      return finish(() {
        _messages.add(ChatMsg(
          text: botText,
          isUser: false,
          logId: logId,
          timestamp: DateTime.now(),
        ));
      });
    } on SocketException catch (_) {
      finish(() {
        _errorMessage = "You are currently offline. Please check your network connection.";
        // Remove exactly the optimistic message this send added.
        _messages.remove(userMsg);
      });
      return false;
    } catch (e) {
      final failure = FailureMapper.fromException(e);
      finish(() {
        _errorMessage = failure.message;
        // Remove exactly the optimistic message this send added.
        _messages.remove(userMsg);
      });
      return false;
    }
  }

  /// Updates feedback for a message log.
  Future<void> submitFeedback(int logId, FeedbackType type) async {
    final ownerId = SupabaseService.client.auth.currentUser?.id;
    final generation = _generation;
    try {
      // Find the message in UI state and update optimistically
      final index = _messages.indexWhere((msg) => msg.logId == logId);
      if (index != -1) {
        // Toggle behavior: if already selected, set to null; otherwise set to the feedback
        final currentFeedback = _messages[index].feedback;
        final newFeedback = currentFeedback == type ? null : type;

        _messages[index].feedback = newFeedback;
        _notify();

        // Send to remote database
        await _logsRepo.updateLogFeedback(logId, newFeedback);
      }
    } catch (e) {
      debugPrint('Failed to submit feedback: $e');
      // Revert local state if the DB call failed, but only for the account
      // and session that started it.
      if (ownerId != null && _isActive(ownerId, generation)) {
        await loadHistory();
      }
    }
  }

  /// Clears the chat screen messages and resets session.
  ///
  /// Local-only: no server logs are deleted. Invalidates any in-flight
  /// history load or send so its late result cannot add messages back or
  /// remove state that belongs to the new chat.
  void clearChat() {
    _generation++;
    _isSending = false;
    _isLoading = false;
    _messages.clear();
    _sessionId = UuidGenerator.generateV4();
    _notify();
  }
}
