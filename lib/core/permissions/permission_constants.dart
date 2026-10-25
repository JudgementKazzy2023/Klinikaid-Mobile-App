/// The permission names the shared backend defines, and the groups the app
/// gates on.
///
/// The names are the ones the shared database holds in its `permissions`
/// table (web: `src/lib/db/schema.sql`), and the groups mirror the web's
/// area gates (web: `src/app/(dashboard)/layout.tsx`) and the permission each
/// web page requires. The mobile app therefore asks for exactly the
/// permissions the web asks for, and the two clients cannot drift apart
/// because they share the same vocabulary.
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

  /// Every permission the shared backend defines.
  ///
  /// This is the vocabulary the app asks the server about: the server decides
  /// which of these names the signed-in account holds, one name at a time.
  static const all = <String>[
    staffManage,
    rolesManage,
    rolesRead,
    systemLogsRead,
    chatbotLogsRead,
    ragDocumentsManage,
    documentsManage,
    queueManage,
    queueManageOwnDept,
    queueRead,
    recordsManage,
    recordsManageOwnDept,
    patientsManage,
    patientsRead,
    profilesManage,
    profilesReadStaff,
    specialistAnalytics,
    specialistPatients,
    specialistRecords,
    storagePatientDocumentsRead,
    chatAccess,
    ocrRowsManageAll,
    ocrRowsManageOwn,
  ];

  /// The permissions that open the admin area.
  ///
  /// Web: `ADMIN_AREA_PERMISSIONS` in `src/app/(dashboard)/layout.tsx`. A
  /// route under `/admin` is unreachable without one of them, the same way
  /// the web turns the request away with a 403.
  static const adminArea = <String>[
    staffManage,
    rolesManage,
    profilesManage,
    systemLogsRead,
    chatbotLogsRead,
    ragDocumentsManage,
  ];

  /// The permissions that open the reception area.
  ///
  /// Web: `RECEPTION_AREA_PERMISSIONS`.
  static const receptionArea = <String>[
    patientsManage,
    documentsManage,
    queueManage,
  ];

  /// The permissions that open the department area.
  ///
  /// Web: `DEPARTMENT_AREA_PERMISSIONS`.
  static const departmentArea = <String>[
    queueManage,
    queueManageOwnDept,
    recordsManage,
    recordsManageOwnDept,
  ];

  /// The permissions that open the specialist area.
  ///
  /// Web: `SPECIALIST_AREA_PERMISSIONS`.
  static const specialistArea = <String>[
    specialistPatients,
    specialistAnalytics,
    specialistRecords,
  ];

  /// The reception queue needs both permissions.
  ///
  /// Web: the `/reception/queue` page requires `documents.manage` and the
  /// sidebar entry that leads to it requires `documents.manage` and
  /// `queue.manage`.
  static const receptionQueue = <String>[
    documentsManage,
    queueManage,
  ];

  /// The department records need one of the two record permissions.
  static const departmentRecordsAny = <String>[
    recordsManage,
    recordsManageOwnDept,
  ];

  /// The department queue needs one of the two queue permissions.
  static const departmentQueueAny = <String>[
    queueManage,
    queueManageOwnDept,
  ];
}
