/// A single camera unit customers can rent standalone (separate from the
/// booth-package "Camera Rental" add-on in [BoothAddOn] — this is for
/// someone who just wants to borrow a camera on its own).
class CameraOption {
  final String id;
  final String name;
  final String description;
  final int dailyRate;

  /// Per-day rate for rentals of 8 days or more (set by Admin on the
  /// Pricing screen — it differs per camera on the rate cards). 0 means
  /// not set, in which case the 5-7 day rate is used.
  final int rate8Plus;

  /// Per-day rate for 5-7 day rentals (set by Admin). 0 = not set, in which
  /// case dailyRate - 100 is used.
  final int rate5to7;
  final String icon; // simple keyword, mapped to an IconData in the UI layer

  /// A `data:` URI (base64 photo) set by Admin on the Pricing screen.
  /// Empty when no photo has been added yet — the UI falls back to the
  /// [icon] keyword above in that case.
  final String imageUrl;

  const CameraOption({
    required this.id,
    required this.name,
    required this.description,
    required this.dailyRate,
    required this.icon,
    this.imageUrl = '',
    this.rate8Plus = 0,
    this.rate5to7 = 0,
  });
}

/// Port-style constant list, matching the pattern of `kPackages` /
/// `kAddOns` in booth_package.dart.
const List<CameraOption> kCameraOptions = [
  CameraOption(
    id: "dslr_basic",
    name: "DSLR Camera Kit",
    description: "Body + kit lens, extra battery, 32GB card",
    dailyRate: 1200,
    icon: "camera",
  ),
  CameraOption(
    id: "mirrorless_pro",
    name: "Mirrorless Pro Kit",
    description: "Full-frame body, 24-70mm lens, tripod",
    dailyRate: 2000,
    icon: "camera_alt",
  ),
  CameraOption(
    id: "instant_bundle",
    name: "Instant Print Bundle",
    description: "Instant camera + 2 film packs",
    dailyRate: 800,
    icon: "photo_camera_front",
  ),
];

/// A rental length the customer can pick at checkout. [dailyRate] on
/// [CameraOption] is the 1-day price, which on the shop's rate cards is
/// "2-4 day rate + ₱50". So:
///   1 day    = dailyRate
///   2-4 days = (dailyRate - 50) per day
///   5-7 days = (dailyRate - 100) per day
/// (e.g. Canon 600D: 499 / 449 / 399 — Kodak FZ55: 299 / 249 / 199).
///   8+ days  = [rate8Plus] per day (per camera; falls back to the 5-7 rate)
class RentalDurationOption {
  final String label;
  final Duration duration;
  const RentalDurationOption(this.label, this.duration);

  int priceFor(int dailyRate, {int rate8Plus = 0, int rate5to7 = 0}) {
    final days = duration.inDays;
    if (days <= 1) return dailyRate;
    final r57 = rate5to7 > 0 ? rate5to7 : dailyRate - 100;
    final int perDay;
    if (days >= 8) {
      perDay = rate8Plus > 0 ? rate8Plus : r57;
    } else if (days >= 5) {
      perDay = r57;
    } else {
      perDay = dailyRate - 50;
    }
    return perDay * days;
  }
}

const List<RentalDurationOption> kRentalDurationOptions = [
  RentalDurationOption("1 day (24 hrs)", Duration(hours: 24)),
  RentalDurationOption("2 days", Duration(hours: 48)),
  RentalDurationOption("3 days", Duration(hours: 72)),
  RentalDurationOption("4 days", Duration(hours: 96)),
  RentalDurationOption("5 days", Duration(hours: 120)),
  RentalDurationOption("6 days", Duration(hours: 144)),
  RentalDurationOption("7 days", Duration(hours: 168)),
  RentalDurationOption("8 days", Duration(hours: 192)),
  RentalDurationOption("10 days", Duration(hours: 240)),
  RentalDurationOption("14 days", Duration(hours: 336)),
];

/// Default pick when a rental screen needs one before the customer has
/// chosen — the original fixed length this feature launched with.
const RentalDurationOption kDefaultRentalDuration = RentalDurationOption("1 day (24 hrs)", Duration(hours: 24));

/// One camera rental — a Firestore `cameraRentals` document. The camera's
/// name/rate are snapshotted at creation (same reasoning as a booking
/// snapshotting its package price) so a later edit on the Pricing screen
/// never rewrites a past rental's history.
class CameraRental {
  final String id;
  final String userId;
  final String cameraId;
  final String cameraName;
  final int dailyRate;
  final int totalPrice;
  final Duration duration;
  final DateTime rentedAt;
  final DateTime dueAt;
  final DateTime? returnedAt;

  const CameraRental({
    required this.id,
    required this.userId,
    required this.cameraId,
    required this.cameraName,
    required this.dailyRate,
    required this.totalPrice,
    required this.duration,
    required this.rentedAt,
    required this.dueAt,
    this.returnedAt,
  });

  bool get isReturned => returnedAt != null;
  bool get isOverdue => !isReturned && DateTime.now().isAfter(dueAt);
}

/// The camera a customer tapped "Message staff about this camera" on. It is
/// handed to the Messages screen, which attaches it to the customer's next
/// message as a camera card so staff see which camera is being asked about.
class CameraChatRef {
  final String id;
  final String name;
  final String subtitle;

  const CameraChatRef({required this.id, required this.name, required this.subtitle});
}
