import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/permissions/permission_source.dart';
import '../../../../core/permissions/web_operation_permissions.dart';
import '../../../../core/supabase/paged_read.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../domain/admin_rbac.dart';

// SYNC SOURCE: web constants.ts kGeminiBlendedUsdPer1MTokens. Do not edit without web sync. See Constraint #13.
const double kGeminiBlendedUsdPer1MTokens = 0.63;

/// Rows shown per page in the admin log lists.
///
/// The audit logs grow without bound, so the list shows one page at a time
/// and asks the server for the exact total instead of reading every row.
const int kAdminLogsPageSize = 100;

/// How many users the picker of the log filter offers at once.
///
/// The picker reads a bounded list, so a name never turns into a read of the
/// whole profile table.
const int kAdminLogUserPickerLimit = 20;

/// One page of the system event list.
class SystemEventsPage {
  const SystemEventsPage({required this.logs, required this.total});

  /// The events of this page, newest first.
  final List<SystemLog> logs;

  /// The exact number of events the filter matched.
  ///
  /// Zero when the page was read without a count. A "load more" page keeps
  /// the total of the first page instead of paying for a second count.
  final int total;
}

/// One page of the chatbot audit.
class ChatbotAuditPage {
  const ChatbotAuditPage({
    required this.logs,
    required this.total,
    required this.todayQueries,
    required this.todayTokens,
    required this.todayCost,
  });

  /// The logs of this page, newest first.
  final List<ChatbotLog> logs;

  /// The exact number of logs the table holds.
  ///
  /// Zero when the page was read without a count. A "load more" page keeps
  /// the total of the first page instead of paying for a second count.
  final int total;

  /// The number of chatbot queries of today (Philippine time).
  final int todayQueries;

  /// The tokens the chatbot used today (Philippine time).
  final int todayTokens;

  /// The estimated cost of today's tokens.
  final double todayCost;
}

class AdminRepository {
  AdminRepository({
    SupabaseClient? client,
    this.permissionSource,
  }) : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// The permissions of the signed-in account, when the caller knows them.
  ///
  /// The repository asks it before a read or a write that the web gates on
  /// a permission, so the app does not start a side effect it is not allowed
  /// to make. This is a client-side preflight only: the shared backend checks
  /// the same permissions again on every request, and the server stays the
  /// authority.
  final PermissionSource? permissionSource;

  /// Stops the operation when the account does not hold [required].
  ///
  /// The check runs before the operation starts, never after it.
  void _preflight(String operation, List<String> required) {
    final source = permissionSource;
    if (source == null) return;
    if (source.hasAllPermissions(required)) return;
    throw PermissionDeniedException(operation, required);
  }

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
        // only the ones that fit in the first response. The order is total
        // (the primary key), so a page boundary cannot skip or repeat a row.
        final res5 = await readAllPages(
          _client
              .from('patient_queue')
              .select('id, department')
              .gte('created_at', startOfToday.toIso8601String()),
          uniqueOrderColumn: 'id',
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
  /// The filters are applied by the server, so a match past the first page is
  /// found instead of being filtered out of the rows that were read. [limit]
  /// caps the rows returned (the dashboard's "recent events").
  Future<List<SystemLog>> getSystemEvents({
    String? eventType,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
    int limit = kAdminLogsPageSize,
  }) async {
    try {
      final query = _systemEventsQuery(
        eventType: eventType,
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        textSearch: textSearch,
      );

      final rows = await query.limit(limit);
      return rows.map((json) => SystemLog.fromJson(json)).toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Fetches one page of the system event list and the exact total.
  ///
  /// The list grows without bound, so the screen shows one page at a time and
  /// offers "load more" instead of reading every event. The filters and the
  /// order are the same for every page, so a page continues where the last one
  /// stopped. The count is asked for with the first page only; a "load more"
  /// page keeps the total of the first page.
  Future<SystemEventsPage> getSystemEventsPage({
    String? eventType,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
    int offset = 0,
    int limit = kAdminLogsPageSize,
  }) async {
    try {
      final query = _systemEventsQuery(
        eventType: eventType,
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        textSearch: textSearch,
      );

      final List<Map<String, dynamic>> rows;
      final int total;
      if (offset == 0) {
        final response = await query
            .range(0, limit - 1)
            .count(CountOption.exact);
        rows = response.data;
        total = response.count;
      } else {
        rows = await query.range(offset, offset + limit - 1);
        total = 0;
      }

      return SystemEventsPage(
        logs: rows.map((json) => SystemLog.fromJson(json)).toList(),
        total: total,
      );
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// The system event query with the filters applied and a total order.
  ///
  /// The order is newest first and then the primary key, so two events that
  /// share a timestamp keep a fixed place in the order and a page boundary
  /// cannot skip or repeat one of them.
  PostgrestTransformBuilder<PostgrestList> _systemEventsQuery({
    String? eventType,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
  }) {
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

    // The user filter is the id of one chosen user, the way the web filters
    // it. A term used to be resolved against `profiles` and every match was
    // sent as an id list, which grows with the staff list until the server
    // rejects the url.
    final user = userId?.trim() ?? '';
    if (user.isNotEmpty) {
      query = query.eq('user_id', user);
    }

    return query
        .order('created_at', ascending: false)
        .order('id', ascending: false);
  }

  /// The users whose name matches [term], at most [limit] of them.
  ///
  /// The picker of the log filter asks for a bounded list: the log query
  /// itself takes one id, so the picker must not read the whole profile
  /// table.
  Future<List<Profile>> searchLogUsers(
    String term, {
    int limit = kAdminLogUserPickerLimit,
  }) async {
    try {
      final text = term.trim();
      if (text.isEmpty) return const [];

      final rows = await _client
          .from('profiles')
          .select()
          .ilike('full_name', _containsPattern(text))
          .order('full_name', ascending: true)
          .order('id', ascending: true)
          .limit(limit);

      return rows.map((json) => Profile.fromJson(json)).toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
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

  /// Fetches one page of the chatbot audit and the exact total.
  ///
  /// The audit table grows without bound, so the screen shows one page at a
  /// time and offers "load more" instead of reading every log. The order is
  /// newest first and then the primary key, so two logs that share a
  /// timestamp keep a fixed place in the order and a page boundary cannot skip
  /// or repeat one of them.
  ///
  /// The count is asked for with the first page only; a "load more" page keeps
  /// the total of the first page. Today's statistics are read from the logs of
  /// today, not from the page, so they stay exact while the list is paged.
  Future<ChatbotAuditPage> getChatbotAuditPage({
    int offset = 0,
    int limit = kAdminLogsPageSize,
  }) async {
    try {
      final query = _client
          .from('chatbot_logs')
          .select()
          .order('created_at', ascending: false)
          .order('id', ascending: false);

      final List<Map<String, dynamic>> rows;
      final int total;
      if (offset == 0) {
        final response = await query.range(0, limit - 1).count(CountOption.exact);
        rows = response.data;
        total = response.count;
      } else {
        rows = await query.range(offset, offset + limit - 1);
        total = 0;
      }

      final logs = rows.map((json) => ChatbotLog.fromJson(json)).toList();

      // Today's statistics come from the logs of today, so they do not depend
      // on how many pages of the audit list are on screen.
      var todayQueries = 0;
      var todayTokens = 0;
      if (offset == 0) {
        final today = await readAllPages(
          _client
              .from('chatbot_logs')
              .select('id, created_at, tokens_used')
              .gte('created_at', phtStartOfTodayUtc().toIso8601String())
              .order('created_at', ascending: false),
          uniqueOrderColumn: 'id',
        );
        todayQueries = today.total;
        todayTokens = today.rows.fold<int>(
          0,
          (sum, row) => sum + ((row['tokens_used'] as num?)?.toInt() ?? 0),
        );
      }

      // Cost calculation: blended rate of $0.63 per 1,000,000 tokens
      final double todayCost =
          (todayTokens / 1000000.0) * kGeminiBlendedUsdPer1MTokens;

      return ChatbotAuditPage(
        logs: logs,
        total: total,
        todayQueries: todayQueries,
        todayTokens: todayTokens,
        todayCost: todayCost,
      );
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
      // Paged, so a submission past the server's row cap is still listed, and
      // ordered totally (newest first, then the primary key) so a page
      // boundary cannot skip or repeat a submission.
      final response = await readAllPages(
        _client
            .from('documents')
            .select('*, patient:patients(*), uploader:profiles(*)')
            .order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
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
      // still shows all of them, and ordered totally (newest first, then the
      // primary key) so a page boundary cannot skip or repeat a record.
      final response = await readAllPages(
        _client
            .from('department_records')
            .select('*, patient:patients(*), recorder:profiles(*)')
            .eq('department', department.toLowerCase())
            .order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
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

  /// The staff the clinic holds, without the patients and the administrators.
  ///
  /// Pinned to the permission the web requires for the same read (web:
  /// `GET /api/admin/staff` requires `staff.manage`).
  Future<List<Profile>> getStaffPersonnel() async {
    _preflight('read the staff list', WebOperationPermissions.staffListRead);
    try {
      // Paged, so a staff member past the server's row cap is still listed,
      // and ordered totally (name, then the primary key) so two staff members
      // with the same name keep a fixed place in the order.
      final response = await readAllPages(
        _client
            .from('profiles')
            .select()
            .neq('role', 'patient')
            .neq('role', 'admin')
            .order('full_name', ascending: true),
        uniqueOrderColumn: 'id',
        uniqueOrderAscending: true,
      );

      return response.rows
          .map((json) => Profile.fromJson(json))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// The role catalogue: the roles, the permissions and the mappings.
  ///
  /// Pinned to the permission the web requires for the same read (web: the
  /// `/admin/roles` page and the read-only catalogue the staff form uses
  /// both require `roles.read`).
  Future<AdminRbacCatalog> getRbacCatalog() async {
    _preflight('read the role catalogue', WebOperationPermissions.roleCatalogueRead);
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
}
