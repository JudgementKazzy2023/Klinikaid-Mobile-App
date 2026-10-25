import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'package:klinikaid_mobile/core/models/chatbot_log.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/chatbot/presentation/providers/chatbot_provider.dart';
import 'package:klinikaid_mobile/features/chatbot/presentation/screens/chatbot_screen.dart';

// No Supabase.initialize or platform plugins: every HTTP request is intercepted.

class TestAuth extends GoTrueClient {
  TestAuth() : super(autoRefreshToken: false);

  String? userId;

  @override
  User? get currentUser => userId == null
      ? null
      : User(
          id: userId!,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        );
}

/// Encodes and decodes JSON on the test's own event loop. The default client
/// does it in a background isolate, so a request reached the fake transport
/// after a wall-clock delay that no number of [settle] turns could cover, and
/// the tests failed on a slow CI runner.
class InlineJsonIsolate extends YAJsonIsolate {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<dynamic> decode(String json) async => jsonDecode(json);

  @override
  Future<String> encode(Object? json) async => jsonEncode(json);
}

class TestClient extends SupabaseClient {
  TestClient(http.Client transport, this.fakeAuth)
      : super(
          'https://example.invalid',
          'fake-key',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          isolate: InlineJsonIsolate(),
        );

  final TestAuth fakeAuth;

  @override
  GoTrueClient get auth => fakeAuth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAuth auth;
  late TestClient client;
  late List<http.Request> requests;
  late List<Map<String, Object?>> logsDescending;

  Completer<http.Response>? chatBlocker;
  Completer<http.Response>? logsBlocker;
  Completer<void>? feedbackBlocker;
  Object chatBody = const {'response': 'Bot reply', 'log_id': 42};
  int chatStatus = 200;
  bool offline = false;
  bool feedbackFails = false;

  http.Response jsonResponse(http.Request r, Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: r, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/functions/v1/chat')) {
      if (offline) throw const SocketException('test offline');
      final blocker = chatBlocker;
      chatBlocker = null;
      if (blocker != null) return blocker.future;
      return jsonResponse(request, chatBody, chatStatus);
    }
    if (path.endsWith('/rest/v1/chatbot_logs')) {
      if (request.method == 'PATCH') {
        final blocker = feedbackBlocker;
        feedbackBlocker = null;
        if (blocker != null) await blocker.future;
        if (feedbackFails) {
          return jsonResponse(
              request, {'message': 'test denial', 'code': '42501'}, 500);
        }
        return http.Response('[]', 200,
            request: request, headers: {'content-type': 'application/json'});
      }
      final blocker = logsBlocker;
      logsBlocker = null;
      if (blocker != null) return blocker.future;
      return jsonResponse(request, logsDescending);
    }
    return jsonResponse(request, <Object>[]);
  }

  Map<String, Object?> logJson(
    int id,
    String message,
    String botResponse,
    String createdAt, {
    String? feedback,
  }) =>
      {
        'id': id,
        'user_id': 'user-a',
        'session_id': 'session-1',
        'user_message': message,
        'bot_response': botResponse,
        'tokens_used': 7,
        'feedback': feedback,
        'created_at': createdAt,
      };

  Future<void> settle([int turns = 6]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<http.Request> chatRequests() => requests
      .where((r) => r.url.path.endsWith('/functions/v1/chat'))
      .toList(growable: false);

  List<http.Request> tableWrites() => requests
      .where((r) =>
          r.url.path.endsWith('/rest/v1/chatbot_logs') && r.method != 'GET')
      .toList(growable: false);

  setUp(() {
    requests = [];
    logsDescending = [];
    chatBlocker = null;
    logsBlocker = null;
    feedbackBlocker = null;
    chatBody = const {'response': 'Bot reply', 'log_id': 42};
    chatStatus = 200;
    offline = false;
    feedbackFails = false;
    auth = TestAuth()..userId = 'user-a';
    client = TestClient(MockClient(handle), auth);
    SupabaseService.mockClient = client;
  });

  tearDown(() async {
    SupabaseService.mockClient = null;
    await client.dispose();
    auth.dispose();
  });

  group('history pairing', () {
    test(
        'repeated prompts keep their own response, logId and feedback '
        'in chronological row order', () async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z',
            feedback: 'helpful'),
        logJson(2, 'Other?', 'Answer 2', '2026-01-01T10:00:02Z'),
        logJson(1, 'Hours?', 'Answer 1', '2026-01-01T10:00:01Z'),
      ];
      final provider = ChatbotProvider();
      await settle();

      expect(provider.messages.map((m) => m.text).toList(), [
        'Hours?',
        'Answer 1',
        'Other?',
        'Answer 2',
        'Hours?',
        'Answer 3',
      ]);
      final botMessages = provider.messages.where((m) => !m.isUser).toList();
      expect(botMessages.map((m) => m.logId).toList(), [1, 2, 3]);
      expect(botMessages.map((m) => m.feedback).toList(),
          [null, null, FeedbackType.helpful]);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('history rows for a switched account are not applied', () async {
      logsDescending = [
        logJson(1, 'Hours?', 'Answer 1', '2026-01-01T10:00:01Z'),
      ];
      final blocker = Completer<http.Response>();
      logsBlocker = blocker;
      final provider = ChatbotProvider(); // constructor load is in flight
      auth.userId = 'user-b';
      blocker.complete(
          jsonResponse(http.Request('GET', Uri.parse('x')), logsDescending));
      await settle();

      expect(provider.messages, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });
  });

  group('sendMessage lifecycle', () {
    test('success follows the chat function contract and appends the reply', () async {
      final provider = ChatbotProvider();
      await settle();
      final sessionId = provider.sessionId;

      final ok = await provider.sendMessage('Hi there');

      expect(ok, isTrue);
      expect(provider.isSending, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.messages.last.isUser, isFalse);
      expect(provider.messages.last.text, 'Bot reply');
      expect(provider.messages.last.logId, 42);
      expect(provider.messages.first.text, 'Hi there');
      expect(provider.messages.first.isUser, isTrue);

      expect(chatRequests(), hasLength(1));
      final request = chatRequests().single;
      expect(request.method.toUpperCase(), 'POST');
      expect(jsonDecode(request.body), {'message': 'Hi there', 'session_id': sessionId});
    });

    test('duplicate send while one is pending is rejected', () async {
      final provider = ChatbotProvider();
      await settle();
      final blocker = Completer<http.Response>();
      chatBlocker = blocker;

      final first = provider.sendMessage('One');
      final second = await provider.sendMessage('Two');

      expect(second, isFalse);
      expect(provider.messages.map((m) => m.text).toList(), ['One']);
      await settle();
      expect(chatRequests(), hasLength(1));

      blocker.complete(jsonResponse(http.Request('POST', Uri.parse('x')), chatBody));
      expect(await first, isTrue);
      expect(provider.messages.map((m) => m.text).toList(), ['One', 'Bot reply']);
      expect(chatRequests(), hasLength(1));
    });

    test('failure removes exactly the optimistic message, not unrelated ones', () async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z'),
        logJson(2, 'Other?', 'Answer 2', '2026-01-01T10:00:02Z'),
        logJson(1, 'Hours?', 'Answer 1', '2026-01-01T10:00:01Z'),
      ];
      final provider = ChatbotProvider();
      await settle();
      expect(provider.messages, hasLength(6));

      final blocker = Completer<http.Response>();
      chatBlocker = blocker;
      final failing = provider.sendMessage('Doomed');
      expect(provider.messages, hasLength(7));

      // History reload lands while the send is still pending.
      await provider.loadHistory();
      expect(provider.messages, hasLength(6));

      blocker.complete(jsonResponse(
          http.Request('POST', Uri.parse('x')),
          {'message': 'boom'},
          500));
      expect(await failing, isFalse);

      expect(provider.messages, hasLength(6));
      expect(provider.messages.last.text, 'Answer 3');
      expect(provider.errorMessage, isNotNull);
      expect(provider.isSending, isFalse);
    });

    test('error status surfaces the failure and clears the optimistic message', () async {
      chatStatus = 500;
      chatBody = const {'message': 'boom'};
      final provider = ChatbotProvider();
      await settle();

      expect(await provider.sendMessage('Hi'), isFalse);
      expect(provider.messages, isEmpty);
      expect(provider.errorMessage, isNotNull);
      expect(provider.isSending, isFalse);
    });

    test('empty and whitespace text are rejected without any request', () async {
      final provider = ChatbotProvider();
      await settle();

      expect(await provider.sendMessage(''), isFalse);
      expect(await provider.sendMessage('   '), isFalse);
      expect(provider.messages, isEmpty);
      expect(chatRequests(), isEmpty);
    });

    test('offline send keeps offline message, drops optimistic message, retry works', () async {
      final provider = ChatbotProvider();
      await settle();
      offline = true;

      expect(await provider.sendMessage('Hi'), isFalse);
      expect(
          provider.errorMessage,
          'You are currently offline. Please check your network connection.');
      expect(provider.messages, isEmpty);

      offline = false;
      expect(await provider.sendMessage('Hi again'), isTrue);
      expect(provider.errorMessage, isNull);
      expect(provider.messages.last.text, 'Bot reply');
    });
  });

  group('clear chat', () {
    test('clearChat during a pending send cannot resurrect a late reply', () async {
      final provider = ChatbotProvider();
      await settle();
      final oldSessionId = provider.sessionId;
      final blocker = Completer<http.Response>();
      chatBlocker = blocker;

      final pending = provider.sendMessage('One');
      provider.clearChat();

      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);
      expect(provider.sessionId, isNot(oldSessionId));

      blocker.complete(jsonResponse(http.Request('POST', Uri.parse('x')), chatBody));
      expect(await pending, isFalse);
      expect(provider.messages, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isSending, isFalse);
    });

    test('clearChat during a failing send leaves no residue and never deletes remotely', () async {
      final provider = ChatbotProvider();
      await settle();
      final blocker = Completer<http.Response>();
      chatBlocker = blocker;

      final pending = provider.sendMessage('One');
      provider.clearChat();
      blocker.complete(jsonResponse(
          http.Request('POST', Uri.parse('x')),
          {'message': 'boom'},
          500));
      expect(await pending, isFalse);

      expect(provider.messages, isEmpty);
      expect(provider.errorMessage, isNull);

      // New sends work right after clearing.
      expect(await provider.sendMessage('Two'), isTrue);
      expect(provider.messages.map((m) => m.text).toList(), ['Two', 'Bot reply']);

      // clearChat is local-only: no table writes were issued at any point.
      expect(tableWrites(), isEmpty);
    });
  });

  group('ownership and disposal', () {
    test('logout during a pending send does not apply the late reply', () async {
      final provider = ChatbotProvider();
      await settle();
      final blocker = Completer<http.Response>();
      chatBlocker = blocker;

      final pending = provider.sendMessage('One');
      auth.userId = null; // logout
      blocker.complete(jsonResponse(http.Request('POST', Uri.parse('x')), chatBody));

      expect(await pending, isFalse);
      expect(provider.messages.where((m) => !m.isUser), isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isSending, isFalse);
    });

    test('disposed provider ignores a late completion without notifying', () async {
      final provider = ChatbotProvider();
      await settle();
      final blocker = Completer<http.Response>();
      chatBlocker = blocker;

      final pending = provider.sendMessage('One');
      provider.dispose();
      blocker.complete(jsonResponse(http.Request('POST', Uri.parse('x')), chatBody));

      await expectLater(pending, completion(false));
    });
  });

  group('feedback', () {
    test('toggle targets the exact logId and follows the PATCH contract', () async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z'),
        logJson(1, 'Hours?', 'Answer 1', '2026-01-01T10:00:01Z'),
      ];
      final provider = ChatbotProvider();
      await settle();
      expect(provider.messages.map((m) => m.logId).toList(),
          [null, 1, null, 3]);

      await provider.submitFeedback(3, FeedbackType.helpful);

      expect(provider.messages[3].logId, 3);
      expect(provider.messages[3].feedback, FeedbackType.helpful);
      expect(provider.messages[1].feedback, isNull);
      final patch = tableWrites().single;
      expect(patch.method, 'PATCH');
      expect(patch.url.queryParameters['id'], 'eq.3');
      expect(jsonDecode(patch.body), {'feedback': 'helpful'});

      // Second tap toggles off.
      await provider.submitFeedback(3, FeedbackType.helpful);
      expect(provider.messages[3].feedback, isNull);
      expect(jsonDecode(tableWrites().last.body), {'feedback': null});
    });

    test('failed feedback write reloads history for the current owner', () async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z'),
      ];
      final provider = ChatbotProvider();
      await settle();
      feedbackFails = true;

      await provider.submitFeedback(3, FeedbackType.unhelpful);
      await settle();

      expect(provider.messages[1].feedback, isNull); // reverted by reload
      expect(tableWrites(), hasLength(1));
      expect(
          requests
              .where((r) =>
                  r.method == 'GET' && r.url.path.endsWith('/rest/v1/chatbot_logs')),
          hasLength(2)); // initial load + reload
    });

    test('account switch during a pending feedback write does not reload old-owner data', () async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z'),
      ];
      final provider = ChatbotProvider();
      await settle();
      feedbackFails = true;
      final blocker = Completer<void>();
      feedbackBlocker = blocker;

      final pending = provider.submitFeedback(3, FeedbackType.helpful);
      auth.userId = 'user-b';
      blocker.complete();
      await pending;

      final historyReads = requests
          .where((r) => r.method == 'GET' && r.url.path.endsWith('/rest/v1/chatbot_logs'))
          .length;
      expect(historyReads, 1); // only the initial load; no stale reload
    });
  });

  group('widget', () {
    testWidgets(
        'screen renders distinct replies for repeated prompts and clear chat is local',
        (tester) async {
      logsDescending = [
        logJson(3, 'Hours?', 'Answer 3', '2026-01-01T10:00:03Z',
            feedback: 'helpful'),
        logJson(2, 'Other?', 'Answer 2', '2026-01-01T10:00:02Z'),
        logJson(1, 'Hours?', 'Answer 1', '2026-01-01T10:00:01Z'),
      ];
      final provider = ChatbotProvider();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<ChatbotProvider>.value(
          value: provider,
          child: const ChatbotScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Answer 1'), findsOneWidget);
      expect(find.text('Answer 3'), findsOneWidget);
      expect(find.text('Hours?'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Clear Chat History'));
      await tester.pumpAndSettle();

      expect(find.text('How can I help you today?'), findsOneWidget);
      expect(
          find.text('Chat screen cleared. Logs are saved in database history.'),
          findsOneWidget);
      expect(tableWrites(), isEmpty);
    });
  });
}
