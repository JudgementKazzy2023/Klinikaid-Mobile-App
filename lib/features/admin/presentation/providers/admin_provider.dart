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

  // Actions
  Future<void> loadDashboard() async {
    _isDashboardLoading = true;
    _dashboardError = null;
    notifyListeners();

    try {
      _dashboardData = await _repository.getDashboardData();
    } catch (e) {
      _dashboardError = e.toString();
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
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

  Future<void> loadSystemEvents({
    String? eventType,
    String? userSearch,
    DateTime? startDate,
    DateTime? endDate,
    String? textSearch,
  }) async {
    _isLogsLoading = true;
    _logsError = null;
    notifyListeners();

    try {
      _systemEvents = await _repository.getSystemEvents(
        eventType: eventType,
        userSearch: userSearch,
        startDate: startDate,
        endDate: endDate,
        textSearch: textSearch,
      );
    } catch (e) {
      _logsError = e.toString();
    } finally {
      _isLogsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadChatbotAudit() async {
    _isChatbotLoading = true;
    _chatbotError = null;
    notifyListeners();

    try {
      final data = await _repository.getChatbotAudit();
      _chatbotLogs = data['logs'] as List<ChatbotLog>;
      _todayQueries = data['todayQueries'] as int;
      _todayTokens = data['todayTokens'] as int;
      _todayCost = data['todayCost'] as double;
    } catch (e) {
      _chatbotError = e.toString();
    } finally {
      _isChatbotLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadApiCost() async {
    _isCostLoading = true;
    _costError = null;
    notifyListeners();

    try {
      final data = await _repository.getApiCostData();
      _costChartData = List<Map<String, dynamic>>.from(data['chartData'] as List);
      _weeklyBreakdown = List<Map<String, dynamic>>.from(data['weeklyBreakdown'] as List);
    } catch (e) {
      _costError = e.toString();
    } finally {
      _isCostLoading = false;
      notifyListeners();
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

  Future<void> loadDepartmentQueue(String department) async {
    _isDeptQueueLoading = true;
    _deptQueueError = null;
    notifyListeners();

    try {
      _deptRepository.adminDepartmentOverride = department;
      _deptQueueEntries = await _deptRepository.getDailyQueue();
    } catch (e) {
      _deptQueueError = e.toString();
    } finally {
      _isDeptQueueLoading = false;
      notifyListeners();
    }
  }
}
