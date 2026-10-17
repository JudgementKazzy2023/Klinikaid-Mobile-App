import 'package:flutter/material.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/models/rag_document.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/patient_queue.dart';
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
  })  : _repository = repository ?? AdminRepository(),
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
  String? _logsError;
  List<SystemLog> _systemEvents = [];
  
  bool _isChatbotLoading = false;
  String? _chatbotError;
  List<ChatbotLog> _chatbotLogs = [];
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

  bool get isRbacLoading => _isRbacLoading;
  String? get rbacError => _rbacError;
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

  bool get isChatbotLoading => _isChatbotLoading;
  String? get chatbotError => _chatbotError;
  List<ChatbotLog> get chatbotLogs => _chatbotLogs;
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
    } catch (e) {
      _rbacError = e.toString();
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

  Future<void> loadSystemEvents({String? eventType, String? userSearch, DateTime? startDate, DateTime? endDate, String? textSearch,}) async {
    final request = ++_logsRequest;
    final isRefresh = _logsHadSuccess;
    _isLogsLoading = true;
    _logsError = null;
    logsState = AdminReadState.loading;
    notifyListeners();
    try {
      final events = await _repository.getSystemEvents(eventType: eventType, userSearch: userSearch, startDate: startDate, endDate: endDate, textSearch: textSearch);
      if (request != _logsRequest) return;
      _systemEvents = events;
      _logsHadSuccess = true;
      logsState = AdminReadState.loaded;
    } catch (e) {
      if (request != _logsRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _systemEvents = []; }
      _logsError = 'Could not load system events. Check your connection or access and retry.';
      logsState = AdminReadState.failed;
    } finally {
      if (request == _logsRequest) {
        _isLogsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadChatbotAudit() async {
    final request = ++_chatbotRequest;
    final isRefresh = _chatbotHadSuccess;
    _isChatbotLoading = true;
    _chatbotError = null;
    chatbotState = AdminReadState.loading;
    notifyListeners();
    try {
      final data = await _repository.getChatbotAudit();
      if (request != _chatbotRequest) return;
      final logs = data['logs'] as List<ChatbotLog>;
      final queries = data['todayQueries'] as int;
      final tokens = data['todayTokens'] as int;
      final cost = data['todayCost'] as double;
      _chatbotLogs = logs; _todayQueries = queries; _todayTokens = tokens; _todayCost = cost;
      _chatbotHadSuccess = true;
      chatbotState = AdminReadState.loaded;
    } catch (e) {
      if (request != _chatbotRequest) return;
      // Initial failures have no prior payload; refresh failures must discard it.
      if (isRefresh) { _chatbotLogs = []; _todayQueries = 0; _todayTokens = 0; _todayCost = 0; }
      _chatbotError = 'Could not load chatbot audit. Check your connection or access and retry.';
      chatbotState = AdminReadState.failed;
    } finally {
      if (request == _chatbotRequest) {
        _isChatbotLoading = false;
        notifyListeners();
      }
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
      _deptQueueEntries = await _deptRepository.getActiveQueue();
    } catch (e) {
      _deptQueueError = e.toString();
    } finally {
      _isDeptQueueLoading = false;
      notifyListeners();
    }
  }
}
