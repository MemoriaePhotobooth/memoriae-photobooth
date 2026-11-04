import '../../shared/top_toast.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pricing_item_record.dart';
import '../services/pricing_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Admin-only: edit what booth packages and camera rentals cost, and
/// attach a photo to each one. Backed by the same `pricing/{id}`
/// Firestore collection the customer app reads from — see the note on
/// [PricingItemRecord] — so a change here shows up there right away.
///
/// Same modern-dashboard treatment as the Staff screen: inline header +
/// "Add pricing item" button, a live search field, category stat pills,
/// and soft-shadow cards with bigger rounded thumbnails instead of
/// thin-bordered rows.
class AdminPricingScreen extends StatefulWidget {
  const AdminPricingScreen({super.key});

  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const Map<String, IconData> _categoryIcons = {
    'Camera Rental': Icons.camera_alt_rounded,
    'Booth Package': Icons.card_giftcard_rounded,
    'Add-on': Icons.add_shopping_cart_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PricingItemRecord>>(
      stream: PricingRepository.watchAllPricing(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final items = snapshot.data!;
        final categories = items.map((i) => i.category).toSet().toList();

        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty ? items : items.where((i) => i.name.toLowerCase().contains(q)).toList();
        final visibleCategories = q.isEmpty ? categories : categories.where((c) => filtered.any((i) => i.category == c)).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _buildHeader(context),
            const SizedBox(height: 20),
            _buildStatsAndSearch(context, items: items, categories: categories),
            const SizedBox(height: 20),
            if (filtered.isEmpty)
              _buildEmptyState(context, hasQuery: q.isNotEmpty)
            else
              for (final category in visibleCategories) ...[
                _categoryHeader(context, category, filtered.where((i) => i.category == category).length),
                const SizedBox(height: 10),
                ...filtered.where((i) => i.category == category).map((i) => _priceRow(context, i, categories)),
                const SizedBox(height: 20),
              ],
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Pricing",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppPalette.textPrimary(context)),
              ),
              const SizedBox(height: 4),
              Text(
                "What customers see when booking a package or renting a camera.",
                style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () => _openItemDialog(context, categories: const ['Booth Package', 'Camera Rental', 'Add-on']),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text("Add pricing item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildStatsAndSearch(BuildContext context, {required List<PricingItemRecord> items, required List<String> categories}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final stats = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statPill(context, icon: Icons.sell_outlined, label: '${items.length} item${items.length == 1 ? '' : 's'}'),
            for (final c in categories)
              _statPill(context, icon: _categoryIcons[c] ?? Icons.local_offer_outlined, label: '${items.where((i) => i.category == c).length} $c', tint: true),
          ],
        );
        final search = _buildSearchField(context);

        if (isNarrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [stats, const SizedBox(height: 14), search]);
        }
        return Row(
          children: [
            Expanded(child: stats),
            const SizedBox(width: 16),
            SizedBox(width: 260, child: search),
          ],
        );
      },
    );
  }

  Widget _statPill(BuildContext context, {required IconData icon, required String label, bool tint = false}) {
    final fg = tint ? AppColors.accent : AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tint ? AppColors.accentTint(0.08) : AppPalette.surface(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: "Search pricing items",
          hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
          prefixIcon: Icon(Icons.search, size: 18, color: AppPalette.textMuted(context)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: 16, color: AppPalette.textMuted(context)),
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool hasQuery}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(hasQuery ? Icons.search_off : Icons.sell_outlined, size: 36, color: AppPalette.textMuted(context)),
          const SizedBox(height: 10),
          Text(
            hasQuery ? "No items match \u201c$_query\u201d" : "No pricing items yet",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _categoryHeader(BuildContext context, String category, int count) {
    return Row(
      children: [
        Icon(_categoryIcons[category] ?? Icons.local_offer_outlined, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(category, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
          child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.textMuted(context))),
        ),
      ],
    );
  }

  Widget _thumbnail(BuildContext context, String imageUrl, {double size = 52}) {
    Uint8List? bytes;
    if (imageUrl.startsWith('data:') && imageUrl.contains(',')) {
      try {
        bytes = base64Decode(imageUrl.split(',').last);
      } catch (_) {
        bytes = null;
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover)
            : Container(
                color: AppPalette.surface(context),
                alignment: Alignment.center,
                child: Icon(Icons.image_outlined, size: size * 0.4, color: AppPalette.textMuted(context)),
              ),
      ),
    );
  }

  Widget _priceRow(BuildContext context, PricingItemRecord item, List<String> categories) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          _thumbnail(context, item.imageUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 3),
                Text(item.unit, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(999)),
            child: Text('\u20b1${item.price}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.accent)),
          ),
          const SizedBox(width: 6),
          _iconButton(context, icon: Icons.edit_outlined, onTap: () => _openItemDialog(context, categories: categories, existing: item)),
          const SizedBox(width: 4),
          _iconButton(context, icon: Icons.delete_outline, danger: true, onTap: () => _confirmDelete(context, item)),
        ],
      ),
    );
  }

  Widget _iconButton(BuildContext context, {required IconData icon, required VoidCallback onTap, bool danger = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: danger ? Colors.redAccent : AppColors.accent),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PricingItemRecord item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: const Text('Remove pricing item?'),
          content: Text('This will remove "${item.name}" from the price list.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                PricingRepository.removePricingItem(item.id);
                Navigator.of(context).pop();
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  /// One dialog for both Add and Edit — [existing] null means "add new".
  /// Handles picking/previewing/clearing a photo either way, so a new
  /// item can get its picture right away instead of needing an edit pass
  /// afterward.
  void _openItemDialog(BuildContext context, {required List<String> categories, PricingItemRecord? existing}) {
    final isEditing = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(text: existing?.price.toString() ?? '');
    final unitController = TextEditingController(text: existing?.unit ?? '');
    final rate8Controller = TextEditingController(text: (existing?.rate8Plus ?? 0) > 0 ? existing!.rate8Plus.toString() : '');
    // Camera rates are entered like the rate card: per-day rate for 2-4 days,
    // 5-7 days and 8+ days. The stored `price` is the 1-day price (2-4 days
    // rate + 50). Existing cameras are pre-filled from what's saved.
    final isCam = existing?.category == 'Camera Rental';
    final savedPrice = existing?.price ?? 0;
    final saved57 = !isCam ? 0 : ((existing!.rate5to7 > 0) ? existing.rate5to7 : savedPrice - 100);
    final rate24Controller = TextEditingController(text: isCam && savedPrice > 50 ? (savedPrice - 50).toString() : '');
    final rate57Controller = TextEditingController(text: saved57 > 0 ? saved57.toString() : '');
    final featuresController = TextEditingController(text: existing?.features.join('\n') ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    String selectedCategory = existing?.category ?? (categories.isNotEmpty ? categories.first : 'Booth Package');
    String imageUrl = existing?.imageUrl ?? '';
    bool picking = false;
    bool saving = false;
    // Realtime validation: a field's message shows once it's touched (or a
    // save was attempted) and updates on every keystroke.
    final touched = <String>{};
    int? digitsOf(String raw) => int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    String? fieldError(String key) {
      switch (key) {
        case 'name':
          return nameController.text.trim().isEmpty ? 'Enter a name.' : null;
        case 'rate24':
          final v = digitsOf(rate24Controller.text);
          return (v == null || v <= 0) ? 'Enter a rate above \u20b10, numbers only (e.g. 449).' : null;
        case 'rate57':
          return (rate57Controller.text.trim().isNotEmpty && digitsOf(rate57Controller.text) == null) ? 'Numbers only.' : null;
        case 'rate8':
          return (rate8Controller.text.trim().isNotEmpty && digitsOf(rate8Controller.text) == null) ? 'Numbers only.' : null;
        case 'price':
          final v = digitsOf(priceController.text);
          return (v == null || v <= 0) ? 'Enter a price above \u20b10, numbers only (e.g. 2999).' : null;
        case 'unit':
          return unitController.text.trim().isEmpty ? 'Enter the unit (e.g. per 2 hrs).' : null;
      }
      return null;
    }
    String? shownError(String key) => touched.contains(key) ? fieldError(key) : null;

    InputDecoration deco(BuildContext ctx, String label, {String? prefixText}) => InputDecoration(
          labelText: label,
          prefixText: prefixText,
          filled: true,
          fillColor: AppPalette.surface(ctx),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          alignLabelWithHint: true,
        );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> pickPhoto() async {
              setState(() => picking = true);
              try {
                final picker = ImagePicker();
                // Same constraints as ReceiptUpload — keeps the base64
                // result comfortably small since there's no Storage
                // upload backing this, just an in-memory data: URI.
                final XFile? picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  // Small on purpose: these photos are stored inside the
                  // Firestore document and downloaded by every customer, so
                  // every extra pixel makes the customer app heavier.
                  imageQuality: 65,
                  maxWidth: 720,
                  maxHeight: 720,
                );
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                if (bytes.lengthInBytes > 400 * 1024) {
                  if (dialogContext.mounted) {
                    TopToast.show(dialogContext, "That photo is too large (${(bytes.lengthInBytes / 1024).round()} KB) — pick a smaller one.");
                  }
                  return;
                }
                setState(() => imageUrl = PricingRepository.encodeImage(bytes, picked.name));
              } finally {
                if (dialogContext.mounted) setState(() => picking = false);
              }
            }

            Widget photoPicker() {
              Uint8List? bytes;
              if (imageUrl.startsWith('data:') && imageUrl.contains(',')) {
                try {
                  bytes = base64Decode(imageUrl.split(',').last);
                } catch (_) {}
              }
              return Row(
                children: [
                  InkWell(
                    onTap: picking ? null : pickPhoto,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppPalette.surface(dialogContext),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppPalette.divider(dialogContext)),
                        image: bytes != null ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover) : null,
                      ),
                      alignment: Alignment.center,
                      child: picking
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          : (bytes == null ? const Icon(Icons.add_a_photo_outlined, color: AppColors.accent) : null),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bytes == null ? 'No photo yet' : 'Photo attached',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(dialogContext)),
                        ),
                        TextButton(
                          onPressed: picking ? null : pickPhoto,
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero, minimumSize: const Size(0, 0), alignment: Alignment.centerLeft, foregroundColor: AppColors.accent),
                          child: Text(bytes == null ? 'Add photo' : 'Change photo', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        if (bytes != null)
                          TextButton(
                            onPressed: picking ? null : () => setState(() => imageUrl = ''),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero, minimumSize: const Size(0, 0), alignment: Alignment.centerLeft, foregroundColor: Colors.redAccent),
                            child: const Text('Remove photo', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.accentTint(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(isEditing ? Icons.edit_outlined : Icons.add_circle_outline, size: 19, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit \u2014 ${existing.name}' : 'Add pricing item',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photoPicker(),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        onChanged: (_) => setState(() => touched.add('name')),
                        decoration: deco(dialogContext, 'Name').copyWith(errorText: shownError('name')),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        items: const [
                          DropdownMenuItem(value: 'Booth Package', child: Text('Booth Package')),
                          DropdownMenuItem(value: 'Camera Rental', child: Text('Camera Rental')),
                          DropdownMenuItem(value: 'Add-on', child: Text('Add-on')),
                        ],
                        onChanged: (value) => setState(() => selectedCategory = value ?? selectedCategory),
                        decoration: deco(dialogContext, 'Category'),
                      ),
                      const SizedBox(height: 12),
                      if (selectedCategory == 'Camera Rental') ...[
                        TextField(
                          controller: rate24Controller,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => touched.add('rate24')),
                          decoration: deco(dialogContext, '2-4 days (per day)', prefixText: '\u20b1 ').copyWith(errorText: shownError('rate24')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: rate57Controller,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => touched.add('rate57')),
                          decoration: deco(dialogContext, '5-7 days (per day)', prefixText: '\u20b1 ').copyWith(errorText: shownError('rate57')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: rate8Controller,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => touched.add('rate8')),
                          decoration: deco(dialogContext, '8 days onwards (per day)', prefixText: '\u20b1 ').copyWith(errorText: shownError('rate8')),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            (int.tryParse(rate24Controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) > 0
                                ? '1 day rental = \u20b1${(int.tryParse(rate24Controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) + 50} (2-4 days rate + \u20b150)'
                                : '1 day rental = 2-4 days rate + \u20b150',
                            style: TextStyle(fontSize: 12, color: AppPalette.textMuted(dialogContext)),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => touched.add('price')),
                          decoration: deco(dialogContext, 'Price', prefixText: '\u20b1 ').copyWith(errorText: shownError('price')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: unitController,
                          onChanged: (_) => setState(() => touched.add('unit')),
                          decoration: deco(dialogContext, 'Unit (e.g. per 2 hrs)').copyWith(errorText: shownError('unit')),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 1,
                        maxLines: 2,
                        maxLength: 120,
                        decoration: deco(dialogContext, 'Short description (optional, shown on homepage)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: featuresController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: deco(dialogContext, 'Features (one per line, optional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.textSecondary(dialogContext), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          // Tanggalin ang comma at espasyo, kaya "2,999" ay tatanggapin din.
                          final isCamera = selectedCategory == 'Camera Rental';
                          int? parse(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));
                          final rate24 = parse(rate24Controller);
                          // Cameras: stored price = 1-day price = 2-4 days rate + 50.
                          final price = isCamera ? (rate24 == null ? null : rate24 + 50) : parse(priceController);
                          final unit = isCamera ? 'per 1 day' : unitController.text.trim();
                          final rate5to7 = isCamera ? (parse(rate57Controller) ?? 0) : 0;
                          final rate8Plus = isCamera ? (parse(rate8Controller) ?? 0) : 0;
                          final features = featuresController.text.split('\n').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
                          final description = descriptionController.text.trim();
                          if (name.isEmpty || price == null || unit.isEmpty) {
                            setState(() => touched.addAll(['name', 'rate24', 'price', 'unit']));
                            TopToast.show(dialogContext, isCamera
                                    ? 'Kulang ang Name o ang 2-4 days rate. Numero lang ang rate, halimbawa 449.'
                                    : 'Kulang ang Name, Price, o Unit. Ang Price ay numero lang, halimbawa 2999.');
                            return;
                          }

                          setState(() => saving = true);
                          try {
                            // Hintayin ang sagot ng Firestore. Dati, hindi ito hinihintay
                            // kaya tahimik na nawawala ang item kapag may problema sa koneksyon.
                            final write = isEditing
                                ? PricingRepository.updateItem(
                                    existing.id,
                                    name: name,
                                    category: selectedCategory,
                                    price: price,
                                    rate8Plus: rate8Plus,
                                    rate5to7: rate5to7,
                                    unit: unit,
                                    imageUrl: imageUrl,
                                    features: features,
                                    description: description,
                                  )
                                : PricingRepository.addPricingItem(
                                    PricingItemRecord(
                                      id: 'pkg-${DateTime.now().millisecondsSinceEpoch}',
                                      name: name,
                                      category: selectedCategory,
                                      price: price,
                                      rate8Plus: rate8Plus,
                                      rate5to7: rate5to7,
                                      unit: unit,
                                      imageUrl: imageUrl,
                                      features: features,
                                      description: description,
                                    ),
                                  );
                            await write.timeout(const Duration(seconds: 15));
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          } on TimeoutException {
                            debugPrint('Pricing save timed out');
                            if (dialogContext.mounted) {
                              setState(() => saving = false);
                              TopToast.show(
                                dialogContext,
                                'Walang sagot mula sa server. Tingnan ang internet at subukan ulit. Baka mag-sync pa ito pag nakakonekta na, kaya i-refresh ang listahan.',
                                kind: TopToastKind.error,
                                duration: const Duration(seconds: 6),
                              );
                            }
                          } catch (e) {
                            debugPrint('Pricing save failed: $e');
                            if (dialogContext.mounted) {
                              setState(() => saving = false);
                              TopToast.show(
                                dialogContext,
                                'Hindi na-save: $e',
                                kind: TopToastKind.error,
                                duration: const Duration(seconds: 6),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isEditing ? 'Save' : 'Add', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}