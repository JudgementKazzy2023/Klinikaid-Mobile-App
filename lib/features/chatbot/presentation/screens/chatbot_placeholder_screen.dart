import 'package:flutter/material.dart';

class ChatbotPlaceholderScreen extends StatelessWidget {
  const ChatbotPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text(
          'KlinikAid Chatbot',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
        ),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF9E00FF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF9E00FF).withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 64,
                  color: Color(0xFF9E00FF),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'AI FAQ Chatbot Assistance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Interact with our RAG-grounded chatbot helper for clinics-related FAQs and policies.\n\nComing soon in Phase 5.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.5,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
