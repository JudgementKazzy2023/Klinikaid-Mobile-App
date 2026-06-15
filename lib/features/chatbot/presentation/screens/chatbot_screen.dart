import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/chatbot_log.dart';
import '../providers/chatbot_provider.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<String> _quickActions = [
    "What are the laboratory hours?",
    "How do I prepare for an ECG?",
    "Fasting for ultrasound?",
    "How much does a CBC cost?",
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KlinikAid Assistant',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'AI Clinic FAQ & Policies',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
            tooltip: 'Clear Chat History',
            onPressed: () {
              context.read<ChatbotProvider>().clearChat();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Chat screen cleared. Logs are saved in database history.'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            },
          ),
        ],
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Consumer<ChatbotProvider>(
        builder: (context, provider, child) {
          // Trigger scroll to bottom on new messages
          if (provider.messages.isNotEmpty) {
            _scrollToBottom();
          }

          return Column(
            children: [
              // Safety & Grounding Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This AI assistant answers administrative questions about hours, prices, and test preparations. It does not provide medical advice or diagnoses.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chat Messages List
              Expanded(
                child: provider.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                        ),
                      )
                    : provider.messages.isEmpty
                        ? _buildEmptyState(provider)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            itemCount: provider.messages.length,
                            itemBuilder: (context, index) {
                              final message = provider.messages[index];
                              return _buildMessageBubble(message, provider);
                            },
                          ),
              ),

              // Error banner if any
              if (provider.errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          provider.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Typing/Thinking indicator
              if (provider.isSending) _buildThinkingIndicator(),

              // Quick Action Chips
              if (provider.messages.isEmpty && !provider.isLoading)
                _buildQuickActions(provider),

              // Message Input Panel
              _buildInputPanel(provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ChatbotProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How can I help you today?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask me about laboratory working hours, prep instructions for ultrasound, testing prices, or document submission guidelines.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMsg msg, ChatbotProvider provider) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Message Body Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Theme.of(context).cardColor : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 16),
                ),
                border: isUser 
                    ? Border.all(color: Theme.of(context).colorScheme.outline, width: 1) 
                    : null,
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isUser ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
            
            // Log/Feedback footer for Bot replies
            if (!isUser) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Was this helpful?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (msg.logId != null) ...[
                    GestureDetector(
                      onTap: () => provider.submitFeedback(msg.logId!, FeedbackType.helpful),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          msg.feedback == FeedbackType.helpful
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined,
                          size: 14,
                          color: msg.feedback == FeedbackType.helpful
                              ? Colors.green
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => provider.submitFeedback(msg.logId!, FeedbackType.unhelpful),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          msg.feedback == FeedbackType.unhelpful
                              ? Icons.thumb_down_rounded
                              : Icons.thumb_down_outlined,
                          size: 14,
                          color: msg.feedback == FeedbackType.unhelpful
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 16, bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Thinking',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ChatbotProvider provider) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickActions.length,
        itemBuilder: (context, index) {
          final action = _quickActions[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              backgroundColor: Theme.of(context).cardColor,
              surfaceTintColor: Colors.transparent,
              side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
              label: Text(
                action,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
              onPressed: () {
                provider.sendMessage(action);
                _scrollToBottom();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputPanel(ChatbotProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _messageController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Type your question here...',
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (text) {
                    if (!provider.isSending) {
                      _sendMessage(provider);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: provider.isSending ? null : () => _sendMessage(provider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(ChatbotProvider provider) async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;

    _messageController.clear();
    await provider.sendMessage(text);
    _scrollToBottom();
  }
}
