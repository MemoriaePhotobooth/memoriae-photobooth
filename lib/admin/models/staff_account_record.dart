/// The two employee roles managed on the Admin > Staff screen: a Staff
/// account gets day-to-day operations only; an Admin account gets full
/// access to the Admin app. Which collection a person's access doc lives
/// in (`staff` or `admins`) is what actually decides which app they can
/// sign in to.
enum AccessRole { staff, admin }

/// What the Staff screen shows as a person's status.
///  - [active]   can sign in
///  - [inactive] locked out for now, can be reactivated
///  - [archived] removed from the everyday list (and locked out), but the
///               record is kept so it can be restored
enum AccountStatus { active, inactive, archived }

/// Plain data class for a staff/admin account, as managed from the
/// Admin > Staff screen (backed by `staff/{uid}` and `admins/{uid}`).
class StaffAccountRecord {
  final String id;
  final String name;
  final String email;
  final AccessRole role;
  final bool active;
  final bool archived;
  final DateTime? createdAt;

  const StaffAccountRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
    this.archived = false,
    this.createdAt,
  });

  /// Archived wins over inactive: an archived account is always also
  /// locked out (see StaffRepository.archive), but it should read as
  /// "Archived", not "Inactive".
  AccountStatus get status {
    if (archived) return AccountStatus.archived;
    return active ? AccountStatus.active : AccountStatus.inactive;
  }

  StaffAccountRecord copyWith({AccessRole? role, bool? active, bool? archived}) {
    return StaffAccountRecord(
      id: id,
      name: name,
      email: email,
      role: role ?? this.role,
      active: active ?? this.active,
      archived: archived ?? this.archived,
      createdAt: createdAt,
    );
  }
}
