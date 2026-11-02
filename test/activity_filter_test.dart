import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/admin/models/activity_log_entry.dart';
import 'package:memoriae_photobooth/admin/services/activity_filter.dart';

ActivityLogEntry entry(String action, {String target = '', String email = 'admin@memoriae.ph', String role = 'admin', DateTime? at}) {
  return ActivityLogEntry(
    id: '${action}_$target',
    action: action,
    targetSummary: target,
    actorEmail: email,
    actorRole: role,
    createdAt: at ?? DateTime(2026, 10, 6, 10),
  );
}

void main() {
  final entries = [
    entry('Approved booking', target: 'Classic Moments — Juan Dela Cruz'),
    entry('Checked in rental', target: 'DSLR Camera Kit', email: 'staff@memoriae.ph', role: 'staff'),
    entry('Blocked customer', target: 'Maria Santos'),
    entry('Voided POS sale', target: '#1042', role: 'staff', email: 'staff@memoriae.ph'),
    entry('Approved booking', target: 'Glam Booth — Ana Reyes', at: DateTime(2026, 9, 1)),
  ];

  test('categorises actions', () {
    expect(activityCategoryOf(entries[0]), ActivityCategory.bookings);
    expect(activityCategoryOf(entries[1]), ActivityCategory.rentals);
    expect(activityCategoryOf(entries[2]), ActivityCategory.customers);
    expect(activityCategoryOf(entries[3]), ActivityCategory.other);
  });

  test('no filters returns everything', () {
    expect(filterActivity(entries), hasLength(5));
  });

  test('filters by role', () {
    expect(filterActivity(entries, role: 'staff'), hasLength(2));
  });

  test('filters by category', () {
    final r = filterActivity(entries, category: ActivityCategory.bookings);
    expect(r, hasLength(2));
    expect(r.every((e) => e.action == 'Approved booking'), isTrue);
  });

  test('search matches action, target and actor, ignoring case', () {
    expect(filterActivity(entries, query: 'MARIA'), hasLength(1));
    expect(filterActivity(entries, query: 'camera'), hasLength(1));
    expect(filterActivity(entries, query: 'staff@'), hasLength(2));
    expect(filterActivity(entries, query: 'nobody'), isEmpty);
  });

  test('since drops older entries', () {
    final r = filterActivity(entries, since: DateTime(2026, 10, 1));
    expect(r, hasLength(4));
  });

  test('filters combine', () {
    final r = filterActivity(entries, role: 'staff', category: ActivityCategory.rentals, query: 'dslr');
    expect(r, hasLength(1));
  });
}
