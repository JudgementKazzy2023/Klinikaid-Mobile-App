import 'permission_constants.dart';

/// The permissions the web requires for an operation, and the mobile entry
/// point that performs it, where there is one.
///
/// The table is transcribed from the web source (KlinikAid, `06ccce1`):
///
/// | Web operation                                        | Web requires                                  | Mobile entry point                          |
/// |------------------------------------------------------|-----------------------------------------------|---------------------------------------------|
/// | `GET /api/admin/staff` (list staff)                   | `staff.manage`                               | `AdminRepository.getStaffPersonnel`          |
/// | read the role catalogue (roles, permissions, mappings)| `roles.read`                                 | `AdminRepository.getRbacCatalog`             |
/// | `POST /api/admin/staff` (create a staff account)      | `staff.manage`, `roles.read`, `profiles.manage` | web only (no mobile account creation)      |
/// | `PUT /api/admin/staff/[id]` (update a staff member)   | `staff.manage`, `roles.read`, `profiles.manage` | web only (hands off: Auth, sessions, audit) |
/// | `PATCH /api/admin/staff/[id]` (activate/deactivate)   | `staff.manage`, `profiles.manage`            | web only (hands off: Auth ban, sessions, audit) |
/// | send a staff password reset email                      | `staff.manage`                               | web only (no mobile reset)                   |
/// | create/update/delete a custom role                    | `roles.manage`                               | web only (the mobile RBAC screen is read-only) |
/// | upload a RAG knowledge document                       | `rag_documents.manage`                       | web only (the mobile upload action is locked)  |
/// | delete a RAG knowledge document                       | `rag_documents.manage`                       | web only (hands off: audit record)           |
///
/// The web checks the permissions of a write *before* it starts the side
/// effect (web: `src/app/api/admin/staff/route.ts` and
/// `src/app/api/admin/staff/[id]/route.ts` preflight `roles.read` and
/// `profiles.manage` before the Auth and profile work starts). The app does
/// not perform the staff and knowledge writes above: each needs the service
/// role for Auth, sessions or the audit record, so the app hands them off to
/// the web instead of writing the profile alone.
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

}
