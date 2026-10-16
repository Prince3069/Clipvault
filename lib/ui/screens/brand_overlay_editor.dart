// ui/screens/brand_overlay_editor.dart
//
// Quick Edit's core feature. Upload your own photo, add a price/offer,
// your business name and (optionally) a saved logo, drag each one wherever
// actually fits THIS photo, turn off whichever you don't want, export — no
// AI involved at any point. Compositing happens entirely on-device via
// Canvas (captured through RepaintBoundary); the only network calls are
// the two allowance checks (checkBrandingAllowance / consumeBrandingUse),
// which enforce the free/Pro/credit-pack gating server-side.
//
// Business name and logo persist locally (SharedPreferences + app
// documents dir) so repeat use doesn't mean retyping/re-picking every
// time. Element POSITIONS also persist locally per element kind, as a
// personal default — someone whose photos are usually a certain shape
// shouldn't have to redrag every element every single time. Reset to
// Default restores the original four-corner layout AND full visibility,
// in one tap, so dragging things into a mess is never a dead end.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai_service.dart';
import '../../services/storage_service.dart';
import '../themes/app_theme.dart';

/// The four things that can go on a branded photo. Order here is display
/// order for the toggle-chip row, not draw order (draw order is fixed:
/// logo, then name, then price, then description, so an accidental
/// overlap always keeps price/description on top — the two fields most
/// likely to contain the specific thing someone's looking at).
enum _ElementKind { name, price, logo, cta, description }

extension on _ElementKind {
  String get label => switch (this) {
        _ElementKind.name => 'Name',
        _ElementKind.price => 'Price',
        _ElementKind.logo => 'Logo',
        _ElementKind.cta => 'CTA',
        _ElementKind.description => 'Description',
      };
}

/// One element's placement + visibility. Position is FRACTIONAL (0.0–1.0
/// of the canvas width/height, anchored at the element's own center) —
/// not pixels — so it stays correct regardless of preview size vs. actual
/// export resolution, and so a saved default from a portrait photo still
/// lands somewhere sane on a square one.
class _ElementState {
  Offset position;
  bool visible;
  _ElementState({required this.position, this.visible = true});
  _ElementState copy() => _ElementState(position: position, visible: visible);
}

Map<_ElementKind, Offset> get _defaultPositions => {
      _ElementKind.name: const Offset(0.30, 0.08),
      _ElementKind.price: const Offset(0.82, 0.08),
      _ElementKind.logo: const Offset(0.12, 0.92),
      _ElementKind.cta: const Offset(0.30, 0.90),
      _ElementKind.description: const Offset(0.68, 0.90),
    };

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

  // Caps chosen so a single line at this preview's default font size
  // wraps to at most 2–3 lines rather than running off indefinitely —
  // the actual overflow protection is the wrapping box below, this is
  // about keeping input reasonable while someone is still typing.
  static const _nameMaxLen = 40;
  static const _descMaxLen = 80;

  final _businessNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _ctaCtrl = TextEditingController(text: 'Message us to order');
  final _descriptionCtrl = TextEditingController();

  String? _logoPath;
  bool _loadingProfile = true;
  bool _exporting = false;
  bool _checkingAllowance = false;
  _ElementKind? _selectedElement;

  final Map<_ElementKind, _ElementState> _elements = {
    for (final k in _ElementKind.values)
      k: _ElementState(position: _defaultPositions[k]!),
  };

  static const _prefsNameKey = 'brand_overlay_business_name';
  static const _prefsLogoKey = 'brand_overlay_logo_path';
  static const _prefsPositionsKey = 'brand_overlay_positions_v1';

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
    _descriptionCtrl.dispose();
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

      // Saved layout is "x,y,visible;x,y,visible;..." in _ElementKind.values
      // order — a compact, dependency-free format rather than pulling in a
      // JSON-map preference just for four small records.
      final savedLayout = prefs.getString(_prefsPositionsKey);
      if (savedLayout != null) {
        final parts = savedLayout.split(';');
        for (var i = 0; i < _ElementKind.values.length && i < parts.length; i++) {
          final fields = parts[i].split(',');
          if (fields.length == 3) {
            final x = double.tryParse(fields[0]);
            final y = double.tryParse(fields[1]);
            final vis = fields[2] == '1';
            if (x != null && y != null) {
              _elements[_ElementKind.values[i]] =
                  _ElementState(position: Offset(x, y), visible: vis);
            }
          }
        }
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
    final layout = _ElementKind.values.map((k) {
      final e = _elements[k]!;
      return '${e.position.dx},${e.position.dy},${e.visible ? 1 : 0}';
    }).join(';');
    await prefs.setString(_prefsPositionsKey, layout);
  }

  Future<void> _resetToDefault() async {
    setState(() {
      for (final k in _ElementKind.values) {
        _elements[k] = _ElementState(position: _defaultPositions[k]!);
      }
      _selectedElement = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPositionsKey);
  }

  void _toggleVisible(_ElementKind kind) {
    setState(() {
      _elements[kind]!.visible = !_elements[kind]!.visible;
      if (!_elements[kind]!.visible && _selectedElement == kind) {
        _selectedElement = null;
      }
    });
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

    // Selection UI (the highlight ring + delete button) must never end up
    // baked into the exported image — clear it, let a frame render
    // without it, then capture. A bare setState + toImage in the same
    // call can race ahead of the rebuild on some devices; the frame
    // callback below guarantees the clean frame has actually painted
    // before capture happens.
    final hadSelection = _selectedElement != null;
    if (hadSelection) {
      setState(() => _selectedElement = null);
      await WidgetsBinding.instance.endOfFrame;
    }

    setState(() => _exporting = true);
    try {
      final bytes = await _renderComposite();
      if (bytes == null) {
        throw 'Could not render the image.';
      }

      final tempDir = await getTemporaryDirectory();
      final safeName =
          widget.imageTitle.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final tempPath =
          '${tempDir.path}/branded_${DateTime.now().millisecondsSinceEpoch}_$safeName.png';
      await File(tempPath).writeAsBytes(bytes);

      // saveEditedFile is what makes this show up in the Saved Edits
      // screen — it copies into the app's "Edits" folder, scans it into
      // the gallery, and registers it in StorageService's saved-edits
      // tracking, all in one call. This is the same pathway the old
      // QuickPhotoEditor used; it's the correct integration point, not a
      // new capability being added here.
      final destPath = await _storage.saveEditedFile(
        sourcePath: tempPath,
        fileName: safeName,
        editType: 'brand_overlay',
        mimeType: 'image/png',
      );
      if (destPath == null) {
        throw 'Could not save the branded image.';
      }

      // Only record the use once the file is actually saved — a render
      // or disk-write failure above must never cost the allowance.
      await _ai.consumeBrandingUse();
      await _saveProfile();

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
        actions: [
          TextButton(
            onPressed: _resetToDefault,
            child: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToggleChips(),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) => _DraggableCanvas(
                      imagePath: widget.imagePath,
                      elements: _elements,
                      selected: _selectedElement,
                      canvasSize: constraints.biggest,
                      businessName: _businessNameCtrl.text,
                      price: _priceCtrl.text,
                      cta: _ctaCtrl.text,
                      description: _descriptionCtrl.text,
                      logoPath: _logoPath,
                      onSelect: (kind) =>
                          setState(() => _selectedElement = kind),
                      onDeselect: () => setState(() => _selectedElement = null),
                      onDragUpdate: (kind, fractional) =>
                          setState(() => _elements[kind]!.position = fractional),
                      onDelete: (kind) => _toggleVisible(kind),
                    ),
                  ),
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
                  _field(
                    controller: _businessNameCtrl,
                    hint: 'Business name',
                    maxLength: _nameMaxLen,
                  ),
                  const SizedBox(height: 8),
                  _field(controller: _ctaCtrl, hint: 'Call to action'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _descriptionCtrl,
                    hint: 'Description (optional)',
                    maxLength: _descMaxLen,
                    maxLines: 2,
                  ),
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

  /// Quick on/off per element — the fast path for someone who already
  /// knows "just logo and price" before they've even looked at the photo,
  /// separate from the tap-to-select-then-delete path for someone who
  /// places everything first and then decides one doesn't work here.
  Widget _buildToggleChips() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: _ElementKind.values.map((kind) {
          final on = _elements[kind]!.visible;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _toggleVisible(kind),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: on ? AppColors.primary : const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: on ? Colors.transparent : Colors.white24,
                  ),
                ),
                child: Text(
                  kind.label,
                  style: TextStyle(
                    color: on ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int? maxLength,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
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
        counterStyle: const TextStyle(color: Colors.white38, fontSize: 10),
      ),
    );
  }
}

/// Draws the photo plus every visible element at its current fractional
/// position, and handles drag/tap/select gestures directly — kept as one
/// widget (rather than the photo and each overlay being separate layers)
/// so RepaintBoundary.toImage captures precisely what's on screen with no
/// possibility of preview and export disagreeing.
class _DraggableCanvas extends StatelessWidget {
  final String imagePath;
  final Map<_ElementKind, _ElementState> elements;
  final _ElementKind? selected;
  final Size canvasSize;
  final String businessName;
  final String price;
  final String cta;
  final String description;
  final String? logoPath;
  final void Function(_ElementKind) onSelect;
  final VoidCallback onDeselect;
  final void Function(_ElementKind, Offset fractional) onDragUpdate;
  final void Function(_ElementKind) onDelete;

  // Snap threshold in fractional units — how close to a target a drag
  // needs to get before it gently aligns.
  static const _snap = 0.025;

  // Snap TARGETS are inset from the raw edges, not 0.0/1.0 themselves —
  // every element is anchored at its own CENTER (see FractionalTranslation
  // below), so snapping the center to the literal edge would push half the
  // element past the canvas boundary, clipped out of the export. 0.08/0.92
  // keeps a snapped element's edge close to the photo's edge without
  // hanging off it — roughly matching the inset the default corner
  // positions already use.
  static const _edgeInset = 0.08;

  const _DraggableCanvas({
    required this.imagePath,
    required this.elements,
    required this.selected,
    required this.canvasSize,
    required this.businessName,
    required this.price,
    required this.cta,
    required this.description,
    required this.logoPath,
    required this.onSelect,
    required this.onDeselect,
    required this.onDragUpdate,
    required this.onDelete,
  });

  Offset _snapped(Offset f) {
    double snapAxis(double v) {
      for (final target in [_edgeInset, 0.5, 1.0 - _edgeInset]) {
        if ((v - target).abs() < _snap) return target;
      }
      return v;
    }

    return Offset(
      snapAxis(f.dx).clamp(0.0, 1.0),
      snapAxis(f.dy).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tapping empty canvas space deselects — the delete button/ring
      // shouldn't linger once the person's attention has moved on.
      onTap: onDeselect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(imagePath), fit: BoxFit.cover),
          if (elements[_ElementKind.logo]!.visible) _buildLogo(),
          if (elements[_ElementKind.name]!.visible) _buildName(),
          if (elements[_ElementKind.price]!.visible) _buildPrice(),
          if (elements[_ElementKind.cta]!.visible) _buildCta(),
          if (elements[_ElementKind.description]!.visible) _buildDescription(),
        ],
      ),
    );
  }

  Widget _positioned({
    required _ElementKind kind,
    required Widget child,
  }) {
    final state = elements[kind]!;
    final isSelected = selected == kind;
    final px = state.position.dx * canvasSize.width;
    final py = state.position.dy * canvasSize.height;

    return Positioned(
      left: px,
      top: py,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5), // position = element CENTER
        child: GestureDetector(
          onTap: () => onSelect(kind),
          onPanUpdate: (details) {
            final newPx = (px + details.delta.dx).clamp(0.0, canvasSize.width);
            final newPy = (py + details.delta.dy).clamp(0.0, canvasSize.height);
            final fractional = Offset(
              newPx / canvasSize.width,
              newPy / canvasSize.height,
            );
            onDragUpdate(kind, _snapped(fractional));
          },
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(color: Colors.white, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            padding: isSelected ? const EdgeInsets.all(3) : EdgeInsets.zero,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                if (isSelected)
                  Positioned(
                    top: -12,
                    right: -12,
                    child: GestureDetector(
                      onTap: () => onDelete(kind),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Every text element gets the same dark scrim behind it, sized to the
  /// text rather than a fixed box — this is what keeps text legible
  /// regardless of what's actually behind it once it's been dragged
  /// somewhere the default four-corner layout didn't anticipate. Wraps up
  /// to a bounded width instead of truncating — the real overflow
  /// protection is the input character caps in _field(); this box just
  /// needs to be ABLE to show whatever fits under that cap, in full.
  Widget _scrimText(String text, {required TextStyle style, Color? bg}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: canvasSize.width * 0.6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: style, softWrap: true),
      ),
    );
  }

  Widget _buildName() {
    return _positioned(
      kind: _ElementKind.name,
      child: _scrimText(
        businessName.trim().isNotEmpty ? businessName.trim() : 'Your business name',
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  Widget _buildPrice() {
    if (price.trim().isEmpty) return const SizedBox.shrink();
    return _positioned(
      kind: _ElementKind.price,
      child: _scrimText(
        price.trim(),
        bg: const Color(0xFF10B981),
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  Widget _buildLogo() {
    if (logoPath == null) return const SizedBox.shrink();
    return _positioned(
      kind: _ElementKind.logo,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(logoPath!), width: 44, height: 44, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCta() {
    // This was the actual bug behind "I typed a message and it didn't
    // show" — `cta` was accepted as a constructor parameter and threaded
    // all the way through this widget, but nothing ever actually painted
    // it. Every other field (name, price, logo) had a real _build method
    // called from build() above; this one didn't exist at all.
    if (cta.trim().isEmpty) return const SizedBox.shrink();
    return _positioned(
      kind: _ElementKind.cta,
      child: _scrimText(
        cta.trim(),
        bg: AppColors.primary,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _buildDescription() {
    if (description.trim().isEmpty) return const SizedBox.shrink();
    return _positioned(
      kind: _ElementKind.description,
      child: _scrimText(
        description.trim(),
        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
      ),
    );
  }
}
