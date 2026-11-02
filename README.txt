Ilagay ang mga file sa kaparehong path sa project mo (palitan ang luma):

  lib/admin/screens/admin_staff_screen.dart     (bagong design)
  lib/admin/screens/admin_profile_screen.dart   (1 linya lang: hindi na binibilang ang archived)
  lib/admin/services/staff_repository.dart
  lib/admin/models/staff_account_record.dart
  firestore.rules        -> pagkatapos: firebase deploy --only firestore:rules

Hindi ko na-compile ito dito (walang Flutter sa environment ko),
kaya i-run ang `flutter analyze` at subukan sa app bago i-deploy ang rules.
