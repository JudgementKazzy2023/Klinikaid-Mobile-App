import 'permission_constants.dart';

/// The permissions the web requires for an operation, and the mobile entry
/// point that performs it.
///
/// The table is transcribed from the web source (KlinikAid, `06ccce1`):
///
/// | Web operation                                        | Web requires                                  | Mobile entry point                          |
/// |------------------------------------------------------|-----------------------------------------------|---------------------------------------------|
/// | `GET /api/admin/staff` (list staff)                   | `staff.manage`                               | `AdminRepository.getStaffPersonnel`          |
/// | read the role catalogue (roles, permissions, mappings)| `roles.read`                                 | `AdminRepository.getRbacCatalog`             |
/// | `POST /api/admin/staff` (create a staff account)      | `staff.manage`, `roles.read`, `profiles.manage` | web only (no mobile account creation)      |
/// | `PUT /api/admin/staff/[id]` (update a staff member)   | `staff.manage`, `roles.read`, `profiles.manage` | `AdminRepository.updateStaffProfile`       |
/// | `PATCH /api/admin/staff/[id]` (activate/deactivate)   | `staff.manage`, `profiles.manage`            | `AdminRepository.setStaffActive`             |
/// | send a staff password reset email                      | `staff.manage`                               | web only (no mobile reset)                   |
/// | create/update/delete a custom role                    | `roles.manage`                               | web only (the mobile RBAC screen is read-only) |
/// | upload a RAG knowledge document                       | `rag_documents.manage`                       | web only (the mobile upload action is locked)  |
/// | delete a RAG knowledge document                       | `rag_documents.manage`                       | `AdminRepository.deleteRagDocument`          |
///
/// The web checks the permissions of a write *before* it starts the side
/// effect (web: `src/app/api/admin/staff/route.ts` and
/// `src/app/api/admin/staff/[id]/route.ts` preflight `roles.read` and
/// `profiles.manage` before the Auth and profile work starts). The mobile
/// preflights the same set, so the app does not start a write it is not
/// allowed to make.
///
/// Every check here is a client-side preflight only. The shared backend
/// checks the same permissions again on every request, and the server stays
/// the authority: a client that skips or misreads this table gains nothing.
class WebOperationPermissions {
  const WebOperationPermissions._();

  /// Reading the staff list.
  ///
  /// Web: `GET /api/admin/staff` requires `staff.manage`.
  static const staffListRead = <String>[
    PermissionConstants.staffManage,
  ];

  /// Reading the role catalogue.
  ///
  /// Web: the `/admin/roles` page and the read-only catalogue the staff form
  /// uses (`getRolesAction`) both require `roles.read`.
  static const roleCatalogueRead = <String>[
    PermissionConstants.rolesRead,
  ];

  /// Updating a staff member (name, role, department, position titles).
  ///
  /// Web: `PUT /api/admin/staff/[id]` requires `staff.manage`, and
  /// preflights `roles.read` (the role lookup) and `profiles.manage` (the
  /// profile write) before it touches Auth or the profile row.
  static const staffProfileUpdate = <String>[
    PermissionConstants.staffManage,
    PermissionConstants.rolesRead,
    PermissionConstants.profilesManage,
  ];

  /// Activating or deactivating a staff member.
  ///
  /// Web: `PATCH /api/admin/staff/[id]` requires `staff.manage` and
  /// preflights `profiles.manage` (the status write) before it changes the
  /// Auth state.
  static const staffStatusUpdate = <String>[
    PermissionConstants.staffManage,
    PermissionConstants.profilesManage,
  ];

  /// Deleting a RAG knowledge document.
  ///
  /// Web: the `/admin/rag` page and its delete action require
  /// `rag_documents.manage`.
  static const ragDocumentDelete = <String>[
    PermissionConstants.ragDocumentsManage,
  ];
}
