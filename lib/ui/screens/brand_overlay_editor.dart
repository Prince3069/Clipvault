// ui/screens/brand_overlay_editor.dart
//
// Replaces the old rotate-only QuickPhotoEditor as Quick Edit's core
// feature. Upload your own photo, add a price/offer, your business name
// and (optionally) a saved logo, export a branded image — no AI involved
// at any point. Compositing happens entirely on-device via Canvas; the
// only network calls this screen makes are the two allowance checks
// (checkBrandingAllowance / consumeBrandingUse), which enforce the
// free/Pro/credit-pack gating server-side. See ai_service.dart for those
// two methods and index.js for what they actually enforce.
//
// Business name persists locally (SharedPreferences) so repeat use
// doesn't mean retyping it every time — this is a deliberate, bounded
// first version: the logo, if picked, is copied into the app's own
// documents directory and its local path is what's remembered, so it
// survives even if the original picked file is deleted from the gallery.
// Neither the business name nor the logo currently sync across devices —
// that would mean uploading to Firestore/Storage, which is a real,
// separate decision (cost, and this app's existing Storage usage is
// scoped to Cloud Vault Pro specifically) that hasn't been made. Said
// plainly here rather than silently built one way.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai_service.dart';
import '../../services/native_bridge.dart';
import '../../services/storage_service.dart';
import '../themes/app_theme.dart';

class BrandOverlayEditor extends StatefulWidget {
  final String imagePath;
  final String imageTitle;

  const BrandOverlayEditor({
    Key? key,
    required this.imagePath,
    required this.imageTitle,
  }) : super(key: key);

  @override
  State<BrandOverlayEditor> createState() => _BrandOverlayEditorState();
}

class _BrandOverlayEditorState extends State<BrandOverlayEditor> {
  final _ai = AIService();
  final _storage = StorageService();
  final _boundaryKey = GlobalKey();

  final _businessNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _ctaCtrl = TextEditingController(text: 'Message us to order');

  String? _logoPath;
  bool _loadingProfile = true;
  bool _exporting = false;
  bool _checkingAllowance = false;

  static const _prefsNameKey = 'brand_overlay_business_name';
  static const _prefsLogoKey = 'brand_overlay_logo_path';

  @override
  void initState() {
    super.initState();
    _loadSavedProfile();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _priceCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _businessNameCtrl.text = prefs.getString(_prefsNameKey) ?? '';
      final savedLogo = prefs.getString(_prefsLogoKey);
      if (savedLogo != null && await File(savedLogo).exists()) {
        _logoPath = savedLogo;
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsNameKey, _businessNameCtrl.text.trim());
    if (_logoPath != null) {
      await prefs.setString(_prefsLogoKey, _logoPath!);
    }
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    try {
      // Copy into the app's own documents directory — the file the user
      // picked from their gallery could be deleted or moved later, and
      // this logo is meant to persist across many future exports, not
      // just this one session.
      final docsDir = await getApplicationDocumentsDirectory();
      final destPath =
          '${docsDir.path}/brand_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(file.path).copy(destPath);
      if (mounted) setState(() => _logoPath = destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save logo: $e')),
        );
      }
    }
  }

  Future<void> _export() async {
    if (_exporting || _checkingAllowance) return;

    setState(() => _checkingAllowance = true);
    Map<String, dynamic> gate;
    try {
      gate = await _ai.checkBrandingAllowance();
    } catch (e) {
      setState(() => _checkingAllowance = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check your allowance: $e')),
      );
      return;
    }
    setState(() => _checkingAllowance = false);

    if (gate['allowed'] != true) {
      if (!mounted) return;
      _showPaywall(gate['reason']?.toString() ??
          'You have used your allowance for this feature.');
      return;
    }

    setState(() => _exporting = true);
    try {
      final bytes = await _renderComposite();
      if (bytes == null) {
        throw 'Could not render the image.';
      }

      final folder = await _storage.getPlatformDownloadPath('Branded');
      final safeName =
          widget.imageTitle.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final tempPath =
          '$folder/branded_${DateTime.now().millisecondsSinceEpoch}_$safeName.png';
      await File(tempPath).writeAsBytes(bytes);

      final destPath = await NativeBridge.saveToMediaStore(
        sourcePath: tempPath,
        fileName: tempPath.split('/').last,
        platform: 'MediaNest',
        mimeType: 'image/png',
      );
      if (destPath == null) {
        throw NativeBridge.lastMediaStoreError ?? 'Save failed';
      }

      // Only record the use once the file is actually saved — a render
      // or disk-write failure above must never cost the allowance.
      await _ai.consumeBrandingUse();
      await _saveProfile();
      await _storage.scanMediaFile(destPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Branded image saved.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Renders the exact same layout the on-screen preview shows, at the
  /// preview widget's own resolution — captured via RepaintBoundary
  /// rather than redrawn separately, so the exported file can never
  /// visually drift from what the user actually saw and approved.
  Future<Uint8List?> _renderComposite() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // pixelRatio 3 for real print/screen sharpness — the on-screen
    // preview itself can stay at device resolution; this only affects
    // the exported file.
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _showPaywall(String reason) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Out of uses for now',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(reason,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Brand Overlay'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: _CompositePreview(
                  imagePath: widget.imagePath,
                  businessName: _businessNameCtrl.text,
                  price: _priceCtrl.text,
                  cta: _ctaCtrl.text,
                  logoPath: _logoPath,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFF111111),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _priceCtrl,
                          hint: 'Price or offer (e.g. ₦12,000)',
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _pickLogo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        child: Text(_logoPath == null ? 'Add logo' : 'Change logo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field(controller: _businessNameCtrl, hint: 'Business name'),
                  const SizedBox(height: 8),
                  _field(controller: _ctaCtrl, hint: 'Call to action'),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: (_exporting || _checkingAllowance) ? null : _export,
                    icon: (_exporting || _checkingAllowance)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(_checkingAllowance
                        ? 'Checking…'
                        : _exporting
                            ? 'Saving…'
                            : 'Save branded image'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}), // live-updates the preview as they type
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// The actual composited layout — the photo, plus price badge, business
/// name/CTA footer, and logo, drawn with plain widgets rather than raw
/// Canvas calls. Flutter's own text and shape widgets already handle
/// anti-aliasing, font weights, and arbitrary sizes correctly — there is
/// no need to fight a lower-level Canvas API by hand for something this
/// widget tree already renders exactly right, and RepaintBoundary.toImage
/// captures precisely what's on screen, so preview and export can never
/// disagree.
class _CompositePreview extends StatelessWidget {
  final String imagePath;
  final String businessName;
  final String price;
  final String cta;
  final String? logoPath;

  const _CompositePreview({
    required this.imagePath,
    required this.businessName,
    required this.price,
    required this.cta,
    required this.logoPath,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(imagePath), fit: BoxFit.cover),

          // Price badge — top-right, high-contrast, the single fact a
          // buyer looks for first. Only shown if the field isn't empty —
          // an empty green pill would look like a rendering bug, not an
          // intentionally-omitted price.
          if (price.trim().isNotEmpty)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  price.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),

          // Footer — business name + logo, always present once a name is
          // set, anchors trust the same way it does across every other
          // branded-export pattern already established elsewhere.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              color: Colors.black.withOpacity(0.55),
              child: Row(
                children: [
                  if (logoPath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(logoPath!),
                          width: 28, height: 28, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      businessName.trim().isNotEmpty
                          ? businessName.trim()
                          : 'Your business name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (cta.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        cta.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
