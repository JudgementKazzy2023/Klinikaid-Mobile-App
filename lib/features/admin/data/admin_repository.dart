import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/supabase/supabase_client.dart';

// SYNC SOURCE: web constants.ts kGeminiBlendedUsdPer1MTokens. Do not edit without web sync. See Constraint #13.
const double kGeminiBlendedUsdPer1MTokens = 0.63;

class AdminRepository {
  final _client = SupabaseService.client;

  DateTime phtStartOfTodayUtc() {
    final phtNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final phtMidnight = DateTime.utc(phtNow.year, phtNow.month, phtNow.day);
    return phtMidnight.subtract(const Duration(hours: 8));
  }

  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      final startOfToday = phtStartOfTodayUtc();
      
      // 1. Today's patients
      int todayPatientsCount = 0;
      try {
        final res = await _client
            .from('patient_queue')
            .select('id')
            .gte('created_at', startOfToday.toIso8601String())
            .count(CountOption.exact);
        todayPatientsCount = res.count;
      } catch (_) {}

      // 2. Pending reviews
      int pendingReviewsCount = 0;
      try {
        final res = await _client
            .from('documents')
            .select('id')
            .eq('status', 'pending')
            .count(CountOption.exact);
        pendingReviewsCount = res.count;
      } catch (_) {}

      // 3. Active staff
      int activeStaffCount = 0;
      try {
        final res = await _client
            .from('profiles')
            .select('id')
            .eq('is_active', true)
            .neq('role', 'patient')
            .neq('role', 'admin')
            .count(CountOption.exact);
        activeStaffCount = res.count;
      } catch (_) {}

      // 4. Chatbot queries today
      int chatbotQueriesToday = 0;
      try {
        final res = await _client
            .from('chatbot_logs')
            .select('id')
            .gte('created_at', startOfToday.toIso8601String())
            .count(CountOption.exact);
        chatbotQueriesToday = res.count;
      } catch (_) {}

      // 5. Department workload
      final Map<String, int> workload = {
        'laboratory': 0,
        'imaging': 0,
        'ultrasound': 0,
        'ecg': 0,
      };
      try {
        final res = await _client
            .from('patient_queue')
            .select('department')
            .gte('created_at', startOfToday.toIso8601String());
        for (final row in res as List) {
          final dept = row['department'] as String?;
          if (dept != null && workload.containsKey(dept.toLowerCase())) {
            workload[dept.toLowerCase()] = workload[dept.toLowerCase()]! + 1;
          }
        }
      } catch (_) {}

      // 6. Recent system events
      List<SystemLog> recentEvents = [];
      try {
        recentEvents = await getSystemEvents(limit: 5);
      } catch (_) {
        recentEvents = _getMockSystemLogs().take(5).toList();
      }

      return {
        'todayPatients': todayPatientsCount,
        'pendingReviews': pendingReviewsCount,
        'activeStaff': activeStaffCount,
        'chatbotQueries': chatbotQueriesToday,
        'departmentWorkload': workload,
        'recentEvents': recentEvents,
      };
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<List<SystemLog>> getSystemEvents({
    String? eventType,
    String? userSearch,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
    int limit = 50,
  }) async {
    try {
      // Query system_logs or fallback to mock
      try {
        var query = _client.from('system_logs').select('*, user:profiles(full_name, role)');
        
        if (eventType != null && eventType.isNotEmpty && eventType != 'All') {
          query = query.eq('event_type', eventType.toLowerCase());
        }
        
        if (startDate != null) {
          query = query.gte('created_at', startDate.toIso8601String());
        }
        if (endDate != null) {
          query = query.lte('created_at', endDate.toIso8601String());
        }

        final response = await query.order('created_at', ascending: false).limit(limit);
        
        List<SystemLog> logs = (response as List)
            .map((json) => SystemLog.fromJson(json as Map<String, dynamic>))
            .toList();

        // Perform client-side userSearch and textSearch filtering if needed
        if (userSearch != null && userSearch.isNotEmpty) {
          final search = userSearch.toLowerCase();
          logs = logs.where((l) => l.userName.toLowerCase().contains(search) || l.userRole.toLowerCase().contains(search)).toList();
        }
        if (textSearch != null && textSearch.isNotEmpty) {
          final search = textSearch.toLowerCase();
          logs = logs.where((l) => l.description.toLowerCase().contains(search) || l.eventType.toLowerCase().contains(search)).toList();
        }

        return logs;
      } catch (_) {
        // Fallback to Mock Logs
        List<SystemLog> logs = _getMockSystemLogs();
        if (eventType != null && eventType.isNotEmpty && eventType != 'All') {
          logs = logs.where((l) => l.eventType.toLowerCase() == eventType.toLowerCase()).toList();
        }
        if (userSearch != null && userSearch.isNotEmpty) {
          final search = userSearch.toLowerCase();
          logs = logs.where((l) => l.userName.toLowerCase().contains(search) || l.userRole.toLowerCase().contains(search)).toList();
        }
        if (textSearch != null && textSearch.isNotEmpty) {
          final search = textSearch.toLowerCase();
          logs = logs.where((l) => l.description.toLowerCase().contains(search)).toList();
        }
        if (startDate != null) {
          logs = logs.where((l) => l.createdAt.isAfter(startDate)).toList();
        }
        if (endDate != null) {
          logs = logs.where((l) => l.createdAt.isBefore(endDate)).toList();
        }
        return logs.take(limit).toList();
      }
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<Map<String, dynamic>> getChatbotAudit() async {
    try {
      final startOfToday = phtStartOfTodayUtc();
      
      // Fetch logs
      List<ChatbotLog> logs = [];
      try {
        final res = await _client
            .from('chatbot_logs')
            .select()
            .order('created_at', ascending: false);
        logs = (res as List)
            .map((json) => ChatbotLog.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (_) {
        logs = _getMockChatbotLogs();
      }

      // Compute statistics for today
      final todayLogs = logs.where((log) => log.createdAt.isAfter(startOfToday)).toList();
      final todayQueries = todayLogs.length;
      final todayTokens = todayLogs.fold<int>(0, (sum, log) => sum + log.tokensUsed);
      
      // Cost calculation: blended rate of $0.63 per 1,000,000 tokens
      final double todayCost = (todayTokens / 1000000.0) * kGeminiBlendedUsdPer1MTokens;

      return {
        'logs': logs,
        'todayQueries': todayQueries,
        'todayTokens': todayTokens,
        'todayCost': todayCost,
      };
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<Map<String, dynamic>> getApiCostData() async {
    try {
      // API cost tracker: Blended rate ($0.63 per 1,000,000 tokens) computed app-side.
      // 30-day token consumption series + weekly cost breakdown.
      // Confirm token source is the RPC get_daily_token_usage (chatbot_logs + system_logs), fallback to chatbot_logs only if RPC fails
      List<dynamic> rpcRows = [];
      try {
        final res = await _client.rpc('get_daily_token_usage');
        if (res != null) {
          rpcRows = res as List<dynamic>;
        }
      } catch (e) {
        print('[AdminRepository getApiCostData] get_daily_token_usage RPC failed, falling back to chatbot_logs: $e');
      }

      List<ChatbotLog> logs = [];
      if (rpcRows.isEmpty) {
        try {
          final res = await _client
              .from('chatbot_logs')
              .select()
              .order('created_at', ascending: false);
          logs = (res as List)
              .map((json) => ChatbotLog.fromJson(json as Map<String, dynamic>))
              .toList();
        } catch (_) {
          logs = _getMockChatbotLogs();
        }
      }

      final now = DateTime.now();
      final Map<String, int> dailyTokens = {};
      
      // Initialize last 30 days
      for (int i = 29; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        dailyTokens[dateKey] = 0;
      }

      if (rpcRows.isNotEmpty) {
        // Parse from daily token usage RPC (chatbot_logs + system_logs)
        for (final row in rpcRows) {
          final dateStr = (row['usage_date'] ?? row['date']) as String?;
          final tokens = (row['tokens_used'] ?? row['total_tokens'] ?? row['tokens'] ?? 0) as num;
          if (dateStr != null && dailyTokens.containsKey(dateStr)) {
            dailyTokens[dateStr] = dailyTokens[dateStr]! + tokens.toInt();
          }
        }
      } else {
        // Fallback: Populate token counts from chatbot_logs
        for (final log in logs) {
          final dateKey = '${log.createdAt.year}-${log.createdAt.month.toString().padLeft(2, '0')}-${log.createdAt.day.toString().padLeft(2, '0')}';
          if (dailyTokens.containsKey(dateKey)) {
            dailyTokens[dateKey] = dailyTokens[dateKey]! + log.tokensUsed;
          }
        }
      }

      // Convert to chart points (chronological order)
      final List<Map<String, dynamic>> chartData = [];
      dailyTokens.forEach((dateStr, tokens) {
        chartData.add({
          'date': dateStr,
          'tokens': tokens,
          'cost': (tokens / 1000000.0) * kGeminiBlendedUsdPer1MTokens,
        });
      });

      // Weekly cost breakdown rows
      final List<Map<String, dynamic>> weeklyBreakdown = [];
      for (int i = 0; i < 4; i++) {
        final weekStart = now.subtract(Duration(days: (i + 1) * 7));
        final weekEnd = now.subtract(Duration(days: i * 7));
        
        int tokens = 0;
        if (rpcRows.isNotEmpty) {
          dailyTokens.forEach((dateStr, t) {
            try {
              final date = DateTime.parse(dateStr);
              if (date.isAfter(weekStart) && date.isBefore(weekEnd)) {
                tokens += t;
              }
            } catch (_) {}
          });
        } else {
          final weekLogs = logs.where((log) => log.createdAt.isAfter(weekStart) && log.createdAt.isBefore(weekEnd)).toList();
          tokens = weekLogs.fold<int>(0, (sum, log) => sum + log.tokensUsed);
        }
        
        final cost = (tokens / 1000000.0) * kGeminiBlendedUsdPer1MTokens;
        final weekLabel = i == 0 
            ? 'This Week' 
            : (i == 1 ? 'Last Week' : '$i Weeks Ago');

        weeklyBreakdown.add({
          'label': weekLabel,
          'tokens': tokens,
          'cost': cost,
          'range': '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}',
        });
      }

      return {
        'chartData': chartData,
        'weeklyBreakdown': weeklyBreakdown,
      };
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<List<Map<String, dynamic>>> getAllQueueSubmissions() async {
    try {
      final response = await _client
          .from('documents')
          .select('*, patient:patients(*), uploader:profiles(*)')
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> result = [];
      for (final doc in response as List) {
        final patient = doc['patient'] as Map<String, dynamic>?;
        final uploader = doc['uploader'] as Map<String, dynamic>?;

        final patientFirstName = patient != null ? (patient['first_name'] as String? ?? '') : '';
        final patientLastName = patient != null ? (patient['last_name'] as String? ?? '') : '';
        final patientName = '$patientFirstName $patientLastName'.trim();

        result.add({
          'id': doc['id'] as String,
          'patientId': doc['patient_id'] as String?,
          'patientName': patientName.isNotEmpty ? patientName : 'Unknown Patient',
          'fileName': doc['file_name'] as String? ?? 'document.pdf',
          'fileType': doc['file_type'] as String? ?? 'PDF',
          'status': doc['status'] as String? ?? 'pending',
          'createdAt': DateTime.parse(doc['created_at'] as String),
          'uploadedBy': uploader != null ? (uploader['full_name'] as String? ?? 'System') : 'System',
        });
      }
      return result;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<List<DepartmentRecord>> getDepartmentRecords(String department) async {
    try {
      // Query cross-department records; Admin can read ANY department.
      final response = await _client
          .from('department_records')
          .select('*, patient:patients(*), recorder:profiles(*)')
          .eq('department', department.toLowerCase())
          .order('created_at', ascending: false);

      return (response as List).map((json) {
        final recordJson = Map<String, dynamic>.from(json as Map);
        // Ensure nesting is preserved or parsed safely in DepartmentRecord
        return DepartmentRecord.fromJson(recordJson);
      }).toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<List<Profile>> getStaffPersonnel() async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .neq('role', 'patient')
          .neq('role', 'admin')
          .order('full_name', ascending: true);

      return (response as List)
          .map((json) => Profile.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<Profile> setStaffActive({
    required String userId,
    required bool isActive,
  }) async {
    try {
      final response = await _client
          .from('profiles')
          .update({'is_active': isActive})
          .eq('id', userId)
          .select()
          .single();

      return Profile.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<Profile> updateStaffRole({
    required String userId,
    required String role,
    String? department,
  }) async {
    try {
      // Normalize department: if role is not department_staff, must be null
      final normalizedDept = role == 'department_staff' ? department : null;
      final response = await _client
          .from('profiles')
          .update({
            'role': role,
            'department': normalizedDept,
          })
          .eq('id', userId)
          .select()
          .single();

      return Profile.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<void> deleteRagDocument({required String documentId}) async {
    try {
      await _client
          .from('rag_documents')
          .delete()
          .eq('metadata->>document_id', documentId);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  // --- MOCK DATA FOR SAFETY FALLBACKS ---

  List<SystemLog> _getMockSystemLogs() {
    final now = DateTime.now();
    return [
      SystemLog(
        id: '1',
        createdAt: now.subtract(const Duration(minutes: 5)),
        userName: 'Admin User',
        userRole: 'admin',
        eventType: 'Security',
        description: 'MFA setup completed successfully for admin account.',
        ipAddress: '192.168.1.50',
      ),
      SystemLog(
        id: '2',
        createdAt: now.subtract(const Duration(hours: 1)),
        userName: 'Alice Staff',
        userRole: 'receptionist',
        eventType: 'Authentication',
        description: 'User login successful via mobile app.',
        ipAddress: '192.168.1.100',
      ),
      SystemLog(
        id: '3',
        createdAt: now.subtract(const Duration(hours: 3)),
        userName: 'Bob Specialist',
        userRole: 'medical_specialist',
        eventType: 'Data Access',
        description: 'Specialist loaded diagnostic history for patient PAT-8841.',
        ipAddress: '192.168.1.112',
      ),
      SystemLog(
        id: '4',
        createdAt: now.subtract(const Duration(hours: 6)),
        userName: 'System Bot',
        userRole: 'system',
        eventType: 'AI Model',
        description: 'AI validated and extracted OCR text from submitted PDF document.',
        ipAddress: '127.0.0.1',
      ),
      SystemLog(
        id: '5',
        createdAt: now.subtract(const Duration(days: 1)),
        userName: 'Super Admin',
        userRole: 'admin',
        eventType: 'Configuration',
        description: 'RAG knowledge base document "klinikaid_guide_v2.pdf" uploaded and indexed.',
        ipAddress: '202.122.50.8',
      ),
    ];
  }

  List<ChatbotLog> _getMockChatbotLogs() {
    final now = DateTime.now();
    return [
      ChatbotLog(
        id: 1,
        userId: 'patient-1',
        sessionId: 'session-a',
        userMessage: 'What is the preparation for a lipid profile test?',
        botResponse: 'Fast for 9-12 hours prior to the blood draw. Water is permitted.',
        tokensUsed: 250,
        feedback: FeedbackType.helpful,
        createdAt: now.subtract(const Duration(minutes: 10)),
      ),
      ChatbotLog(
        id: 2,
        userId: 'patient-2',
        sessionId: 'session-b',
        userMessage: 'How can I view my ultrasound report?',
        botResponse: 'Navigate to the "Records" tab in your mobile app and select the ultrasound entry.',
        tokensUsed: 180,
        feedback: null,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      ChatbotLog(
        id: 3,
        userId: 'patient-3',
        sessionId: 'session-c',
        userMessage: 'Does KlinikAid offer ECG services on weekends?',
        botResponse: 'Yes, our clinic is open for ECG services on Saturday from 8:00 AM to 5:00 PM.',
        tokensUsed: 310,
        feedback: FeedbackType.unhelpful,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      ChatbotLog(
        id: 4,
        userId: 'patient-1',
        sessionId: 'session-a2',
        userMessage: 'What are normal levels of blood pressure?',
        botResponse: 'Normal blood pressure is usually defined as systolic below 120 and diastolic below 80 mmHg.',
        tokensUsed: 420,
        feedback: FeedbackType.helpful,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }
}
