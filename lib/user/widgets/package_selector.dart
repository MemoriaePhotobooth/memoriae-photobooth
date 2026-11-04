import 'package:flutter/material.dart';
import '../models/booth_package.dart';
import '../services/pricing_repository.dart' show decodeDataUriImage;
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Port of `PackageSelector` — now a "Spotlight"-style swipeable carousel
/// (one big card per package, peeking neighbours, dot indicator) instead
/// of a stacked vertical list.
class PackageSelector extends StatefulWidget {
  final List<BoothPackage> packages;
  final BoothPackage? selectedPkg;
  final ValueChanged<BoothPackage> onSelect;

  const PackageSelector({super.key, required this.packages, required this.selectedPkg, required this.onSelect});

  @override
  State<PackageSelector> createState() => _PackageSelectorState();
}

class _PackageSelectorState extends State<PackageSelector> {
  late final PageController _controller;
  // `_page` is the *real* package index (0..n-1) used for the dots and the
  // selected state. The PageView itself runs on a huge virtual range so it
  // loops forever: after the last package, swiping goes back to the first.
  late int _page;
  static const int _loopBase = 10000;

  int _indexOfSelected() {
    final idx = widget.packages.indexWhere((p) => p.id == widget.selectedPkg?.id);
    return idx < 0 ? 0 : idx;
  }

  @override
  void initState() {
    super.initState();
    _page = _indexOfSelected();
    final n = widget.packages.isEmpty ? 1 : widget.packages.length;
    _controller = PageController(viewportFraction: 0.84, initialPage: n * _loopBase + _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _page = index);
    widget.onSelect(widget.packages[index]);
  }

  /// Called with the virtual page number from the PageView.
  void _onVirtualPageChanged(int virtualPage) {
    final n = widget.packages.length;
    if (n == 0) return;
    _select(virtualPage % n);
  }

  @override
  Widget build(BuildContext context) {
    final packages = widget.packages;
    if (packages.isEmpty) return const SizedBox.shrink();
    if (_page >= packages.length) _page = packages.length - 1;
    final n = packages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text("Choose Your Package",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
            ),
            Icon(Icons.swipe_outlined, size: 14, color: AppPalette.textMuted(context)),
            const SizedBox(width: 4),
            Text("Swipe", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 380,
          child: PageView.builder(
            controller: _controller,
            // No itemCount => endless PageView (loops back to the first slide).
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onVirtualPageChanged,
            itemBuilder: (context, virtualIndex) {
              final index = virtualIndex % n;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  double scale = 1;
                  double opacity = 1;
                  if (_controller.position.haveDimensions) {
                    final page = _controller.page ?? _page.toDouble();
                    final delta = (page - virtualIndex).abs().clamp(0.0, 1.0);
                    scale = 1 - (delta * 0.10);
                    opacity = 1 - (delta * 0.35);
                  }
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: _PackageCard(
                  package: packages[index],
                  isSelected: index == _page,
                  onTap: () {
                    _controller.animateToPage(virtualIndex, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(packages.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.accentTint(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final BoothPackage package;
  final bool isSelected;
  final VoidCallback onTap;
  const _PackageCard({required this.package, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photo = decodeDataUriImage(package.imageUrl);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          decoration: BoxDecoration(
            color: AppPalette.cardBg(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isSelected ? AppColors.accent : AppPalette.divider(context), width: isSelected ? 2 : 1),
            boxShadow: isSelected ? AppShadows.accentGlowSmall : AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: photo != null
                        ? Image.memory(photo, fit: BoxFit.cover, cacheWidth: 640, gaplessPlayback: true)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.accentTint(0.85), AppColors.accent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(child: Icon(Icons.photo_camera_outlined, size: 44, color: Colors.white70)),
                          ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: Text(package.duration, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 15, color: AppColors.onAccent),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(package.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: package.features.take(3).map((f) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 11, color: AppColors.accent),
                            const SizedBox(width: 3),
                            Text(f, style: TextStyle(fontSize: 10.5, color: AppPalette.textSecondary(context))),
                          ],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatPeso(package.price),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accent : AppColors.accentTint(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isSelected ? "Selected" : "Select",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? AppColors.onAccent : AppColors.accent),
                          ),
                        ),
                      ],
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
