import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../main.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_record.dart';
import '../services/app_storage.dart';
import '../services/compliance_engine.dart';
import '../services/image_cropper.dart';
import '../services/scan_store.dart';
import '../services/report_service.dart';
import 'result_screen.dart';

/// Which independent scan this camera session runs. Label checking and
/// box/damage checking are separate flows; Inspection Mode runs both in one
/// session (label slots, then packaging slots) and produces a single
/// combined record. The user picks one on the Homepage before the camera
/// opens.
enum CameraMode { label, damage, inspection }

/// Which slot group is currently being captured. Fixed for [CameraMode.label]
/// (always [label]) and [CameraMode.damage] (always [box]); for
/// [CameraMode.inspection] the session starts at [label] and advances to
/// [box] once all label slots are captured.
enum _CapturePhase { label, box }

/// UI-facing scan progress. OCR happens in this screen before
/// ComplianceEngine's analyze methods are ever called, so it gets its own
/// leading stage ahead of [ScanStage].
enum _ScanUiStage {
  extractingText,
  matchingRegistry,
  classifying,
  checkingDamage,
}

/// One label-capture step.
typedef _LabelSpec = ({PhotoSlot slot, String title, String helper});

/// One packaging-capture step.
typedef _BoxSpec = ({BoxSlot slot, String title, String helper});

const List<_LabelSpec> _labelSlots = [
  (
  slot: PhotoSlot.front,
  title: 'Product name / label',
  helper: 'Frame the product name or full label inside the guide',
  ),
  (
  slot: PhotoSlot.expiration,
  title: 'Expiration date',
  helper: 'Frame the expiration / best-before date inside the guide',
  ),
  (
  slot: PhotoSlot.ingredients,
  title: 'Ingredient list',
  helper: 'Frame the ingredient list inside the guide',
  ),
];

/// Selectable framing-box presets for the label close-ups. Users pick the one
/// that best isolates the target text, so a logo that's too big or too long
/// doesn't pull in surrounding detail that confuses OCR.
typedef _GuidePreset = ({String label, Size size});

const List<_GuidePreset> _guidePresets = [
  (label: 'Small', size: Size(190, 130)),
  (label: 'Medium', size: Size(250, 180)),
  (label: 'Large', size: Size(310, 230)),
];

/// The expiration date is small and must not capture nearby text, so its
/// framing box is fixed tight regardless of the selected preset.
const Size _expirationGuideSize = Size(210, 100);

class CameraScreen extends StatefulWidget {
  final CameraMode mode;

  /// Which packaging type the damage step should run against — required for
  /// [CameraMode.damage] and [CameraMode.inspection] (chosen on
  /// PackagingTypeScreen before this screen opens); unused for
  /// [CameraMode.label].
  final PackagingType? packagingType;

  const CameraScreen({super.key, required this.mode, this.packagingType})
      : assert(
  mode == CameraMode.label || packagingType != null,
  'packagingType is required for damage and inspection scans',
  );

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isReady = false;
  bool _isTaking = false;
  bool _isProcessing = false;
  _ScanUiStage _scanStage = _ScanUiStage.extractingText;
  bool _isFlashOn = false;
  int _cameraIndex = 0;

  // Zoom
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // Focus
  Offset? _focusPoint;

  // ── Sequential capture state ────────────────────────────────────────────
  late _CapturePhase _phase;
  int _slotIndex = 0;

  /// Index into [_guidePresets] for the label framing box. Defaults to Medium.
  int _guidePresetIndex = 1;

  final Map<PhotoSlot, String> _labelPaths = {};
  final Map<BoxSlot, String> _boxPaths = {};

  /// Label slots the user has verified are physically absent from the packaging
  /// (via the "not on the box" button). A declared-missing element flags the
  /// scan non-compliant — see ComplianceEngine's label checks.
  final Set<PhotoSlot> _declaredMissing = {};

  /// Rendered size of the camera area, captured in [build] via LayoutBuilder.
  /// The framing guide is centered in this space, so it's also the coordinate
  /// system used to crop label photos to the guide.
  Size _previewSize = Size.zero;

  bool get _isLabelPhase => _phase == _CapturePhase.label;

  /// The four packaging-capture steps, titled for whichever [PackagingType]
  /// was chosen (Box / Foil / Bottle). The capture shape (front/side/side/
  /// back) is shared across all packaging types — only the label text and
  /// which detector processes the photos afterward changes.
  List<_BoxSpec> get _boxSlots {
    final typeLabel = (widget.packagingType ?? PackagingType.box).label;
    final lower = typeLabel.toLowerCase();
    return [
      (
      slot: BoxSlot.front,
      title: '$typeLabel — Front',
      helper: 'Fit the whole front of the $lower inside the guide',
      ),
      (
      slot: BoxSlot.side1,
      title: '$typeLabel — Side',
      helper: 'Fit one side of the $lower inside the guide',
      ),
      (
      slot: BoxSlot.side2,
      title: '$typeLabel — Other side',
      helper: 'Fit the other side of the $lower inside the guide',
      ),
      (
      slot: BoxSlot.back,
      title: '$typeLabel — Back',
      helper: 'Fit the whole back of the $lower inside the guide',
      ),
    ];
  }

  int get _slotCount =>
      _isLabelPhase ? _labelSlots.length : _boxSlots.length;

  String get _currentTitle =>
      _isLabelPhase ? _labelSlots[_slotIndex].title : _boxSlots[_slotIndex].title;

  String get _currentHelper => _isLabelPhase
      ? _labelSlots[_slotIndex].helper
      : _boxSlots[_slotIndex].helper;

  /// The label slot currently being captured, or null during a box phase.
  PhotoSlot? get _currentLabelSlot =>
      _isLabelPhase ? _labelSlots[_slotIndex].slot : null;

  /// Whether the current slot is one the user can declare absent from the
  /// packaging (expiration date or ingredient list).
  bool get _canDeclareMissing =>
      _currentLabelSlot == PhotoSlot.expiration ||
          _currentLabelSlot == PhotoSlot.ingredients;

  /// Which progress stages apply to the whole session, in display order.
  List<_ScanUiStage> get _activeStages {
    switch (widget.mode) {
      case CameraMode.label:
        return const [
          _ScanUiStage.extractingText,
          _ScanUiStage.matchingRegistry,
          _ScanUiStage.classifying,
        ];
      case CameraMode.damage:
        return const [_ScanUiStage.checkingDamage];
      case CameraMode.inspection:
        return const [
          _ScanUiStage.extractingText,
          _ScanUiStage.matchingRegistry,
          _ScanUiStage.classifying,
          _ScanUiStage.checkingDamage,
        ];
    }
  }

  /// Badge text describing what this camera session is doing right now.
  String get _modeBadgeText {
    final typeLabel = widget.packagingType?.label.toUpperCase();
    switch (widget.mode) {
      case CameraMode.label:
        return 'LABEL CHECK';
      case CameraMode.damage:
        return '$typeLabel DAMAGE CHECK';
      case CameraMode.inspection:
        return _isLabelPhase
            ? 'INSPECTION · LABEL STEP'
            : 'INSPECTION · $typeLabel STEP';
    }
  }

  Color get _modeBadgeColor {
    switch (widget.mode) {
      case CameraMode.label:
        return const Color(0xFF4CAF50);
      case CameraMode.damage:
        return const Color(0xFF1E88E5);
      case CameraMode.inspection:
        return const Color(0xFF8E24AA);
    }
  }

  /// Framing-guide dimensions. Packaging shots use a fixed upright rectangle.
  /// Label close-ups use the user-selected [_guidePresets] entry so
  /// oversized/long logos don't drag in surrounding text — except the
  /// expiration slot, which is locked to a small tight frame
  /// ([_expirationGuideSize]) so nearby text can't be mistaken for the date.
  Size get _guideSize {
    if (!_isLabelPhase) {
      if (!_isLandscape) return const Size(300, 360);
      // In landscape the screen is short and wide, so the portrait box
      // guide (taller than it is wide) barely fits vertically — use a
      // wider, shorter rectangle.
      //
      // The height is derived from what is actually free rather than being
      // a fixed constant. A fixed 260 overlapped the thumbnail strip on
      // shorter landscape viewports, drawing the guide border straight
      // through the slot tiles; subtracting the strip and the safe-area
      // insets keeps them apart at any screen size.
      final band = _landscapeGuideBand;
      final height = (band.height - 16).clamp(140.0, 300.0);
      final maxWidth = (band.width - 16).clamp(200.0, 520.0);
      return Size((height * 1.35).clamp(200.0, maxWidth), height);
    }

    final labelGuide = _currentLabelSlot == PhotoSlot.expiration
        ? _expirationGuideSize
        : _guidePresets[_guidePresetIndex].size;
    if (!_isLandscape) return labelGuide;
    // The presets are sized for portrait. Rotated, the Large preset is tall
    // enough to reach the thumbnail strip, so scale it to fit the free
    // height. The drawn guide and the OCR crop both read this getter, so
    // they stay in agreement — a shrunk guide crops exactly what the user
    // framed.
    final available = _landscapeGuideBand.height - 16;
    if (available >= labelGuide.height) return labelGuide;
    final scale = (available / labelGuide.height).clamp(0.45, 1.0);
    return Size(labelGuide.width * scale, labelGuide.height * scale);
  }

  /// True once the rendered camera area (tracked via [_previewSize], set at
  /// the top of the LayoutBuilder in [build]) is wider than it is tall —
  /// i.e. the phone is physically rotated to landscape. Drives both the
  /// guide sizing above and which overlay layout [build] uses.
  bool get _isLandscape => _previewSize.width > _previewSize.height;

  /// System intrusions — status bar, gesture bar, display cutout — read in
  /// [build]. The preview is deliberately full-bleed, so the Stack is *not*
  /// wrapped in a SafeArea; the overlay controls add these insets to their
  /// own offsets instead.
  ///
  /// This matters far more in landscape than portrait. Rotated, the status
  /// bar and the notch both move to a side edge, which is exactly where the
  /// left info panel and the exit button sit — which is why the flow badge
  /// was sliding under the clock and the exit button was landing on the
  /// battery icons.
  EdgeInsets _viewPadding = EdgeInsets.zero;

  /// Width of the landscape left-hand info panel.
  static const double _landscapePanelWidth = 216;

  /// Horizontal room the right-hand control column needs (button plus its
  /// margin), used to keep the guide and thumbnail strip clear of it.
  static const double _landscapeControlColumnWidth = 96;

  /// Reserved height for the bottom-left cluster (preset picker + thumbnail
  /// wrap) in landscape. The top info column stops above this. Sized for the
  /// worst case: a single-row preset pill row (~44), the gap (10), and a
  /// one-row 48px thumbnail wrap — a label phase. Damage phases have no
  /// picker and use less.
  static const double _landscapeBottomClusterHeight = 120;


  /// The rectangle actually available to the framing guide in landscape:
  /// the preview minus the safe-area insets, the left info panel, the right
  /// control column, and the bottom thumbnail strip.
  ///
  /// The guide is centred in *this*, not in the whole preview. Centring in
  /// the whole preview is what put the guide's lower edge through the slot
  /// tiles: the free space is not symmetric, because the strip only eats
  /// into the bottom. Working from the band also allows a noticeably larger
  /// guide than shrinking a centred one until it happened to clear.
  /// Width reserved on the left for the bottom cluster's widest element —
  /// the horizontal preset pill row, which now extends past the info panel.
  /// The guide starts to the right of this so the two never overlap even
  /// though the guide runs the full height.
  static const double _landscapeLeftReserve = 300;

  Rect get _landscapeGuideBand {
    final left = _viewPadding.left + _landscapeLeftReserve;
    final right = _previewSize.width -
        _landscapeControlColumnWidth -
        _viewPadding.right;
    // Leaves room at the top for the declare-missing pill when that step
    // can show one, so a tall guide's top edge stays clear of it; otherwise
    // just the normal margin.
    final top = _viewPadding.top +
        (_canDeclareMissing && _isLabelPhase ? 64 : 16);
    // The thumbnails moved into the left panel, so the bottom no longer
    // needs the reserved strip — the guide can run nearly the full height.
    final bottom = _previewSize.height - 16 - _viewPadding.bottom;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Where the framing guide is centred. Portrait keeps the geometric
  /// centre of the preview; landscape uses the centre of the free band.
  ///
  /// The label crop reads this too (see [_takePhoto]), so the cropped
  /// region always matches the rectangle the user was shown — moving the
  /// guide without moving the crop would silently crop the wrong area.
  Offset get _guideCenter {
    if (!_isLandscape) {
      return Offset(_previewSize.width / 2, _previewSize.height / 2);
    }
    return _landscapeGuideBand.center;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inspection Mode starts on the label phase, same as label-only mode;
    // damage-only mode starts (and stays) on the box phase.
    _phase = widget.mode == CameraMode.damage
        ? _CapturePhase.box
        : _CapturePhase.label;
    _initCamera(_cameraIndex);
    // Prefetch the FDA dataset (and DistilBERT if enabled), plus the chosen
    // packaging type's damage detector, while the user is still framing/
    // capturing photos, so analysis doesn't pay full load latency.
    ComplianceEngine.warmUp(packagingType: widget.packagingType);
    // Wide packaging is easier to capture tilted, so allow landscape only
    // while this screen is open; every other screen stays portrait-locked.
    _applyCameraOrientations();
  }

  Future<void> _initCamera(int index) async {
    if (globalCameras.isEmpty) return;
    final prev = _controller;
    if (prev != null) await prev.dispose();

    final controller = CameraController(
      globalCameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _currentZoom = _minZoom;
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      if (mounted) setState(() => _isReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_cameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // Restore the portrait lock used by the rest of the app.
    SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]);
    // Best-effort cleanup of any temp photos abandoned mid-flow.
    for (final path in [..._labelPaths.values, ..._boxPaths.values]) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _switchCamera() async {
    if (globalCameras.length < 2) return;
    setState(() => _isReady = false);
    _cameraIndex = (_cameraIndex + 1) % globalCameras.length;
    await _initCamera(_cameraIndex);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await _controller!
        .setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
  }

  // ── Pinch to zoom ──────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (details.pointerCount < 2) return; // only act on pinch, not single tap
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return; // skip tiny changes
    setState(() => _currentZoom = newZoom);
    await _controller!.setZoomLevel(newZoom);
  }

  // ── Tap to focus ───────────────────────────────────────────────────────────
  Future<void> _onTapFocus(TapUpDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPos = box.globalToLocal(details.globalPosition);
    final double x = (localPos.dx / box.size.width).clamp(0.0, 1.0);
    final double y = (localPos.dy / box.size.height).clamp(0.0, 1.0);

    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setFocusPoint(Offset(x, y));
      await _controller!.setExposurePoint(Offset(x, y));
    } catch (e) {
      debugPrint('Focus error: $e');
    }

    setState(() {
      _focusPoint = localPos;
    });
  }

  // ── Take photo ─────────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTaking || _isProcessing) return;
    setState(() => _isTaking = true);

    try {
      final XFile photo = await _controller!.takePicture();

      // takePicture() writes into the plugin's cache directory, which Android
      // is free to reclaim part-way through a scan. Move the shot into the
      // app's own captures folder before anything else refers to it; the crop
      // below then lands beside it, and both are cleared when the flow ends.
      final stagedPath = await AppStorage.newCapturePath(
        prefix: _isLabelPhase
            ? _labelSlots[_slotIndex].slot.name
            : _boxSlots[_slotIndex].slot.name,
      );
      await photo.saveTo(stagedPath);
      try {
        await File(photo.path).delete();
      } catch (_) {
        // The plugin's own temp copy is best-effort cleanup, not correctness.
      }

      if (_isLabelPhase) {
        // Isolate the label region: crop to the framing guide so OCR isn't
        // distracted by the surrounding scene.
        // Same centre the guide was drawn at, so the crop matches exactly
        // what the user framed in either orientation.
        final guide = Rect.fromCenter(
          center: _guideCenter,
          width: _guideSize.width,
          height: _guideSize.height,
        );
        final croppedPath = await ImageCropper.cropToGuide(
          stagedPath,
          screenSize: _previewSize,
          guideRect: guide,
        );
        final slot = _labelSlots[_slotIndex].slot;
        _labelPaths[slot] = croppedPath;
      } else {
        // Packaging shots are used full-frame for damage detection — no crop.
        _boxPaths[_boxSlots[_slotIndex].slot] = stagedPath;
      }

      await _advanceOrFinish();
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture failed. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  /// Records the current label element (expiration or ingredients) as absent
  /// from the packaging and advances without a photo. The scan will be flagged
  /// non-compliant for the missing element.
  Future<void> _declareCurrentMissing() async {
    if (_isTaking || _isProcessing) return;
    final slot = _currentLabelSlot;
    if (slot == null) return;

    // Drop any photo already taken for this slot (unlikely mid-flow).
    final existing = _labelPaths.remove(slot);
    if (existing != null) {
      try {
        final f = File(existing);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }

    setState(() => _declaredMissing.add(slot));
    await _advanceOrFinish();
  }

  Future<void> _advanceOrFinish() async {
    if (_slotIndex < _slotCount - 1) {
      setState(() => _slotIndex++);
      return;
    }

    // Inspection Mode: after the last label slot, move on to the packaging
    // phase instead of analyzing yet.
    if (widget.mode == CameraMode.inspection && _isLabelPhase) {
      setState(() {
        _phase = _CapturePhase.box;
        _slotIndex = 0;
      });
      if (mounted) {
        final typeLabel = (widget.packagingType ?? PackagingType.box).label;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Label photos done — now photograph the $typeLabel.'),
            backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    await _runAnalysis();
  }

  // ── Run the analysis for whichever mode this screen is in ──────────────
  Future<void> _runAnalysis() async {
    switch (widget.mode) {
      case CameraMode.label:
        await _runLabelAnalysis();
        break;
      case CameraMode.damage:
        await _runDamageAnalysis();
        break;
      case CameraMode.inspection:
        await _runInspectionAnalysis();
        break;
    }
  }

  /// OCRs every captured label crop, routing each slot's text to its own
  /// field (see LabelParser) instead of guessing field boundaries out of one
  /// combined blob. Shared by label-only and Inspection Mode.
  Future<_OcrResult> _ocrLabelSlots() async {
    final textRecognizer = TextRecognizer();
    final textBySlot = <PhotoSlot, String>{};
    final buffer = StringBuffer();
    // Mean OCR confidence on the product-name (front) crop — gates the
    // last-ditch semantic tier in ComplianceEngine.
    double? nameConfidence;
    try {
      for (final spec in _labelSlots) {
        final path = _labelPaths[spec.slot];
        if (path == null) continue;
        final inputImage = InputImage.fromFilePath(path);
        final recognized = await textRecognizer.processImage(inputImage);
        textBySlot[spec.slot] = recognized.text;
        if (spec.slot == PhotoSlot.front) {
          nameConfidence = _meanLineConfidence(recognized);
        }
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(recognized.text);
      }
    } catch (e) {
      debugPrint('OCR error: $e');
    } finally {
      await textRecognizer.close();
    }
    return _OcrResult(
      textBySlot: textBySlot,
      combinedText: buffer.toString(),
      nameConfidence: nameConfidence,
    );
  }

  List<String> get _capturedBoxPaths => [
    for (final spec in _boxSlots)
      if (_boxPaths[spec.slot] != null) _boxPaths[spec.slot]!,
  ];

  // ── OCR the label crops, then run the label-compliance analysis ────────
  Future<void> _runLabelAnalysis() async {
    setState(() {
      _isProcessing = true;
      _scanStage = _ScanUiStage.extractingText;
    });

    final ocr = await _ocrLabelSlots();

    final record = await ComplianceEngine.analyzeLabel(
      textBySlot: ocr.textBySlot,
      combinedText: ocr.combinedText,
      ocrConfidence: ocr.nameConfidence,
      expirationDeclaredMissing:
      _declaredMissing.contains(PhotoSlot.expiration),
      ingredientsDeclaredMissing:
      _declaredMissing.contains(PhotoSlot.ingredients),
      onStageChange: _mapStageChange,
    );

    await _finishAnalysis(record);
  }

  // ── Run the packaging/damage analysis directly — no OCR involved ───────
  Future<void> _runDamageAnalysis() async {
    setState(() {
      _isProcessing = true;
      _scanStage = _ScanUiStage.checkingDamage;
    });

    final record = await ComplianceEngine.analyzeDamage(
      packagingType: widget.packagingType!,
      boxPhotoPaths: _capturedBoxPaths,
    );

    await _finishAnalysis(record);
  }

  // ── OCR + damage check together, combined into one verdict ─────────────
  Future<void> _runInspectionAnalysis() async {
    setState(() {
      _isProcessing = true;
      _scanStage = _ScanUiStage.extractingText;
    });

    final ocr = await _ocrLabelSlots();

    final record = await ComplianceEngine.analyzeInspection(
      textBySlot: ocr.textBySlot,
      combinedText: ocr.combinedText,
      packagingType: widget.packagingType!,
      boxPhotoPaths: _capturedBoxPaths,
      ocrConfidence: ocr.nameConfidence,
      expirationDeclaredMissing:
      _declaredMissing.contains(PhotoSlot.expiration),
      ingredientsDeclaredMissing:
      _declaredMissing.contains(PhotoSlot.ingredients),
      onStageChange: _mapStageChange,
    );

    await _finishAnalysis(record);
  }

  void _mapStageChange(ScanStage stage) {
    if (!mounted) return;
    setState(() {
      _scanStage = switch (stage) {
        ScanStage.matchingRegistry => _ScanUiStage.matchingRegistry,
        ScanStage.classifying => _ScanUiStage.classifying,
        ScanStage.checkingDamage => _ScanUiStage.checkingDamage,
      };
    });
  }

  Future<void> _finishAnalysis(ScanRecord record) async {
    if (mounted) setState(() => _isProcessing = false);

    if (mounted) {
      // The result screen is portrait-only. The camera allows landscape,
      // and pushing the result over it would otherwise inherit whatever way
      // the phone was being held — which is what rendered the result card
      // sideways and clipped. Force portrait for the result, then restore
      // the camera's orientation set on the way back so the next capture
      // can still be shot in landscape.
      await SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(record: record),
        ),
      );
      _applyCameraOrientations();
      if (mounted) _showSaveSheet(record);
    }
  }

  /// Orientations allowed while the camera is on screen: portrait plus both
  /// landscapes, so wide packaging can be captured by turning the phone.
  /// Pulled out so [_finishAnalysis] can restore it after the portrait-only
  /// result screen.
  void _applyCameraOrientations() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Mean recognized-line confidence (0..1) across [recognized], or null if
  /// ML Kit didn't populate confidences (e.g. on platforms/models that omit
  /// them) — in which case the caller treats OCR as "not known to be low".
  double? _meanLineConfidence(RecognizedText recognized) {
    var sum = 0.0;
    var count = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final c = line.confidence;
        if (c != null) {
          sum += c;
          count++;
        }
      }
    }
    return count == 0 ? null : sum / count;
  }

  // ── Check duplicate name ───────────────────────────────────────────────────
  Future<bool> _nameExists(String raw) => ScanStore.recordExists(raw);

  void _resetCaptureFlow() {
    setState(() {
      _labelPaths.clear();
      _boxPaths.clear();
      _declaredMissing.clear();
      _slotIndex = 0;
      _phase = widget.mode == CameraMode.damage
          ? _CapturePhase.box
          : _CapturePhase.label;
    });
  }

  void _discardCapturedPhotos() {
    for (final path in [..._labelPaths.values, ..._boxPaths.values]) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
    _resetCaptureFlow();
  }

  /// Confirms before wiping every captured photo and restarting the flow from
  /// the first slot.
  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all photos?'),
        content: const Text(
            'This discards every photo you\'ve taken and restarts the scan '
                'from the first step.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE57373)),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _discardCapturedPhotos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All photos cleared.'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Confirms before leaving this scan and popping back to the chooser.
  /// Skips the confirmation if nothing has been captured yet.
  Future<void> _confirmExit() async {
    if (_isTaking || _isProcessing) return;
    final hasPhotos = _labelPaths.isNotEmpty || _boxPaths.isNotEmpty;
    if (!hasPhotos) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit scan?'),
        content: const Text(
            'This discards every photo you\'ve taken so far for this scan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE57373)),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _discardCapturedPhotos();
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Save Record bottom sheet ───────────────────────────────────────────────
  void _showSaveSheet(ScanRecord record) {
    final TextEditingController nameController = TextEditingController();
    // The outer screen's own context, kept so we can pop CameraScreen itself
    // (back to the Homepage) once the sheet — which sits on its own route —
    // has been dismissed.
    final BuildContext cameraContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool isTaken = false;
        bool isEmpty = true;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void onChanged(String val) async {
              final taken = await _nameExists(val);
              setSheetState(() {
                isTaken = taken;
                isEmpty = val.trim().isEmpty;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A847),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'User Instruction - Save Record',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    onChanged: onChanged,
                    decoration: InputDecoration(
                      hintText: 'Record name',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isTaken
                              ? const Color(0xFFE57373)
                              : Colors.grey.shade400,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isTaken
                              ? const Color(0xFFE57373)
                              : const Color(0xFF4CAF50),
                          width: 2,
                        ),
                      ),
                      errorText: isTaken
                          ? 'This name is already taken. Please choose another.'
                          : null,
                      errorStyle: const TextStyle(
                          color: Color(0xFFE57373), fontSize: 11),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                        const BorderSide(color: Color(0xFFE57373)),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFFE57373), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '*Please input a name for the record you just scanned.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '*Note: once saved, this name cannot be changed.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  const Text('Example :',
                      style:
                      TextStyle(fontSize: 12, color: Colors.black54)),
                  const Text(
                    'Loaf_of_bread',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _discardCapturedPhotos();
                            if (cameraContext.mounted) {
                              Navigator.of(cameraContext).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE57373),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (isEmpty || isTaken)
                              ? null
                              : () async {
                            final raw = nameController.text.trim();
                            Navigator.of(context).pop();
                            final saved = await _saveRecord(raw, record);
                            if (saved && cameraContext.mounted) {
                              // Back to the Homepage, not the packaging
                              // chooser this scan came through: returning
                              // there shows a stale "Last used" marker for
                              // the scan just finished. popUntil clears the
                              // camera and chooser together.
                              Navigator.of(cameraContext)
                                  .popUntil((route) => route.isFirst);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Save',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Save record ─────────────────────────────────────────────────────────────
  /// Returns true if the record was saved successfully.
  Future<bool> _saveRecord(String rawName, ScanRecord record) async {
    try {
      final dir = await ScanStore.save(
        rawName: rawName,
        capturedPhotoPaths: Map.of(_labelPaths),
        boxPhotoPaths: Map.of(_boxPaths),
        record: record,
      );

      // Submit flagged results to central dashboard (fire-and-forget)
      ReportService.submit(
        recordDir: dir,
        record: record,
        productName: rawName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Record "$rawName" saved!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
      _resetCaptureFlow();
      return true;
    } catch (e) {
      debugPrint('Save record error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save record.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Starting camera...',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final isLabelPhase = _isLabelPhase;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The guide is centered in this space; reuse it as the crop
          // coordinate system for label photos. Also drives _isLandscape,
          // which both _guideSize and the overlay layout below key off of.
          _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          // Read fresh every build: rotating the device moves which edges
          // the status bar and cutout occupy, and the landscape offsets
          // below depend on it.
          _viewPadding = MediaQuery.of(context).padding;
          final isLandscape = _isLandscape;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview — GestureDetector wraps it for pinch + tap
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onTapUp: _onTapFocus,
                child: CameraPreview(_controller!),
              ),

              // Framing guide. Positioned at the guide's exact centre with a
              // -50%/-50% translation, so the rectangle's true centre lands
              // on _guideCenter regardless of its size. (Alignment-based
              // placement pulls a child toward the preview middle by a
              // fraction of its own size, which made the guide and the pill
              // above it centre on different points.) The pill uses the same
              // method, so the two share a vertical centre line.
              Positioned(
                left: _guideCenter.dx,
                top: _guideCenter.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: IgnorePointer(
                    child: Container(
                      width: _guideSize.width,
                      height: _guideSize.height,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _currentZoom > _minZoom + 0.05
                          ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentZoom.toStringAsFixed(1)}x',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      )
                          : null,
                    ),
                  ),
                ),
              ),

              // Focus circle indicator — always in tree, animates on each tap
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 35,
                  top: _focusPoint!.dy - 35,
                  child: _FocusCircle(
                    key: ValueKey(_focusPoint),
                    visible: true,
                  ),
                ),

              // Everything else — header, shortcuts, guide preset picker,
              // thumbnails, and the shutter/flip/flash controls — is laid
              // out completely differently depending on orientation, since
              // portrait has vertical room to spare and landscape doesn't.
              ...isLandscape
                  ? _landscapeOverlay(isLabelPhase)
                  : _portraitOverlay(isLabelPhase),
            ],
          );
        },
      ),
    );
  }

  // ── Portrait overlay ──────────────────────────────────────────────────
  // The original layout: header banner across the top, shutter/flip/flash
  // in a row along the bottom. Plenty of vertical room, so everything
  // stacks.
  List<Widget> _portraitOverlay(bool isLabelPhase) {
    return [
      Positioned(
        top: 56,
        left: 20,
        right: 20,
        child: _headerColumn(isLabelPhase),
      ),

      // Clear-all shortcut — top-left. Only shown once at least one photo
      // has been captured, so there's something to discard.
      if (!_isProcessing &&
          (_labelPaths.isNotEmpty || _boxPaths.isNotEmpty))
        Positioned(top: 52, left: 12, child: _clearAllButton()),

      // Exit shortcut — top-right. Pops back to the Homepage.
      if (!_isProcessing)
        Positioned(top: 52, right: 12, child: _exitButton()),

      // "No <element> on the box" — horizontally centered on the guide
      // rectangle and sitting just above its top edge, per step.
      if (isLabelPhase && !_isProcessing && _canDeclareMissing)
        _declareMissingPositioned(),

      if (_isProcessing) _processingOverlay(),

      // Framing-box preset selector — label phase only. Sits well above
      // the thumbnail strip (bottom: 120, ~70px tall) so the
      // Small/Medium/Large pills don't crowd the slot thumbnails.
      if (isLabelPhase && !_isProcessing)
        Positioned(
          bottom: 212,
          left: 0,
          right: 0,
          child: Center(child: _buildGuideControl()),
        ),

      // Thumbnail strip for the current phase
      Positioned(
        bottom: 120,
        left: 0,
        right: 0,
        child: _thumbnailRow(isLabelPhase),
      ),

      // Bottom controls — above the gesture layer so buttons work
      Positioned(
        bottom: 32,
        left: 0,
        right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [_flipButton(), _shutterButton(), _flashButton()],
        ),
      ),
    ];
  }

  // ── Landscape overlay ─────────────────────────────────────────────────
  // Landscape trades vertical room for horizontal: the badge, title, helper,
  // and clear-all sit in a top-left column; the preset picker and thumbnails
  // sit in a bottom-left cluster; the declare-missing pill is centered above
  // the guide; the
  // shutter/flip/flash controls move into a column centered on the right
  // edge instead of a bottom row; the thumbnail strip stays a horizontal
  // row, narrowed to the space between the two side columns instead of
  // spanning full width. The exit button is the one piece that stays a
  // simple top corner in both orientations.
  List<Widget> _landscapeOverlay(bool isLabelPhase) {
    // Every offset is padded by the system insets. Rotated, the status bar
    // and cutout sit on a side edge — the same edge as the info panel and
    // the exit button — so without this the badge slides under the clock
    // and the exit button lands on the battery icons.
    final leftInset = _viewPadding.left;
    final rightInset = _viewPadding.right;
    final topInset = _viewPadding.top;
    final bottomInset = _viewPadding.bottom;

    return [
      // Top-left cluster — clear-all, mode badge, title, helper text, and
      // the declare-missing pill. Anchored to the TOP and allowed to take
      // only the height it needs. It is deliberately NOT in the same column
      // as the preset picker and thumbnails: stacking all of it made the
      // panel taller than a short landscape screen and forced a scroll.
      // Splitting top-anchored info from bottom-anchored controls means
      // neither can push the other off-screen.
      Positioned(
        left: 16 + leftInset,
        top: 16 + topInset,
        // Stops above the bottom cluster's zone so the two never collide.
        bottom: _landscapeBottomClusterHeight + 16 + bottomInset,
        width: _landscapePanelWidth,
        // No FittedBox: the text renders at one fixed size on every step.
        // The earlier scale-to-fit is what made each step look different,
        // since steps carry different amounts of text. Fixed sizing plus a
        // worst-case-sized bottom reserve keeps it consistent and keeps it
        // from ever needing to scroll.
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isProcessing &&
                  (_labelPaths.isNotEmpty || _boxPaths.isNotEmpty)) ...[
                _clearAllButton(),
                const SizedBox(height: 10),
              ],
              _headerColumn(
                isLabelPhase,
                crossAxisAlignment: CrossAxisAlignment.start,
                textAlign: TextAlign.left,
              ),
            ],
          ),
        ),
      ),

      // Bottom-left cluster — the guide preset picker and the per-slot
      // thumbnails, anchored to the BOTTOM corner. Fixed, shallow height so
      // it can't grow into a scroll, and it sits in the dead space under
      // the guide's left side rather than over it.
      if (!_isProcessing)
        Positioned(
          left: 16 + leftInset,
          bottom: 16 + bottomInset,
          // Bounded on the right only, so the horizontal preset row can run
          // wider than the info panel into the open space — but never into
          // the shutter/flip/flash column.
          right: _landscapeControlColumnWidth + rightInset,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLabelPhase) ...[
                  _buildGuideControl(),
                  const SizedBox(height: 10),
                ],
                _thumbnailWrap(isLabelPhase),
              ],
            ),
          ),
        ),

      // "No <element> on the box" — horizontally centered on the guide
      // rectangle and sitting just above its top edge, same as portrait.
      if (isLabelPhase && !_isProcessing && _canDeclareMissing)
        _declareMissingPositioned(),

      // Exit shortcut — top-right corner in both orientations. The control
      // column on the right is vertically centered (see below), so this
      // never collides with it.
      if (!_isProcessing)
        Positioned(
          top: 12 + topInset,
          right: 16 + rightInset,
          child: _exitButton(),
        ),

      if (_isProcessing) _processingOverlay(),

      // Right control column — flip/shutter/flash stacked vertically and
      // centered along the full height, replacing the portrait bottom row.
      Positioned(
        right: 16 + rightInset,
        top: topInset,
        bottom: bottomInset,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _flipButton(),
              const SizedBox(height: 22),
              _shutterButton(),
              const SizedBox(height: 22),
              _flashButton(),
            ],
          ),
        ),
      ),
    ];
  }

  // ── Shared overlay pieces ────────────────────────────────────────────
  // Built once, arranged differently by each orientation's overlay above.

  /// Mode badge, photo count, title, helper text, and (when relevant) the
  /// "not on the box" button. [crossAxisAlignment]/[textAlign] let the
  /// landscape overlay left-align this in a narrow column instead of the
  /// portrait centered banner.
  Widget _headerColumn(
      bool isLabelPhase, {
        CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
        TextAlign textAlign = TextAlign.center,
      }) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Which check this session is running.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _modeBadgeColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _modeBadgeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'PHOTO ${_slotIndex + 1} OF $_slotCount',
          textAlign: textAlign,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _currentTitle,
          textAlign: textAlign,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _currentHelper,
          textAlign: textAlign,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  /// Positions [_declareMissingPill] so its horizontal center aligns with
  /// the guide rectangle's center, sitting just above the rectangle's top
  /// edge. Both are derived from [_guideCenter] and [_guideSize], so the
  /// pill tracks the guide across steps and orientations without a separate
  /// anchor to keep in sync.
  ///
  /// The pill's own width is unknown until layout, so it is centered with a
  /// FractionalTranslation(-0.5) around the guide's center x rather than by
  /// computing left/right — that keeps it centered whatever the caption
  /// length.
  Widget _declareMissingPositioned() {
    // Horizontal position tracks the guide rectangle's centre, so the pill
    // sits directly over whichever rectangle the current step shows.
    // Vertical position is FIXED near the top of the screen — it does not
    // follow the guide's top edge — so the pill stays put across steps and
    // only slides left/right to stay centred on the rectangle.
    //
    // Centering is done with an Align across the FULL width rather than a
    // left offset plus a translation: the pill's own width is unknown until
    // layout, and the earlier translation-based approach shifted it by half
    // its measured width, landing it right of the guide's centre. Align maps
    // the guide's centre x to an alignment value directly, so the result is
    // exact regardless of caption length.
    final topY = _viewPadding.top + (_isLandscape ? 16 : 56);
    return Positioned(
      left: _guideCenter.dx,
      top: topY,
      child: FractionalTranslation(
        // -0.5 on x only: centre on the guide's x, keep the given top y.
        // This is the exact method the guide rectangle uses, so the pill's
        // centre and the rectangle's centre fall on the same vertical line
        // whatever either one's width.
        translation: const Offset(-0.5, 0),
        child: _declareMissingPill(),
      ),
    );
  }

  /// The "No <element> on the box" pill, shown top-center above the guide
  /// during label phases. Pulled out of the header column and given its own
  /// centered anchor: inside the column it overflowed the fixed-height left
  /// panel (the yellow-black stripe on the expiration and ingredient steps),
  /// and it sat over the preset picker. Centered above the guide, it clears
  /// every other control.
  Widget _declareMissingPill() {
    return GestureDetector(
      onTap: _isTaking ? null : _declareCurrentMissing,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.report_gmailerrorred_outlined,
                color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              _currentLabelSlot == PhotoSlot.expiration
                  ? 'No expiration date on the box'
                  : 'No ingredient list on the box',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clearAllButton() {
    return GestureDetector(
      onTap: _isTaking ? null : _confirmClearAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 16),
            SizedBox(width: 5),
            Text('Clear all',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _exitButton() {
    return GestureDetector(
      onTap: _isTaking ? null : _confirmExit,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _processingOverlay() {
    return Container(
      color: const Color(0xFF2E7D32),
      child: Center(
        child: _ScanProgressCard(
          stage: _scanStage,
          stages: _activeStages,
        ),
      ),
    );
  }

  Widget _thumbnailRow(bool isLabelPhase) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: isLabelPhase
          ? [
        for (var i = 0; i < _labelSlots.length; i++)
          _SlotThumbnail(
            label: _shortTitle(_labelSlots[i].title),
            isCurrent: i == _slotIndex,
            imagePath: _labelPaths[_labelSlots[i].slot],
          ),
      ]
          : [
        for (var i = 0; i < _boxSlots.length; i++)
          _SlotThumbnail(
            label: _shortTitle(_boxSlots[i].title),
            isCurrent: i == _slotIndex,
            imagePath: _boxPaths[_boxSlots[i].slot],
          ),
      ],
    );
  }

  Widget _flipButton() {
    return _CircleButton(
      color: Colors.black.withValues(alpha: 0.6),
      icon: Icons.flip_camera_android,
      iconColor: Colors.white,
      size: 52,
      onTap: _isProcessing ? null : _switchCamera,
    );
  }

  Widget _shutterButton() {
    return _CircleButton(
      color: Colors.white,
      icon: _isTaking ? null : Icons.circle,
      iconColor: Colors.white,
      size: 72,
      onTap: (_isTaking || _isProcessing) ? null : _takePhoto,
      isShutter: true,
      isTaking: _isTaking,
    );
  }

  Widget _flashButton() {
    return _CircleButton(
      color: Colors.grey.withValues(alpha: 0.6),
      icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
      iconColor: Colors.white,
      size: 52,
      onTap: _isProcessing ? null : _toggleFlash,
    );
  }

  /// The framing-box control shown during a label phase: a preset picker for
  /// most slots, or a locked "fixed tight frame" badge for the expiration slot.
  Widget _buildGuideControl() {
    if (_currentLabelSlot == PhotoSlot.expiration) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('Fixed tight frame for the date',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
    }

    // Single horizontal row in both orientations. It is allowed to be wider
    // than the left info panel — only the framing guide is used for the
    // actual capture, so the pills can extend right into the open space
    // rather than wrapping down and eating vertical room.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _guidePresets.length; i++) _presetPill(i),
        ],
      ),
    );
  }

  /// Compact thumbnail block for the landscape left panel: small tiles that
  /// wrap left-to-right instead of stacking in a tall column. Four tiles at
  /// full size made the panel overflow into a scroll on short landscape
  /// heights; a wrap of ~40px tiles fits without one and never reaches the
  /// guide.
  Widget _thumbnailWrap(bool isLabelPhase) {
    final slots = isLabelPhase ? _labelSlots : _boxSlots;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < slots.length; i++)
          _SlotThumbnail(
            label: null,
            isCurrent: i == _slotIndex,
            imagePath: isLabelPhase
                ? _labelPaths[slots[i].slot]
                : _boxPaths[slots[i].slot],
            size: 48,
          ),
      ],
    );
  }

  Widget _presetPill(int index) {
    final selected = index == _guidePresetIndex;
    return GestureDetector(
      onTap: _isTaking ? null : () => setState(() => _guidePresetIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _guidePresets[index].label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// First word of a slot title, used as the compact thumbnail caption.
  static String _shortTitle(String title) {
    final dashIndex = title.indexOf('—');
    final cleaned = dashIndex == -1 ? title : title.substring(dashIndex + 1).trim();
    return cleaned.split(' ').first;
  }
}

/// Bundles the per-slot OCR text, the concatenated text used for registry
/// matching, and the product-name crop's mean confidence.
class _OcrResult {
  final Map<PhotoSlot, String> textBySlot;
  final String combinedText;
  final double? nameConfidence;

  const _OcrResult({
    required this.textBySlot,
    required this.combinedText,
    required this.nameConfidence,
  });
}

// ── Slot thumbnail ─────────────────────────────────────────────────────────────

class _SlotThumbnail extends StatelessWidget {
  /// Caption under the tile. Null in the landscape thumbnail wrap, where the
  /// tiles are unlabelled to stay compact, so the built-in caption would
  /// only add height.
  final String? label;
  final bool isCurrent;
  final String? imagePath;

  /// Tile edge length. Defaults to the portrait size; the landscape wrap
  /// passes a smaller value so four tiles fit without scrolling.
  final double size;

  const _SlotThumbnail({
    required this.label,
    required this.isCurrent,
    required this.imagePath,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isCaptured = imagePath != null;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFF4CAF50)
                      : Colors.white.withValues(alpha: 0.4),
                  width: isCurrent ? 2.5 : 1,
                ),
                image: imagePath != null
                    ? DecorationImage(
                  image: FileImage(File(imagePath!)),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: imagePath == null
                  ? Icon(Icons.image_outlined,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: size * 0.4)
                  : null,
            ),
            if (isCaptured)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check,
                      size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        if (label != null) ...[
          const SizedBox(height: 3),
          Text(
            label!,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ],
    );
  }
}

// ── Circle button ──────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final Color iconColor;
  final double size;
  final VoidCallback? onTap;
  final bool isShutter;
  final bool isTaking;

  const _CircleButton({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.size,
    required this.onTap,
    this.isShutter = false,
    this.isTaking = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: isShutter
              ? Border.all(color: Colors.white, width: 4)
              : null,
        ),
        child: isTaking
            ? const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.black),
        )
            : Icon(icon, color: iconColor, size: size * 0.45),
      ),
    );
  }
}

// ── Focus circle animation ─────────────────────────────────────────────────────

class _FocusCircle extends StatefulWidget {
  final bool visible;
  const _FocusCircle({super.key, required this.visible});

  @override
  State<_FocusCircle> createState() => _FocusCircleState();
}

class _FocusCircleState extends State<_FocusCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Scale from slightly large → normal size (snappy lock-in feel)
    _scale = Tween<double>(begin: 1.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Fade in quickly, then fade out toward the end
    _opacity = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: 0.85), weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.85, end: 0.85), weight: 50),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.85, end: 0.0), weight: 30),
    ]).animate(_controller);

    if (widget.visible) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(_FocusCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Scan progress card ──────────────────────────────────────────────────────

class _ScanProgressCard extends StatelessWidget {
  final _ScanUiStage stage;

  /// Which stages apply to the running mode, in display order — label mode
  /// shows OCR/registry/classify; damage mode shows just the damage check;
  /// Inspection Mode shows all four.
  final List<_ScanUiStage> stages;

  const _ScanProgressCard({required this.stage, required this.stages});

  static const _subtitles = {
    _ScanUiStage.extractingText: 'Reading text from your label photos',
    _ScanUiStage.matchingRegistry: 'Checking against the FDA database',
    _ScanUiStage.classifying: 'Running the compliance model',
    _ScanUiStage.checkingDamage: 'Inspecting the packaging for damage',
  };

  static const _stepLabels = {
    _ScanUiStage.extractingText: 'Extracting label text (OCR)',
    _ScanUiStage.matchingRegistry: 'Matching FDA registry',
    _ScanUiStage.classifying: 'Classifying label result',
    _ScanUiStage.checkingDamage: 'Checking packaging for damage',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: const [
                CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
                Icon(Icons.document_scanner_outlined,
                    color: Colors.white, size: 30),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing scan...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _subtitles[stage]!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          for (final s in stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _ScanStepRow(
                label: _stepLabels[s]!,
                completed: s.index < stage.index,
                active: s == stage,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanStepRow extends StatelessWidget {
  final String label;
  final bool completed;
  final bool active;

  const _ScanStepRow({
    required this.label,
    required this.completed,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = (completed || active)
        ? Colors.white
        : Colors.white.withValues(alpha: 0.45);

    return Row(
      children: [
        Icon(
          completed ? Icons.check_circle : Icons.circle_outlined,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}