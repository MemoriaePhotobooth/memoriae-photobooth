class BoothPackage {
  final String id;
  final String name;
  final String duration;
  final int price;
  final List<String> features;

  /// Short line shown on the homepage card. Empty = fall back to features.
  final String description;

  /// A `data:` URI (base64 photo) set by Admin on the Pricing screen.
  /// Empty when no photo has been added yet — callers fall back to a
  /// generic icon in that case.
  final String imageUrl;

  const BoothPackage({
    required this.id,
    required this.name,
    required this.duration,
    required this.price,
    required this.features,
    this.imageUrl = '',
    this.description = '',
  });
}

/// Bundles what should be pre-filled when navigating into the Book tab —
/// e.g. tapping a specific date or package on Home, or submitting the
/// Home search bar. Passed as the `/book` route's arguments.
class BookingIntent {
  final DateTime? date;
  final BoothPackage? package;
  final int? guests;
  const BookingIntent({this.date, this.package, this.guests});
}

/// Port of the `PACKAGES` array.
const List<BoothPackage> kPackages = [
  BoothPackage(
    id: "classic",
    name: "Classic Moments",
    duration: "1 hour",
    price: 2500,
    features: ["Unlimited prints", "Digital copies", "Basic props"],
  ),
  BoothPackage(
    id: "premium",
    name: "Premium Celebration",
    duration: "2 hours",
    price: 4500,
    features: ["Unlimited prints", "Premium props", "Custom backdrop", "Guest book"],
  ),
  BoothPackage(
    id: "deluxe",
    name: "Deluxe Experience",
    duration: "3 hours",
    price: 6500,
    features: ["Everything in Premium", "Dedicated attendant", "Boomerang GIFs", "Video messages"],
  ),
];

/// A single optional add-on a customer can attach to their booking
/// (e.g. an extra camera rental) on top of the chosen package.
class BoothAddOn {
  final String id;
  final String name;
  final String description;
  final int price;

  const BoothAddOn({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
  });
}

/// Available add-ons shown in the booking flow, alongside the packages.
const List<BoothAddOn> kAddOns = [
  BoothAddOn(
    id: "camera_rental",
    name: "Camera Rental",
    description: "Extra DSLR camera + operator for roaming shots",
    price: 1500,
  ),
];

/// Port of the `TIME_SLOTS` array.
const List<String> kTimeSlots = ["10:00 AM", "12:00 PM", "2:00 PM", "4:00 PM", "6:00 PM", "8:00 PM"];

/// Simple ₱ formatter equivalent to `price.toLocaleString()`.
String formatPeso(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final posFromEnd = s.length - i;
    buf.write(s[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
  }
  return '₱$buf';
}
