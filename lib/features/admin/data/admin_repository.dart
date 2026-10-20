import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/supabase/paged_read.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../domain/admin_rbac.dart';

// SYNC SOURCE: web constants.ts kGeminiBlendedUsdPer1MTokens. Do not edit without web sync. See Constraint #13.
const double kGeminiBlendedUsdPer1MTokens = 0.63;

class AdminRepository {
  AdminRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;
  final SupabaseClient _client;

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
        final res1 = await _client
            .from('patient_queue')
            .select('id')
            .gte('created_at', startOfToday.toIso8601String())
            .count(CountOption.exact);
        todayPatientsCount = res1.count;


      // 2. Pending reviews
      int pendingReviewsCount = 0;
        final res2 = await _client
            .from('documents')
            .select('id')
            .eq('status', 'pending')
            .count(CountOption.exact);
        pendingReviewsCount = res2.count;


      // 3. Active staff
      int activeStaffCount = 0;
        final res3 = await _client
            .from('profiles')
            .select('id')
            .eq('is_active', true)
            .neq('role', 'patient')
            .neq('role', 'admin')
            .count(CountOption.exact);
        activeStaffCount = res3.count;


      // 4. Chatbot queries today
      int chatbotQueriesToday = 0;
        final res4 = await _client
            .from('chatbot_logs')
            .select('id')
            .gte('created_at', startOfToday.toIso8601String())
            .count(CountOption.exact);
        chatbotQueriesToday = res4.count;


      // 5. Department workload
      final Map<String, int> workload = {
        'laboratory': 0,
        'imaging': 0,
        'ultrasound': 0,
        'ecg': 0,
      };
        // Paged, so the workload counts every queue entry of the day and not
        // only the ones that fit in the first response.
        final res5 = await readAllPages(
          _client
              .from('patient_queue')
              .select('department')
              .gte('created_at', startOfToday.toIso8601String()),
        );
        for (final row in res5.rows) {
          final dept = row['department'] as String?;
          if (dept != null && workload.containsKey(dept.toLowerCase())) {
            workload[dept.toLowerCase()] = workload[dept.toLowerCase()]! + 1;
          }
        }


      // 6. Recent system events
      List<SystemLog> recentEvents = [];
      String? recentEventsError;
      try {
        recentEvents = await getSystemEvents(limit: 5);
      } catch (_) {
        recentEventsError = 'Recent system events could not be loaded.';
      }

      return {
        'todayPatients': todayPatientsCount,
        'pendingReviews': pendingReviewsCount,
        'activeStaff': activeStaffCount,
        'chatbotQueries': chatbotQueriesToday,
        'departmentWorkload': workload,
        'recentEvents': recentEvents,
        'recentEventsError': recentEventsError,
      };
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Fetches system events, newest first.
  ///
  /// The read is paged so every matching event is reachable instead of only
  /// the ones the server's row cap allowed in one response, and the search
  /// terms are applied by the server so a match past the first page is found.
  /// [limit] caps the rows returned (the dashboard's "recent events"); null
  /// returns every matching event.
  Future<List<SystemLog>> getSystemEvents({
    String? eventType,
    String? userSearch,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
    int? limit,
  }) async {
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

        // The description search is applied by the server: filtering the rows
        // that were read back would only ever see the newest page of events.
        final text = textSearch?.trim() ?? '';
        if (text.isNotEmpty) {
          query = query.ilike('description', _containsPattern(text));
        }

        // The event list carries the user's name and role through a join, so
        // the term is resolved against `profiles` first and the events are
        // then filtered by that id.
        final user = userSearch?.trim() ?? '';
        if (user.isNotEmpty) {
          final userIds = await _matchingProfileIds(user);
          if (userIds.isEmpty) return [];
          query = query.inFilter('user_id', userIds);
        }

        final List<Map<String, dynamic>> rows;
        if (limit != null) {
          final response = await query
              .order('created_at', ascending: false)
              .limit(limit)
              .count(CountOption.exact);
          rows = response.data;
        } else {
          rows = (await readAllPages(
            query.order('created_at', ascending: false),
          )).rows;
        }

        List<SystemLog> logs = rows
            .map((json) => SystemLog.fromJson(json))
            .toList();

        // Perform client-side userSearch and textSearch filtering if needed
        if (userSearch != null && userSearch.isNotEmpty) {
          final search = userSearch.trim().toLowerCase();
          logs = logs.where((l) => l.userName.toLowerCase().contains(search) || l.userRole.toLowerCase().contains(search)).toList();
        }
        if (textSearch != null && textSearch.isNotEmpty) {
          final search = textSearch.trim().toLowerCase();
          logs = logs.where((l) => l.description.toLowerCase().contains(search) || l.eventType.toLowerCase().contains(search)).toList();
        }

        return logs;

    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// The ids of the profiles whose name or role match [term].
  ///
  /// Two reads instead of one `or` filter: a term that contains a comma
  /// would otherwise break the `or` list syntax and fail the whole query.
  Future<List<String>> _matchingProfileIds(String term) async {
    final pattern = _containsPattern(term);
    final byName = await readAllPages(
      _client.from('profiles').select('id').ilike('full_name', pattern),
    );
    final byRole = await readAllPages(
      _client.from('profiles').select('id').ilike('role', pattern),
    );
    final ids = <String>{
      for (final row in byName.rows) row['id'] as String,
      for (final row in byRole.rows) row['id'] as String,
    };
    return ids.toList();
  }

  /// Builds an ILIKE pattern that matches [term] literally anywhere in a column.
  ///
  /// `%` and `_` are LIKE wildcards and `\` is the escape character, so a
  /// search for "100%" must not match every row containing "100".
  String _containsPattern(String term) {
    final escaped = term.replaceAllMapped(
      RegExp(r'[\\%_]'),
      (match) => '\\${match[0]}',
    );
    return '%$escaped%';
  }

  Future<Map<String, dynamic>> getChatbotAudit() async {
    try {
      final startOfToday = phtStartOfTodayUtc();
      
      // Paged, so the audit list and the statistics below cover every log and
      // not only the rows the server's row cap allowed in one response.
      final res = await readAllPages(
        _client.from('chatbot_logs').select().order('created_at', ascending: false),
      );
      final logs = res.rows
          .map((json) => ChatbotLog.fromJson(json)).toList();

      // Compute statistics for today
      final todayLogs = logs.where((log) => log.createdAt.isAfter(startOfToday)).toList();
      final todayQueries = todayLogs.length;
      final todayTokens = todayLogs.fold<int>(0, (sum, log) => sum + log.tokensUsed);
      
      // Cost calculation: blended rate of $0.63 per 1,000,000 tokens
      final double todayCost = (todayTokens / 1000000.0) * kGeminiBlendedUsdPer1MTokens;

      return {
        'logs': logs,
        'total': res.total,
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
      // The RPC requires a UTC cutoff for the 30-day Philippine calendar window.
      final phtNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final now = DateTime.utc(phtNow.year, phtNow.month, phtNow.day);
      final startDate = now.subtract(const Duration(days: 29, hours: 8));
      final result = await _client.rpc('get_daily_token_usage', params: {
        'start_date': startDate.toIso8601String(),
      });
      if (result is! List) throw const FormatException('Invalid usage response');
      final rpcRows = result;
      for (final row in rpcRows) {
        if (row is! Map) throw const FormatException('Invalid usage row');
        final date = row['usage_date'] ?? row['date'];
        final tokens = row['tokens_used'] ?? row['total_tokens'] ?? row['tokens'];
        if (date is! String || DateTime.tryParse(date) == null ||
            tokens is! num || !tokens.isFinite || tokens < 0 ||
            tokens != tokens.truncateToDouble()) {
          throw const FormatException('Invalid usage values');
        }
      }

      final Map<String, int> dailyTokens = {};
      
      // Initialize last 30 days
      for (int i = 29; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        dailyTokens[dateKey] = 0;
      }

      if (rpcRows.isNotEmpty) {
        // Parse daily token usage aggregated from chatbot_logs.
        for (final row in rpcRows) {
          final dateStr = (row['usage_date'] ?? row['date']) as String?;
          final tokens = (row['tokens_used'] ?? row['total_tokens'] ?? row['tokens'] ?? 0) as num;
          if (dateStr != null && dailyTokens.containsKey(dateStr)) {
            dailyTokens[dateStr] = dailyTokens[dateStr]! + tokens.toInt();
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
        final weekStart = phtNow.subtract(Duration(days: (i + 1) * 7));
        final weekEnd = phtNow.subtract(Duration(days: i * 7));
        
        int tokens = 0;
        if (rpcRows.isNotEmpty) {
          dailyTokens.forEach((dateStr, t) {
            try {
              final date = DateTime.parse('${dateStr}T00:00:00Z');
              if (date.isAfter(weekStart) && date.isBefore(weekEnd)) {
                tokens += t;
              }
            } catch (_) {}
          });
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
      // Paged, so a submission past the server's row cap is still listed.
      final response = await readAllPages(
        _client
            .from('documents')
            .select('*, patient:patients(*), uploader:profiles(*)')
            .order('created_at', ascending: false),
      );

      final List<Map<String, dynamic>> result = [];
      for (final doc in response.rows) {
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
      // Paged, so a department with more records than the server's row cap
      // still shows all of them.
      final response = await readAllPages(
        _client
            .from('department_records')
            .select('*, patient:patients(*), recorder:profiles(*)')
            .eq('department', department.toLowerCase())
            .order('created_at', ascending: false),
      );

      return response.rows.map((json) {
        final recordJson = Map<String, dynamic>.from(json);
        // Ensure nesting is preserved or parsed safely in DepartmentRecord
        return DepartmentRecord.fromJson(recordJson);
      }).toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<List<Profile>> getStaffPersonnel() async {
    try {
      // Paged, so a staff member past the server's row cap is still listed.
      final response = await readAllPages(
        _client
            .from('profiles')
            .select()
            .neq('role', 'patient')
            .neq('role', 'admin')
            .order('full_name', ascending: true),
      );

      return response.rows
          .map((json) => Profile.fromJson(json))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  Future<AdminRbacCatalog> getRbacCatalog() async {
    try {
      final rolesResponse = await _client
          .from('roles')
          .select('id, name, description, is_system, base_role')
          .order('is_system', ascending: false)
          .order('name', ascending: true);
      final permissionsResponse = await _client
          .from('permissions')
          .select('id, name, description, module')
          .order('module', ascending: true)
          .order('name', ascending: true);
      final rolePermissionsResponse = await _client
          .from('role_permissions')
          .select('role_id, permission_id');

      final permissions = (permissionsResponse as List)
          .map((json) => AdminPermission.fromJson(json as Map<String, dynamic>))
          .toList();
      final permissionsById = {
        for (final permission in permissions) permission.id: permission,
      };

      final rolePermissionIds = <String, List<String>>{};
      for (final row in rolePermissionsResponse as List) {
        final map = row as Map<String, dynamic>;
        final roleId = map['role_id'] as String?;
        final permissionId = map['permission_id'] as String?;
        if (roleId == null || permissionId == null) continue;
        rolePermissionIds.putIfAbsent(roleId, () => []).add(permissionId);
      }

      final roles = (rolesResponse as List).map((json) {
        final map = json as Map<String, dynamic>;
        final roleId = map['id'] as String;
        final rolePermissions = (rolePermissionIds[roleId] ?? const <String>[])
            .map((permissionId) => permissionsById[permissionId])
            .whereType<AdminPermission>()
            .toList()
          ..sort((a, b) {
            final moduleCompare = a.module.compareTo(b.module);
            if (moduleCompare != 0) return moduleCompare;
            return a.name.compareTo(b.name);
          });
        return AdminRole.fromJson(map, permissions: rolePermissions);
      }).toList();

      return AdminRbacCatalog(roles: roles, permissions: permissions);
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

  Future<Profile> updateStaffProfile({
    required String userId,
    required String fullName,
    required String role,
    required String roleId,
    String? department,
    String? employeeType,
  }) async {
    try {
      final normalizedDept = role == 'department_staff' ? department : null;
      final normalizedEmployeeType = employeeType?.trim();
      final response = await _client
          .from('profiles')
          .update({
            'full_name': fullName.trim(),
            'role': role,
            'role_id': roleId,
            'department': normalizedDept,
            'employee_type': normalizedEmployeeType == null || normalizedEmployeeType.isEmpty
                ? null
                : normalizedEmployeeType,
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

}
