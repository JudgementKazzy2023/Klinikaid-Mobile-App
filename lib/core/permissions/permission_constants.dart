class PermissionConstants {
  static const staffManage = 'staff.manage';
  static const rolesManage = 'roles.manage';
  static const rolesRead = 'roles.read';
  static const systemLogsRead = 'system_logs.read';
  static const chatbotLogsRead = 'chatbot_logs.read';
  static const ragDocumentsManage = 'rag_documents.manage';
  static const documentsManage = 'documents.manage';
  static const queueManage = 'queue.manage';
  static const queueManageOwnDept = 'queue.manage.own_dept';
  static const queueRead = 'queue.read';
  static const recordsManage = 'records.manage';
  static const recordsManageOwnDept = 'records.manage.own_dept';
  static const patientsManage = 'patients.manage';
  static const patientsRead = 'patients.read';
  static const profilesManage = 'profiles.manage';
  static const profilesReadStaff = 'profiles.read_staff';
  static const specialistAnalytics = 'specialist.analytics';
  static const specialistPatients = 'specialist.patients';
  static const specialistRecords = 'specialist.records';
  static const storagePatientDocumentsRead = 'storage.patient_documents.read';
  static const chatAccess = 'chat.access';
  static const ocrRowsManageAll = 'ocr_rows.manage.all';
  static const ocrRowsManageOwn = 'ocr_rows.manage.own';

  static const receptionQueue = <String>[
    documentsManage,
    queueManage,
  ];

  static const departmentRecordsAny = <String>[
    recordsManage,
    recordsManageOwnDept,
  ];

  static const specialistAny = <String>[
    specialistAnalytics,
    specialistPatients,
    specialistRecords,
  ];

  static const adminAny = <String>[
    staffManage,
    rolesManage,
    rolesRead,
    systemLogsRead,
    chatbotLogsRead,
    ragDocumentsManage,
    documentsManage,
    queueManage,
    recordsManage,
    recordsManageOwnDept,
    patientsManage,
    patientsRead,
    profilesManage,
    profilesReadStaff,
  ];
}
