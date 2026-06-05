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
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF9E00FF).withAlpha(30),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF9E00FF).withAlpha(80),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: Color(0xFF9E00FF),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KlinikAid Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    fontFamily: 'Outfit',
                  ),
                ),
                Text(
                  'AI Clinic FAQ & Policies',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
            tooltip: 'Clear Chat History',
            onPressed: () {
              context.read<ChatbotProvider>().clearChat();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat screen cleared. Logs are saved in database history.'),
                  backgroundColor: Color(0xFF0F131D),
                ),
              );
            },
          ),
        ],
        backgroundColor: const Color(0xFF0F131D),
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
                color: const Color(0xFF1E1035),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFE040FB), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This AI assistant answers administrative questions about hours, prices, and test preparations. It does not provide medical advice or diagnoses.',
                        style: TextStyle(
                          color: Color(0xFFE1BEE7),
                          fontSize: 13,
                          height: 1.4,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chat Messages List
              Expanded(
                child: provider.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9E00FF)),
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
                  color: Colors.redAccent.withAlpha(40),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          provider.errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontFamily: 'Outfit',
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
                color: const Color(0xFF9E00FF).withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF9E00FF).withAlpha(40),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: Color(0xFF9E00FF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'How can I help you today?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ask me about laboratory working hours, prep instructions for ultrasound, testing prices, or document submission guidelines.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.5,
                fontFamily: 'Outfit',
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
                color: isUser ? const Color(0xFF9E00FF) : const Color(0xFF0F131D),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 16),
                ),
                border: isUser 
                    ? null 
                    : Border.all(color: Colors.white.withAlpha(10), width: 1),
              ),
              child: Text(
                msg.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            
            // Log/Feedback footer for Bot replies
            if (!isUser) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Was this helpful?',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                      fontFamily: 'Outfit',
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
                              ? const Color(0xFF00E676)
                              : Colors.white30,
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
                              ? const Color(0xFFFF1744)
                              : Colors.white30,
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
          color: const Color(0xFF0F131D),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: Colors.white.withAlpha(10), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Thinking',
              style: TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'Outfit'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF9E00FF).withAlpha(150)),
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
              backgroundColor: const Color(0xFF0F131D),
              surfaceTintColor: Colors.transparent,
              side: BorderSide(color: const Color(0xFF9E00FF).withAlpha(50), width: 1),
              label: Text(
                action,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontFamily: 'Outfit',
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
      decoration: const BoxDecoration(
        color: Color(0xFF0F131D),
        border: Border(
          top: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                  decoration: const InputDecoration(
                    hintText: 'Type your question here...',
                    hintStyle: TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
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
              decoration: const BoxDecoration(
                color: Color(0xFF9E00FF),
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
