import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../widgets/centered_modal.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../models/camera_rental.dart';
import '../services/auth_service.dart';
import '../services/camera_rental_repository.dart';
import '../services/pricing_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/rental_countdown_timer.dart';
import '../widgets/stream_once.dart';

const Color _kAvailableGreen = Color(0xFF2E7D32);
const Color _kRentedAmber = Color(0xFFB07A2A);

/// "Rent" tab — a live availability board for the shop's cameras.
///
/// Rentals themselves are handled in person (walk-in / inquiry), so this
/// screen's job is to show customers what is free right now, what each
/// camera costs for each rental length, and, for a camera that's out, when
/// it's expected back — then point them to the staff chat or the shop.
/// If a customer does have a rental checked out under their account, its
/// countdown still shows at the top. Returning it happens at the shop:
/// only staff check a camera in (and free it up for the next customer).
///
/// Rendered as the `child` content inside `AppLayoutShell` (tab index 2).
class CameraRentalScreen extends StatefulWidget {
  const CameraRentalScreen({super.key});

  @override
  State<CameraRentalScreen> createState() => _CameraRentalScreenState();
}

class _CameraRentalScreenState extends State<CameraRentalScreen> {
  String? _uid;
  bool _onlyAvailable = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _uid = u?.uid);
    });
  }

  Color _accentText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE57F84) : AppColors.accent;

  IconData _iconFor(String key) {
    switch (key) {
      case 'camera_alt':
        return Icons.camera_alt_rounded;
      case 'photo_camera_front':
        return Icons.photo_camera_front_rounded;
      default:
        return Icons.camera_rounded;
    }
  }

  Uint8List? _photo(String url) => decodeDataUriImage(url);

  /// "today 3:00 PM" / "Oct 4, 3:00 PM", or null when the due time has
  /// already passed (the unit is still out, but nobody can say when).
  String? _backLabel(CameraRental? rental) {
    if (rental == null) return null;
    final due = rental.dueAt;
    final now = DateTime.now();
    if (due.isBefore(now)) return null;
    final sameDay = due.year == now.year && due.month == now.month && due.day == now.day;
    return sameDay ? 'today ${DateFormat('h:mm a').format(due)}' : DateFormat('MMM d, h:mm a').format(due);
  }

  void _openDetails(CameraOption camera, CameraRental? rental) {
    final pageContext = context;
    showDialog<void>(
      context: context,
      builder: (sheetContext) => CenteredModal(color: Colors.transparent, child: _CameraSheet(
        camera: camera,
        photo: _photo(camera.imageUrl),
        icon: _iconFor(camera.icon),
        unavailable: rental != null,
        backLabel: _backLabel(rental),
        onMessageStaff: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(pageContext).pushReplacementNamed(
            '/messages',
            arguments: CameraChatRef(
              id: camera.id,
              name: camera.name,
              subtitle: 'from ${formatPeso(camera.dailyRate)} / day',
            ),
          );
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Camera rentals",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 8),
          Text(
            "See what's available right now, then drop by the shop or message us to rent.",
            style: TextStyle(fontSize: 13.5, height: 1.45, color: AppPalette.textSecondary(context)),
          ),
          const SizedBox(height: 18),
          _buildInfoCard(context),
          const SizedBox(height: 22),
          if (_uid != null) _buildMyRentals(context),
          _buildCatalog(context),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentTint(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accentTint(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: const Icon(Icons.storefront_rounded, size: 20, color: AppColors.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Rent in person", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 3),
                Text(
                  "Pick a camera below to see its rates. Want to make sure it's still free? Message our staff before you come.",
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppPalette.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Countdown card(s) for anything already checked out under this
  /// customer's account. Renders nothing when they have no active rental.
  Widget _buildMyRentals(BuildContext context) {
    return StreamOnce<List<CameraRental>>(
      create: () => CameraRentalRepository.watchActiveRentalsForUser(_uid!),
      identity: _uid,
      builder: (context, snapshot) {
        final active = snapshot.data ?? const <CameraRental>[];
        if (active.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                active.length == 1 ? "Your rental" : "Your rentals (${active.length})",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppPalette.textPrimary(context)),
              ),
              const SizedBox(height: 4),
              Text(
                "Bring it back to the shop when you're done. Our staff will check it in.",
                style: TextStyle(fontSize: 12, height: 1.4, color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 12),
              ...active.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RentalCountdownTimer(
                    dueAt: r.dueAt,
                    totalDuration: r.duration,
                    cameraName: r.cameraName,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalog(BuildContext context) {
    return StreamOnce<List<CameraOption>>(
      create: () => PricingRepository.watchCameraOptions(),
      builder: (context, snapshot) {
        final cameras = (snapshot.data == null || snapshot.data!.isEmpty) ? kCameraOptions : snapshot.data!;
        return StreamOnce<List<CameraRental>>(
          create: () => CameraRentalRepository.watchAllActiveRentals(),
          builder: (context, activeSnapshot) {
            final activeByCamera = <String, CameraRental>{
              for (final r in activeSnapshot.data ?? const <CameraRental>[]) r.cameraId: r,
            };
            final availableCount = cameras.where((c) => !activeByCamera.containsKey(c.id)).length;
            final shown = _onlyAvailable ? cameras.where((c) => !activeByCamera.containsKey(c.id)).toList() : cameras;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "What's available",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 12),
                _buildFilter(context, total: cameras.length, available: availableCount),
                const SizedBox(height: 16),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_empty_rounded, size: 36, color: AppPalette.textMuted(context)),
                        const SizedBox(height: 10),
                        Text(
                          "Every camera is out right now.\nMessage the staff to ask when one is back.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textMuted(context)),
                        ),
                      ],
                    ),
                  )
                else
                  for (final camera in shown) ...[
                    _buildCameraCard(context, camera, activeByCamera[camera.id]),
                    const SizedBox(height: 14),
                  ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFilter(BuildContext context, {required int total, required int available}) {
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppPalette.cardBg(context) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))] : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? _accentText(context) : AppPalette.textMuted(context),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          pill("All ($total)", !_onlyAvailable, () => setState(() => _onlyAvailable = false)),
          pill("Available now ($available)", _onlyAvailable, () => setState(() => _onlyAvailable = true)),
        ],
      ),
    );
  }

  Widget _buildCameraCard(BuildContext context, CameraOption camera, CameraRental? rental) {
    final unavailable = rental != null;
    final photo = _photo(camera.imageUrl);
    final back = _backLabel(rental);

    return Material(
      color: AppPalette.cardBg(context),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => _openDetails(camera, rental),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppPalette.divider(context)),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: _CameraPhoto(photo: photo, icon: _iconFor(camera.icon), unavailable: unavailable, iconSize: 36),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusChip(unavailable: unavailable, backLabel: back),
                    const SizedBox(height: 8),
                    Text(
                      camera.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3, color: AppPalette.textPrimary(context)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      camera.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: AppPalette.textMuted(context)),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: "from ",
                            style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                          ),
                          TextSpan(
                            text: formatPeso(camera.dailyRate),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _accentText(context)),
                          ),
                          TextSpan(
                            text: " / day",
                            style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera photo (or a gradient + icon placeholder), dimmed when rented out.
class _CameraPhoto extends StatelessWidget {
  final Uint8List? photo;
  final IconData icon;
  final bool unavailable;
  final double iconSize;

  const _CameraPhoto({required this.photo, required this.icon, required this.unavailable, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(photo!, fit: BoxFit.cover, cacheWidth: 640),
          if (unavailable) Container(color: Colors.black.withValues(alpha: 0.4)),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: unavailable ? [AppColors.stone400, AppColors.stone500] : [AppColors.accentTint(0.8), AppColors.accent],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: Colors.white.withValues(alpha: 0.75)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool unavailable;
  final String? backLabel;

  const _StatusChip({required this.unavailable, required this.backLabel});

  @override
  Widget build(BuildContext context) {
    final color = unavailable ? _kRentedAmber : _kAvailableGreen;
    final text = !unavailable ? "Available now" : (backLabel != null ? "Rented · back $backLabel" : "Rented out");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Details for one camera: photo, live status, rates for every rental
/// length, and a shortcut to message the staff.
class _CameraSheet extends StatelessWidget {
  final CameraOption camera;
  final Uint8List? photo;
  final IconData icon;
  final bool unavailable;
  final String? backLabel;
  final VoidCallback onMessageStaff;

  const _CameraSheet({
    required this.camera,
    required this.photo,
    required this.icon,
    required this.unavailable,
    required this.backLabel,
    required this.onMessageStaff,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(
        color: AppPalette.bg(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppPalette.divider(context), borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 190,
                  child: _CameraPhoto(photo: photo, icon: icon, unavailable: unavailable, iconSize: 56),
                ),
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: _StatusChip(unavailable: unavailable, backLabel: backLabel)),
              const SizedBox(height: 10),
              Text(
                camera.name,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppPalette.textPrimary(context)),
              ),
              const SizedBox(height: 4),
              Text(
                camera.description,
                style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textSecondary(context)),
              ),
              const SizedBox(height: 20),
              Text(
                "Rental rates",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    for (final (i, tier) in <(String, int)>[
                      ("2-4 days", camera.dailyRate - 50),
                      ("5-7 days", camera.rate5to7 > 0 ? camera.rate5to7 : camera.dailyRate - 100),
                      ("8 days onwards", camera.rate8Plus > 0 ? camera.rate8Plus : (camera.rate5to7 > 0 ? camera.rate5to7 : camera.dailyRate - 100)),
                    ].indexed) ...[
                      if (i > 0) Divider(height: 1, color: AppPalette.divider(context)),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tier.$1,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)),
                            ),
                            Text(
                              "${formatPeso(tier.$2)}/day",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "+${formatPeso(50)} for 1 day rental",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.storefront_rounded, size: 16, color: AppPalette.textMuted(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Rentals are done in person. Drop by the shop, or message our staff first to make sure this camera is ready for you.",
                      style: TextStyle(fontSize: 12, height: 1.45, color: AppPalette.textMuted(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: onMessageStaff,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent, shape: const StadiumBorder()),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text("Message staff about this camera", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}