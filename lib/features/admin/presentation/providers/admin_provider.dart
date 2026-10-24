import 'package:flutter/material.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/models/rag_document.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/permissions/permission_source.dart';
import '../../../../core/repositories/rag_documents_repository.dart';
import '../../../records/domain/record_grouper.dart';
import '../../../department/data/department_repository.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_rbac.dart';

enum AdminReadState { notLoaded, loading, loaded, failed }

class AdminProvider extends ChangeNotifier {
  final AdminRepository _repository;
  final RagDocumentsRepository _ragRepository;
  final DepartmentRepository _deptRepository;

  AdminProvider({
    AdminRepository? repository,
    RagDocumentsRepository? ragRepository,
    DepartmentRepository? deptRepository,
    PermissionSource? permissionSource,
  })  : _repository = repository ??
            AdminRepository(permissionSource: permissionSource),
        _ragRepository = ragRepository ?? RagDocumentsRepository(),
        _deptRepository = deptRepository ?? DepartmentRepository();

  // General Error / Loading
  bool _isDashboardLoading = false;
  String? _dashboardError;
  Map<String, dynamic>? _dashboardData;

  bool _isStaffLoading = false;
  String? _staffError;
  List<Profile> _staffList = [];

  bool _isRbacLoading = false;
  String? _rbacError;
  bool _isRbacLoaded = false;
  List<AdminRole> _rbacRoles = [];
  List<AdminPermission> _rbacPermissions = [];

  bool _isQueueLoading = false;
  String? _queueError;
  List<Map<String, dynamic>> _queueSubmissions = [];

  bool _isRecordsLoading = false;
  String? _recordsError;
  List<GroupedRecord> _groupedRecords = [];
  String _selectedDepartment = 'laboratory';

  // Department Daily Queue state for Admin
  bool _isDeptQueueLoading = false;
  String? _deptQueueError;
  List<PatientQueue> _deptQueueEntries = [];

  bool _isLogsLoading = false;
  bool _isLogsLoadingMore = false;
  String? _logsError;
  String? _logsMoreError;
  List<SystemLog> _systemEvents = [];
  int _systemEventsTotal = 0;

  // The filters of the list on screen, so "load more" repeats the same read.
  String? _logsEventType;
  String? _logsUserId;
  DateTime? _logsStartDate;
  DateTime? _logsEndDate;
  String? _logsTextSearch;
  String? _logsUserSearchError;
  List<Profile> _logUserOptions = [];
  
  bool _isChatbotLoading = false;
  bool _isChatbotLoadingMore = false;
  String? _chatbotError;
  String? _chatbotMoreError;
  List<ChatbotLog> _chatbotLogs = [];
  int _chatbotTotal = 0;
  int _todayQueries = 0;
  int _todayTokens = 0;
  double _todayCost = 0.0;

  bool _isCostLoading = false;
  String? _costError;
  List<Map<String, dynamic>> _costChartData = [];
  List<Map<String, dynamic>> _weeklyBreakdown = [];

  bool _isRagLoading = false;
  String? _ragError;
  List<RagDocument> _ragDocuments = [];

  // Getters
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;
  Map<String, dynamic>? get dashboardData => _dashboardData;

  bool get isStaffLoading => _isStaffLoading;
  String? get staffError => _staffError;
  List<Profile> get staffList => _staffList;

  /// The exact number of staff the server counted.
  int get staffTotal => _staffList.length;

  bool get isRbacLoading => _isRbacLoading;
  String? get rbacError => _rbacError;

  /// True when the role catalogue was read.
  ///
  /// A failed read is not an empty catalogue: the staff form and the role
  /// filter of the registry need the catalogue, and an empty list would read
  /// as a catalogue without roles instead of as a read that failed.
  bool get isRbacLoaded => _isRbacLoaded;
  List<AdminRole> get rbacRoles => _rbacRoles;
  List<AdminPermission> get rbacPermissions => _rbacPermissions;

  bool get isQueueLoading => _isQueueLoading;
  String? get queueError => _queueError;
  List<Map<String, dynamic>> get queueSubmissions => _queueSubmissions;

  bool get isRecordsLoading => _isRecordsLoading;
  String? get recordsError => _recordsError;
  List<GroupedRecord> get groupedRecords => _groupedRecords;
  String get selectedDepartment => _selectedDepartment;

  bool get isDeptQueueLoading => _isDeptQueueLoading;
  String? get deptQueueError => _deptQueueError;
  List<PatientQueue> get deptQueueEntries => _deptQueueEntries;

  bool get isLogsLoading => _isLogsLoading;
  String? get logsError => _logsError;
  List<SystemLog> get systemEvents => _systemEvents;

  /// True while a "load more" page is on its way.
  bool get isLogsLoadingMore => _isLogsLoadingMore;

  /// The error of the last failed "load more"; the rows on screen stay.
  String? get logsMoreError => _logsMoreError;

  /// The exact number of events the current filter matched.
  int get systemEventsTotal => _systemEventsTotal;

  /// The error of the last failed user lookup of the log filter.
  String? get logsUserSearchError => _logsUserSearchError;

  /// The users the picker of the log filter offers.
  List<Profile> get logUserOptions => _logUserOptions;

  /// True when the list holds fewer events than the server counted.
  bool get hasMoreSystemEvents => _systemEvents.length < _systemEventsTotal;

  bool get isChatbotLoading => _isChatbotLoading;
  String? get chatbotError => _chatbotError;
  List<ChatbotLog> get chatbotLogs => _chatbotLogs;

  /// True while a "load more" page is on its way.
  bool get isChatbotLoadingMore => _isChatbotLoadingMore;

  /// The error of the last failed "load more"; the rows on screen stay.
  String? get chatbotMoreError => _chatbotMoreError;

  /// The exact number of chatbot logs the server counted.
  int get chatbotTotal => _chatbotTotal;

  /// True when the list holds fewer logs than the server counted.
  bool get hasMoreChatbotLogs => _chatbotLogs.length < _chatbotTotal;

  int get todayQueries => _todayQueries;
  int get todayTokens => _todayTokens;
  double get todayCost => _todayCost;

  bool get isCostLoading => _isCostLoading;
  String? get costError => _costError;
  List<Map<String, dynamic>> get costChartData => _costChartData;
  List<Map<String, dynamic>> get weeklyBreakdown => _weeklyBreakdown;

  bool get isRagLoading => _isRagLoading;
  String? get ragError => _ragError;
  List<RagDocument> get ragDocuments => _ragDocuments;

  AdminReadState dashboardState = AdminReadState.notLoaded;
  int _dashboardRequest = 0;
  bool _dashboardHadSuccess = false;

  AdminReadState logsState = AdminReadState.notLoaded;
  int _logsRequest = 0;
  bool _logsHadSuccess = false;

  AdminReadState chatbotState = AdminReadState.notLoaded;
  int _chatbotRequest = 0;
  bool _chatbotHadSuccess = false;

  AdminReadState costState = AdminReadState.notLoaded;
  int _costRequest = 0;
  bool _costHadSuccess = false;

  Future<void> retryRecentEvents() async {
    final data = _dashboardData;
    if (data == null) return;
    final request = _dashboardRequest;
    try {
      final events = await _repository.getSystemEvents(limit: 5);
      if (request != _dashboardRequest) return;
      _dashboardData = {...data, 'recentEvents': events, 'recentEventsError': null};
    } catch (_) {
      if (request != _dashboardRequest) return;
      _dashboardData = {...data, 'recentEvents': <SystemLog>[], 'recentEventsError': 'Recent system events could not be loaded.'};
    }
    notifyListeners();
  }

  // Actions
  Future<void> loadDashboard() async {
    final request = ++_dashboardRequest;
    final isRefresh = _dashboardHadSuccess;
    _isDashboardLoading = true;
    _dashboardError = null;
    dashboardState = AdminReadState.loading;
    notifyListeners();
    try {
      final data = await _repository.getDashboardData();
      if (request != _dashboardRequest) return;
      _dashboardData = data;
      _dashboardHadSuccess = true;
      dashboardState = AdminReadState.loaded;
    } catch (e) {
      if (request != _dashboardRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _dashboardData = null; }
      _dashboardError = 'Could not load dashboard. Check your connection or access and retry.';
      dashboardState = AdminReadState.failed;
    } finally {
      if (request == _dashboardRequest) {
        _isDashboardLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadStaff() async {
    _isStaffLoading = true;
    _staffError = null;
    notifyListeners();

    try {
      _staffList = await _repository.getStaffPersonnel();
    } catch (e) {
      _staffError = e.toString();
    } finally {
      _isStaffLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRbacCatalog() async {
    _isRbacLoading = true;
    _rbacError = null;
    notifyListeners();

    try {
      final catalog = await _repository.getRbacCatalog();
      _rbacRoles = catalog.roles;
      _rbacPermissions = catalog.permissions;
      _isRbacLoaded = true;
    } catch (e) {
      _rbacError = e.toString();
      _isRbacLoaded = false;
    } finally {
      _isRbacLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadQueue() async {
    _isQueueLoading = true;
    _queueError = null;
    notifyListeners();

    try {
      _queueSubmissions = await _repository.getAllQueueSubmissions();
    } catch (e) {
      _queueError = e.toString();
    } finally {
      _isQueueLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDepartmentRecords(String department) async {
    _selectedDepartment = department;
    _isRecordsLoading = true;
    _recordsError = null;
    notifyListeners();

    try {
      final records = await _repository.getDepartmentRecords(department);
      // Group records using the existing RecordGrouper
      _groupedRecords = groupRecords(records);
    } catch (e) {
      _recordsError = e.toString();
    } finally {
      _isRecordsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSystemEvents({String? eventType, String? userId, DateTime? startDate, DateTime? endDate, String? textSearch,}) async {
    final request = ++_logsRequest;
    final isRefresh = _logsHadSuccess;
    _isLogsLoading = true;
    _logsError = null;
    _logsMoreError = null;
    logsState = AdminReadState.loading;
    notifyListeners();
    try {
      final page = await _repository.getSystemEventsPage(eventType: eventType, userId: userId, startDate: startDate, endDate: endDate, textSearch: textSearch);
      if (request != _logsRequest) return;
      _systemEvents = page.logs;
      _systemEventsTotal = page.total;
      // The filters of the list on screen, so "load more" repeats this read.
      _logsEventType = eventType;
      _logsUserId = userId;
      _logsStartDate = startDate;
      _logsEndDate = endDate;
      _logsTextSearch = textSearch;
      _logsHadSuccess = true;
      logsState = AdminReadState.loaded;
    } catch (e) {
      if (request != _logsRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _systemEvents = []; _systemEventsTotal = 0; }
      _logsError = 'Could not load system events. Check your connection or access and retry.';
      logsState = AdminReadState.failed;
    } finally {
      if (request == _logsRequest) {
        _isLogsLoading = false;
        notifyListeners();
      }
    }
  }

  /// The users whose name matches [term], at most a bounded number of them.
  ///
  /// The picker of the log filter needs a list to choose from, and the log
  /// query itself takes the id of the chosen user.
  Future<void> searchLogUsers(String term) async {
    try {
      _logUserOptions = await _repository.searchLogUsers(term);
      _logsUserSearchError = null;
    } catch (e) {
      _logUserOptions = [];
      _logsUserSearchError =
          'Could not load the user list. Check your connection and retry.';
    }
    notifyListeners();
  }

  /// Forgets the offered users, so the picker closes after a choice.
  void clearLogUserOptions() {
    if (_logUserOptions.isEmpty) return;
    _logUserOptions = [];
    notifyListeners();
  }

  /// Appends the next page of the system event list.
  ///
  /// The same filters and the same order are used, so the page continues
  /// where the last one stopped.
  Future<void> loadMoreSystemEvents() async {
    if (_isLogsLoading || _isLogsLoadingMore) return;
    if (!hasMoreSystemEvents) return;
    final request = _logsRequest;
    _isLogsLoadingMore = true;
    _logsMoreError = null;
    notifyListeners();
    try {
      final page = await _repository.getSystemEventsPage(
        eventType: _logsEventType,
        userId: _logsUserId,
        startDate: _logsStartDate,
        endDate: _logsEndDate,
        textSearch: _logsTextSearch,
        offset: _systemEvents.length,
      );
      if (request != _logsRequest) return;
      _systemEvents = [..._systemEvents, ...page.logs];
    } catch (e) {
      if (request != _logsRequest) return;
      _logsMoreError = 'Could not load more events. Check your connection and retry.';
    } finally {
      _isLogsLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadChatbotAudit() async {
    final request = ++_chatbotRequest;
    final isRefresh = _chatbotHadSuccess;
    _isChatbotLoading = true;
    _chatbotError = null;
    _chatbotMoreError = null;
    chatbotState = AdminReadState.loading;
    notifyListeners();
    try {
      final page = await _repository.getChatbotAuditPage();
      if (request != _chatbotRequest) return;
      _chatbotLogs = page.logs;
      _chatbotTotal = page.total;
      _todayQueries = page.todayQueries;
      _todayTokens = page.todayTokens;
      _todayCost = page.todayCost;
      _chatbotHadSuccess = true;
      chatbotState = AdminReadState.loaded;
    } catch (e) {
      if (request != _chatbotRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _chatbotLogs = []; _chatbotTotal = 0; _todayQueries = 0; _todayTokens = 0; _todayCost = 0; }
      _chatbotError = 'Could not load chatbot audit. Check your connection or access and retry.';
      chatbotState = AdminReadState.failed;
    } finally {
      if (request == _chatbotRequest) {
        _isChatbotLoading = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page of the chatbot audit.
  Future<void> loadMoreChatbotAudit() async {
    if (_isChatbotLoading || _isChatbotLoadingMore) return;
    if (!hasMoreChatbotLogs) return;
    final request = _chatbotRequest;
    _isChatbotLoadingMore = true;
    _chatbotMoreError = null;
    notifyListeners();
    try {
      final page = await _repository.getChatbotAuditPage(offset: _chatbotLogs.length);
      if (request != _chatbotRequest) return;
      _chatbotLogs = [..._chatbotLogs, ...page.logs];
    } catch (e) {
      if (request != _chatbotRequest) return;
      _chatbotMoreError = 'Could not load more logs. Check your connection and retry.';
    } finally {
      _isChatbotLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadApiCost() async {
    final request = ++_costRequest;
    final isRefresh = _costHadSuccess;
    _isCostLoading = true;
    _costError = null;
    costState = AdminReadState.loading;
    notifyListeners();
    try {
      final data = await _repository.getApiCostData();
      if (request != _costRequest) return;
      final chart = List<Map<String, dynamic>>.from(data['chartData'] as List);
      final weeks = List<Map<String, dynamic>>.from(data['weeklyBreakdown'] as List);
      _costChartData = chart; _weeklyBreakdown = weeks;
      _costHadSuccess = true;
      costState = AdminReadState.loaded;
    } catch (e) {
      if (request != _costRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _costChartData = []; _weeklyBreakdown = []; }
      _costError = 'Could not load API usage. Check your connection or access and retry.';
      costState = AdminReadState.failed;
    } finally {
      if (request == _costRequest) {
        _isCostLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadRag() async {
    _isRagLoading = true;
    _ragError = null;
    notifyListeners();

    try {
      _ragDocuments = await _ragRepository.getRagDocuments();
    } catch (e) {
      _ragError = e.toString();
    } finally {
      _isRagLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteRag(String documentId) async {
    _isRagLoading = true;
    notifyListeners();

    try {
      await _repository.deleteRagDocument(documentId: documentId);
      _ragDocuments.removeWhere((doc) => doc.metadata?['document_id'] == documentId);
    } catch (e) {
      rethrow;
    } finally {
      _isRagLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleStaffActive(String userId, bool isActive) async {
    _isStaffLoading = true;
    _staffError = null;
    notifyListeners();

    try {
      await _repository.setStaffActive(userId: userId, isActive: isActive);
      await loadStaff();
      await loadDashboard();
    } catch (e) {
      _staffError = e.toString();
      rethrow;
    } finally {
      _isStaffLoading = false;
      notifyListeners();
    }
  }

  Future<void> editStaffRole(String userId, String role, String? department) async {
    _isStaffLoading = true;
    _staffError = null;
    notifyListeners();

    try {
      await _repository.updateStaffRole(userId: userId, role: role, department: department);
      await loadStaff();
      await loadDashboard();
    } catch (e) {
      _staffError = e.toString();
      rethrow;
    } finally {
      _isStaffLoading = false;
      notifyListeners();
    }
  }

  Future<void> editStaffProfile({
    required String userId,
    required String fullName,
    required AdminRole selectedRole,
    required String employeeType,
    String? department,
  }) async {
    _isStaffLoading = true;
    _staffError = null;
    notifyListeners();

    try {
      await _repository.updateStaffProfile(
        userId: userId,
        fullName: fullName,
        role: selectedRole.legacyProfileRole,
        roleId: selectedRole.id,
        department: department,
        employeeType: employeeType,
      );
      await loadStaff();
      await loadDashboard();
    } catch (e) {
      _staffError = e.toString();
      rethrow;
    } finally {
      _isStaffLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDepartmentQueue(String department) async {
    _isDeptQueueLoading = true;
    _deptQueueError = null;
    notifyListeners();

    try {
      _deptRepository.adminDepartmentOverride = department;
      final queue = await _deptRepository.getActiveQueue();
      _deptQueueEntries = queue.entries;
    } catch (e) {
      _deptQueueError = e.toString();
    } finally {
      _isDeptQueueLoading = false;
      notifyListeners();
    }
  }
}
