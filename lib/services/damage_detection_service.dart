import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../models/damage_report.dart';
import '../models/scan_record.dart';
import '../models/scan_timings.dart';

class _SingleImageResult {
  final bool isDamaged;
  final List<String> detections;
  final List<DamageDetection> boxes;
  final double maxConfidence;

  /// Time spent decoding and letterboxing this photo, and time spent in the
  /// model itself — kept apart because they are two different costs with two
  /// different fixes (photo resolution vs. model size).
  final double preprocessMs;
  final double inferenceMs;

  const _SingleImageResult({
    required this.isDamaged,
    required this.detections,
    required this.boxes,
    required this.maxConfidence,
    required this.preprocessMs,
    required this.inferenceMs,
  });
}

/// One decoded detection box (in model-input letterbox space) with its score and
/// class index. Used for NMS overlap, then mapped back out of letterbox space
/// into normalised source-image coordinates for the on-photo overlay — see
/// [DamageDetectionService._checkOne].
class _Det {
  final double x1, y1, x2, y2, score;
  final int cls;
  const _Det(this.x1, this.y1, this.x2, this.y2, this.score, this.cls);
}

/// One box photo, decoded and letterboxed into the tensor the model wants,
/// plus the numbers needed to map detections back onto the original photo.
///
/// Produced by [DamageDetectionService._preprocessWorker] on a background
/// isolate. Every field is a plain value or typed-data list so the whole thing
/// survives the isolate boundary — same constraint as [ImageCropper]'s
/// crop request.
@immutable
class _Preprocessed {
  /// CHW float32, RGB, 0..1, shaped [1, 3, size, size] once wrapped in a tensor.
  final Float32List input;

  /// Dimensions of the orientation-baked source photo, for un-normalising.
  final int srcWidth, srcHeight;

  /// Letterbox transform the model saw: source pixels were multiplied by
  /// [scale] and offset by [padX]/[padY] inside the square input canvas.
  final double scale;
  final int padX, padY;

  const _Preprocessed({
    required this.input,
    required this.srcWidth,
    required this.srcHeight,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

/// Why the damage model could not be used, in terms a tester can act on.
///
/// The app used to report every load failure as "model failed to load", which
/// says nothing about whether the asset is missing, the export is malformed,
/// or the head is dead — and the three need completely different fixes. This
/// carries a short [reason] for the on-screen message and a longer [fix] for
/// the log.
class DamageModelException implements Exception {
  final String reason;
  final String fix;
  final Object? cause;

  const DamageModelException(this.reason, this.fix, this.cause);

  @override
  String toString() {
    final buffer = StringBuffer('DamageModelException: $reason')
      ..write('\n  Fix: $fix');
    if (cause != null) buffer.write('\n  Cause: $cause');
    return buffer.toString();
  }
}

/// Packaging-damage check backed by an **on-device** Ultralytics YOLO model,
/// run through the `onnxruntime` engine already bundled for the semantic
/// matcher. No network, no API key, no per-scan cost — scans work fully
/// offline.
///
/// One instance per model: [box], [bottle] and [foil] below. Each is INT8-quantized
/// (~3 MB) with the detection head kept in float32 — see
/// `scripts/repair_yolo_int8_head.py` for why the head must stay float.
///
/// Pipeline per photo: decode → resize → optional CLAHE ([claheEqualize],
/// on for [box] only) → letterbox-pad to [inputSize] → CHW float32 (÷255)
/// → model → decode the [1, 4+nc, anchors] output → confidence filter →
/// class-aware NMS. Any surviving detection counts as damage, except classes
/// listed in [nonDamageClasses]; raw class names are preserved for display and
/// for the reason line ComplianceEngine builds.
///
/// Failures (bad decode, model load error) are reported through
/// [DamageCheckResult.available] rather than thrown, so a scan still completes
/// with damage marked unavailable.
class DamageDetectionService {
  /// Cardboard boxes: tuned YOLO11n at 640 px
  /// (`results/New results/boxes_yolo11n_tuned_640_int8.onnx`, repaired).
  ///
  /// Tuned config `batch_batch8` on boxes-v4 v1
  /// (`checkmuna_tuning_boxes_yolo11n_640px_20260919_0830`): validation
  /// P 0.77, R 0.70, F1 0.73, mAP50 0.78, mAP50-95 0.37 — up from the 0.68
  /// mAP50 baseline. 3.03 MB INT8, ~205 ms mean on a Colab CPU proxy. No
  /// confidence sweep has been run on this model yet, so 0.25 is
  /// Ultralytics' default predict threshold — revisit once a sweep exists.
  ///
  /// The only detector with [claheEqualize] on: box damage is largely
  /// low-contrast geometry (creased corners, dented faces, lifted label
  /// edges) whose evidence is a shading gradient rather than a colour or
  /// texture change, and that gradient is what a warehouse's flat overhead
  /// light flattens out. See [applyClahe].
  static final DamageDetectionService box = DamageDetectionService(
    modelAsset: 'assets/box_damage_yolo11n_640_int8.onnx',
    inputSize: 640,
    // names = {0: 'label_abberation', 1: 'surface_deformation'}
    classNames: const {0: 'Label aberration', 1: 'Surface deformation'},
    confThreshold: 0.25,
    subject: 'box',
    claheEqualize: true,
  );

  /// Bottles: tuned YOLOv8n at 640 px
  /// (`results/New results/bottles_yolov8n_tuned_640_int8.onnx`, repaired).
  ///
  /// Tuned config `optimiser_adamw_lr0.0005` on bote-kcrbr v6
  /// (`checkmuna_tuning_bottles_yolov8n_640px_20260920_0548`): validation
  /// P 0.79, R 0.61, F1 0.69, mAP50 0.65, mAP50-95 0.32 — up from the 0.55
  /// mAP50 baseline. 3.29 MB INT8, ~220 ms mean on a Colab CPU proxy. No
  /// confidence sweep has been run on this model yet, so 0.25 is
  /// Ultralytics' default predict threshold — revisit once a sweep exists.
  ///
  /// This retrain drops the input from 960 px to 640 px, which is where the
  /// bottle detector stops being the slow one: the old export cost ~410 ms
  /// mean, and at 640 px the three detectors are now within ~20 ms of each
  /// other.
  static final DamageDetectionService bottle = DamageDetectionService(
    modelAsset: 'assets/bottle_damage_yolov8n_640_int8.onnx',
    inputSize: 640,
    // names = {0: 'label_abberation'}
    classNames: const {0: 'Label aberration'},
    confThreshold: 0.25,
    subject: 'bottle',
  );

  /// Foil packaging (sachets, blister packs): tuned YOLOv5nu at 640 px
  /// (`results/New results/foils_yolov5nu_tuned_640_int8.onnx`, repaired).
  ///
  /// Tuned config `batch_batch8` on foils_without_nodamage v3
  /// (`checkmuna_tuning_foils_yolov5nu_640px_20260920_0605`): validation
  /// P 0.88, R 0.77, F1 0.82, mAP50 0.79, mAP50-95 0.56 — up from the 0.71
  /// mAP50 baseline, and the strongest of the three detectors. 2.84 MB INT8,
  /// ~224 ms mean on a Colab CPU proxy.
  ///
  /// The old foil export's confidence sweep does not carry over (different
  /// dataset, different class set), so this is back on Ultralytics' 0.25
  /// default until a sweep is re-run.
  ///
  /// The dataset this was trained on drops the old explicit "No-Damage"
  /// class — hence `foils_without_nodamage` — so there is no
  /// [nonDamageClasses] entry any more and class 0 is now the damage class.
  /// Keeping the old `{0}` here would have suppressed every foil detection
  /// the model can make.
  static final DamageDetectionService foil = DamageDetectionService(
    modelAsset: 'assets/foil_damage_yolov5nu_640_int8.onnx',
    inputSize: 640,
    // names = {0: 'Structural_Deformation'}
    classNames: const {0: 'Structural deformation'},
    confThreshold: 0.25,
    subject: 'foil',
  );

  DamageDetectionService({
    required this.modelAsset,
    required this.inputSize,
    required this.classNames,
    required this.confThreshold,
    required this.subject,
    this.nonDamageClasses = const {},
    this.claheEqualize = false,
  });

  final String modelAsset;

  /// Square input side the model was exported at (its `imgsz` metadata).
  final int inputSize;

  /// Class index → display name, taken from the model's training metadata.
  /// Keep in sync if you retrain with different/added classes.
  final Map<int, String> classNames;

  /// Class indices that mean "this region is fine" (e.g. a trained
  /// No-Damage class). They are decoded and NMS'd like any other class, then
  /// dropped before reporting so they never count as damage.
  final Set<int> nonDamageClasses;

  /// Minimum class score for a detection to survive.
  final double confThreshold;

  /// What the photos show, for log lines ("box", "bottle").
  final String subject;

  /// Run CLAHE over the photo's luminance before it reaches the model.
  ///
  /// Off by default and on only for [box] — this is a per-detector decision,
  /// not a global one. Contrast-limited equalisation is not free: it lifts
  /// local detail but also amplifies sensor noise in flat regions, and it
  /// moves the input away from the plain-resize pipeline the models were
  /// trained and validated under. That trade is worth taking where the
  /// damage signal *is* local contrast (box creases and dents) and not where
  /// the signal is already high-contrast (foil tears against specular film),
  /// where it would mostly add noise.
  ///
  /// See [applyClahe] for the implementation and its parameters.
  final bool claheEqualize;

  /// IoU above which two same-class boxes are treated as duplicates in NMS.
  static const double _iouThreshold = 0.45;

  /// CLAHE grid: 8x8 tiles, OpenCV's `createCLAHE` default. At a 640 px
  /// input that is 80 px per tile — small enough to track lighting across a
  /// box face, large enough that one crease does not become the whole
  /// histogram it is equalised against.
  static const int _claheTiles = 8;

  /// CLAHE clip limit, as a multiple of the mean bin count (OpenCV's
  /// `clipLimit` default of 2.0 under the same convention). Higher lifts
  /// more detail out of shadow and amplifies more noise with it.
  static const double _claheClipLimit = 2.0;

  Future<OrtSession>? _sessionLoad;

  /// How long the one-time session load took, measured when it happened.
  ///
  /// Kept on the instance rather than per check because the load is paid once
  /// per app run — usually during warm-up, while the user is still framing
  /// photos — and reporting it as part of the first scan only would make that
  /// scan look arbitrarily slower than the ones after it. Every scan reports
  /// it, labelled as the one-time cost it is.
  double? _loadMs;

  /// Loads the ONNX session once; later calls reuse the same in-flight/loaded
  /// session. Safe to call from warm-up and from [check] concurrently.
  Future<OrtSession> _session() => _sessionLoad ??= _loadSession();

  Future<OrtSession> _loadSession() async {
    final loadWatch = Stopwatch()..start();
    OrtEnv.instance.init();

    final Uint8List bytes;
    try {
      bytes = (await rootBundle.load(modelAsset)).buffer.asUint8List();
    } catch (e) {
      throw DamageModelException(
        'the model asset is missing from the app bundle',
        'Check that $modelAsset is listed under flutter/assets in '
            'pubspec.yaml, then rebuild (a hot restart will not pick up a '
            'new asset).',
        e,
      );
    }

    final OrtSession session;
    try {
      session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
    } catch (e) {
      // The usual cause on a phone is a model that desktop onnxruntime loads
      // happily but the mobile build refuses: an export can declare
      // opset_imports for domains no node uses (com.microsoft, nchwc,
      // org.pytorch.aten), and a reduced build rejects the whole model rather
      // than ignoring them.
      throw DamageModelException(
        'onnxruntime rejected the model file',
        'Run scripts/repair_yolo_int8_head.py over the export — it prunes '
            'unused opset imports and fixes the quantized detection head.',
        e,
      );
    }

    _assertHeadAlive(session);
    // Timed after the probe deliberately: the probe is a real inference run
    // that has to finish before the model can be trusted, so its cost is part
    // of what loading the model actually takes.
    _loadMs = loadWatch.elapsedMicroseconds / 1000.0;
    return session;
  }

  /// Rejects a model whose classification head is dead on arrival.
  ///
  /// An INT8 export can quantize the final concat — box coordinates (0..640)
  /// next to sigmoid class scores (0..1) — under a single per-tensor scale
  /// sized for the coordinates. Every class score then falls inside the first
  /// quantization bucket and dequantizes to exactly 0.0. Such a model loads
  /// without error, runs without error, and reports "no damage detected" for
  /// every photo ever scanned — a silent false negative on a compliance check,
  /// which is far worse than an honest failure. The first shipped YOLOv5nu
  /// export had precisely this defect.
  ///
  /// So: push a synthetic frame through and require at least one non-zero
  /// class score. A flat gray frame is not enough — a healthy model can score
  /// every anchor below the first quantization bucket (~0.002) on it — so try
  /// a colour gradient, then fixed-seed noise. Every repaired model
  /// scores well above zero on at least one; a dead head scores exactly 0 on
  /// everything, so an all-zero result is conclusive.
  void _assertHeadAlive(OrtSession session) {
    for (final probe in [_gradientProbe(), _noiseProbe()]) {
      if (_probeHasScore(session, probe)) return; // head is alive
    }

    throw DamageModelException(
      'the model loaded but its classification head is dead',
      'Every class score came back exactly 0, so it could never report '
          'damage. The INT8 export quantized the detection head — re-run '
          'scripts/repair_yolo_int8_head.py on it.',
      null,
    );
  }

  Float32List _gradientProbe() {
    final plane = inputSize * inputSize;
    final data = Float32List(3 * plane);
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final idx = y * inputSize + x;
        data[idx] = x / inputSize;
        data[plane + idx] = y / inputSize;
        data[2 * plane + idx] = (x + y) / (2 * inputSize);
      }
    }
    return data;
  }

  Float32List _noiseProbe() {
    final data = Float32List(3 * inputSize * inputSize);
    var state = 42;
    for (var i = 0; i < data.length; i++) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      data[i] = (state >> 16) / 32768.0;
    }
    return data;
  }

  bool _probeHasScore(OrtSession session, Float32List probe) {
    final tensor = OrtValueTensor.createTensorWithDataList(
      probe,
      [1, 3, inputSize, inputSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs;
    try {
      outputs = session.run(runOptions, {'images': tensor}, const ['output0']);
    } catch (e) {
      throw DamageModelException(
        'the model loaded but could not run',
        'Inference failed on a synthetic frame, so no photo would work either. '
            'Check that the input is named "images" and shaped '
            '[1,3,$inputSize,$inputSize] and the output "output0".',
        e,
      );
    } finally {
      tensor.release();
      runOptions.release();
    }

    try {
      final channels = (outputs[0]!.value as List)[0] as List;
      for (var c = 4; c < channels.length; c++) {
        for (final v in (channels[c] as List)) {
          if ((v as num) != 0) return true;
        }
      }
      return false;
    } finally {
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  /// Kicks off the model load early (e.g. from CameraScreen.initState) so the
  /// first scan doesn't pay full load latency. Errors are swallowed — [check]
  /// re-reports them if loading truly failed.
  Future<void> warmUp() async {
    try {
      await _session();
      debugPrint('Damage model ready: $modelAsset');
    } catch (e) {
      // Logged in full here — including the suggested fix — because warm-up
      // runs the moment a packaging type is picked, well before the user
      // reaches a result screen that could show anything.
      debugPrint('Damage model warm-up failed: $e');
    }
  }

  /// [photoLabels], when given, names each photo's capture slot ("Front",
  /// "Side") for the per-photo report; anything missing falls back to
  /// "Photo N".
  Future<DamageCheckResult> check(
    List<String> photoPaths, {
    List<String>? photoLabels,
  }) async {
    if (photoPaths.isEmpty) {
      return const DamageCheckResult(
        available: false,
        message: 'No photos captured to check for damage.',
      );
    }

    final OrtSession session;
    try {
      session = await _session();
    } catch (e) {
      debugPrint('Damage model failed to load: $e');
      return DamageCheckResult(
        available: false,
        message: e is DamageModelException
            ? 'Damage check unavailable — ${e.reason}.'
            : 'Damage check unavailable (model failed to load).',
      );
    }

    final allDetections = <String>[];
    final allBoxes = <DamageDetection>[];
    final photoReports = <DamagePhotoReport>[];
    var anyDamaged = false;
    var anySucceeded = false;
    var maxConfidence = 0.0;
    final timings = ScanTimingsBuilder();
    // Reported on every scan, not only the one that paid it — see [_loadMs].
    final loadMs = _loadMs;
    if (loadMs != null) {
      timings.add(TimingGroup.damageModel, '$subject model load (one-time)',
          loadMs);
    }

    for (var i = 0; i < photoPaths.length; i++) {
      final path = photoPaths[i];
      try {
        final result = await _checkOne(session, path, i);
        anySucceeded = true;
        timings.add(TimingGroup.damageModel, 'Photo preprocessing',
            result.preprocessMs);
        timings.add(
            TimingGroup.damageModel, 'Inference', result.inferenceMs);
        debugPrint('Damage[${i + 1}/${photoPaths.length}] '
            '${result.detections.isEmpty ? 'clean' : result.detections.join(', ')}'
            ' (max ${(result.maxConfidence * 100).toStringAsFixed(0)}%)'
            ' in ${result.preprocessMs.round()} ms prep'
            ' + ${result.inferenceMs.round()} ms inference');
        photoReports.add(DamagePhotoReport(
          index: i,
          label: _photoLabel(photoLabels, i),
          preprocessMs: result.preprocessMs,
          inferenceMs: result.inferenceMs,
          succeeded: true,
          detections: result.boxes,
        ));
        if (result.isDamaged) {
          anyDamaged = true;
          allDetections.addAll(result.detections);
          allBoxes.addAll(result.boxes);
          if (result.maxConfidence > maxConfidence) {
            maxConfidence = result.maxConfidence;
          }
        }
      } catch (e) {
        debugPrint('Damage check failed for $path: $e');
        // Recorded rather than skipped: a photo that failed is not a photo
        // that came back clean, and the report has to be able to say so.
        photoReports.add(DamagePhotoReport(
          index: i,
          label: _photoLabel(photoLabels, i),
          preprocessMs: 0,
          inferenceMs: 0,
          succeeded: false,
        ));
      }
    }
    debugPrint('Damage: scanned ${photoPaths.length} $subject photo(s); '
        'damaged=$anyDamaged; classes=${allDetections.toSet()}');

    final report = DamageSessionReport(
      subject: subject,
      modelAsset: modelAsset,
      inputSize: inputSize,
      confThreshold: confThreshold,
      modelLoadMs: loadMs,
      photos: photoReports,
    );

    if (!anySucceeded) {
      return DamageCheckResult(
        available: false,
        message: 'Damage check unavailable (inference failed).',
        timings: timings.build(),
        report: report,
      );
    }

    final message = anyDamaged
        ? 'Possible packaging damage detected: ${allDetections.toSet().join(', ')}.'
        : 'No packaging damage detected.';

    return DamageCheckResult(
      available: true,
      message: message,
      isDamaged: anyDamaged,
      detections: allDetections,
      boxes: allBoxes,
      maxConfidence: maxConfidence,
      timings: timings.build(),
      report: report,
    );
  }

  static String _photoLabel(List<String>? labels, int index) {
    if (labels != null && index < labels.length) {
      final label = labels[index].trim();
      if (label.isNotEmpty) return label;
    }
    return 'Photo ${index + 1}';
  }

  /// Decodes and letterboxes one photo. Runs on a background isolate.
  ///
  /// Everything in here is pure Dart over a multi-megapixel still: the JPEG
  /// decode alone runs into seconds on a phone, and the CHW conversion walks
  /// every input pixel on top of that. On the UI isolate — where this used to
  /// live — that is a hard freeze for the whole scan, which is exactly what
  /// made damage checks look like the app had hung.
  static _Preprocessed _preprocessWorker((String, int, bool) request) {
    final (path, inputSize, clahe) = request;
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Could not decode image at $path');
    }
    final oriented = img.bakeOrientation(decoded);

    // ── Letterbox to a square (preserve aspect ratio, pad with gray 114) ──
    final scale =
        math.min(inputSize / oriented.width, inputSize / oriented.height);
    final newW = (oriented.width * scale).round();
    final newH = (oriented.height * scale).round();
    final resized = img.copyResize(oriented, width: newW, height: newH);

    // Equalised after the resize and before the composite, deliberately: at
    // model scale this is ~0.4 MP rather than the full multi-megapixel still,
    // and running it on the padded canvas would feed the flat gray border
    // into the tile histograms and skew the mapping near the edges.
    if (clahe) applyClahe(resized);

    final canvas = img.Image(width: inputSize, height: inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    final padX = ((inputSize - newW) / 2).round();
    final padY = ((inputSize - newH) / 2).round();
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    // ── HWC uint8 → CHW float32, RGB, normalized 0..1 ──
    final input = Float32List(3 * inputSize * inputSize);
    final plane = inputSize * inputSize;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = canvas.getPixel(x, y);
        final idx = y * inputSize + x;
        input[idx] = p.r / 255.0; // R plane
        input[plane + idx] = p.g / 255.0; // G plane
        input[2 * plane + idx] = p.b / 255.0; // B plane
      }
    }

    return _Preprocessed(
      input: input,
      srcWidth: oriented.width,
      srcHeight: oriented.height,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }

  /// Contrast Limited Adaptive Histogram Equalisation, in place.
  ///
  /// Plain histogram equalisation works on the whole frame at once, so a
  /// photo that is bright on one side and shadowed on the other gets a single
  /// compromise curve that helps neither. CLAHE instead equalises each tile
  /// of an 8x8 grid against its own histogram, so a dent sitting in shadow is
  /// stretched against the shadow rather than against the whole photo. Two
  /// corrections keep that from turning into artefacts:
  ///
  ///  * **Clipping.** A tile of flat cardboard has a histogram concentrated
  ///    in a few bins, and equalising it would stretch sensor noise across
  ///    the full range. Each bin is capped at [_claheClipLimit] times the
  ///    mean bin count and the clipped excess is redistributed evenly, which
  ///    bounds how steep the mapping can get.
  ///  * **Bilinear interpolation.** Applying each tile's own mapping to its
  ///    own pixels leaves visible seams at the tile borders — which a
  ///    detector reads as edges. Every pixel is instead mapped by blending
  ///    the four nearest tile mappings by distance to their centres.
  ///
  /// Only luminance is equalised; R/G/B are then scaled by the same ratio so
  /// hue survives. Working on luma rather than per channel is what keeps the
  /// equalisation from shifting colours, which matters because "label
  /// aberration" is partly a colour judgement.
  ///
  /// Public only so `test/clahe_test.dart` can exercise the real thing; the
  /// preprocess worker is the only caller in the app.
  @visibleForTesting
  static void applyClahe(img.Image image) {
    const tiles = _claheTiles;
    final w = image.width, h = image.height;
    if (w < tiles || h < tiles) return; // too small to tile meaningfully

    // ── Luma plane (BT.601), so each pixel is read once, not once per tile ──
    final luma = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        luma[y * w + x] = _clamp255(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
      }
    }

    // Tile bounds come from integer division of the full extent, so the tiles
    // tile the image exactly even when the dimensions do not divide evenly.
    int tileStart(int i, int extent) => (i * extent) ~/ tiles;

    // ── Per-tile mapping: clipped histogram → redistributed → CDF → LUT ──
    final luts = List.generate(tiles * tiles, (_) => Uint8List(256));
    final hist = Int32List(256);
    for (var ty = 0; ty < tiles; ty++) {
      final y0 = tileStart(ty, h), y1 = tileStart(ty + 1, h);
      for (var tx = 0; tx < tiles; tx++) {
        final x0 = tileStart(tx, w), x1 = tileStart(tx + 1, w);
        final count = (y1 - y0) * (x1 - x0);
        if (count <= 0) continue;

        hist.fillRange(0, 256, 0);
        for (var y = y0; y < y1; y++) {
          final row = y * w;
          for (var x = x0; x < x1; x++) {
            hist[luma[row + x]]++;
          }
        }

        // Clip, then hand every clipped pixel back: an even share to each
        // bin, and the remainder one apiece across the low bins. All of it
        // has to go back, because the CDF below is normalised by [count] and
        // any pixel dropped here is range the mapping never reaches. On a
        // low-contrast tile the excess is most of the tile, so dropping even
        // the sub-256 remainder visibly crushes the output.
        final limit = math.max(1, (_claheClipLimit * count / 256).round());
        var excess = 0;
        for (var i = 0; i < 256; i++) {
          if (hist[i] > limit) {
            excess += hist[i] - limit;
            hist[i] = limit;
          }
        }
        final share = excess ~/ 256;
        final remainder = excess % 256;
        for (var i = 0; i < 256; i++) {
          hist[i] += share + (i < remainder ? 1 : 0);
        }

        final lut = luts[ty * tiles + tx];
        var cumulative = 0;
        for (var i = 0; i < 256; i++) {
          cumulative += hist[i];
          lut[i] = _clamp255(cumulative * 255.0 / count);
        }
      }
    }

    // ── Apply, blending the four nearest tile LUTs ──
    // Position is expressed in tile-centre units: -0.5 at the first centre,
    // tiles-0.5 at the last. Clamping the indices makes the outer half-tile
    // margins fall back to a single LUT, which is the standard CLAHE edge
    // handling.
    for (var y = 0; y < h; y++) {
      final fy = (y + 0.5) * tiles / h - 0.5;
      final ty0 = fy.floor();
      final wy = fy - ty0;
      final ty0c = ty0.clamp(0, tiles - 1);
      final ty1c = (ty0 + 1).clamp(0, tiles - 1);
      for (var x = 0; x < w; x++) {
        final fx = (x + 0.5) * tiles / w - 0.5;
        final tx0 = fx.floor();
        final wx = fx - tx0;
        final tx0c = tx0.clamp(0, tiles - 1);
        final tx1c = (tx0 + 1).clamp(0, tiles - 1);

        final src = luma[y * w + x];
        final top = luts[ty0c * tiles + tx0c][src] * (1 - wx) +
            luts[ty0c * tiles + tx1c][src] * wx;
        final bottom = luts[ty1c * tiles + tx0c][src] * (1 - wx) +
            luts[ty1c * tiles + tx1c][src] * wx;
        final mapped = top * (1 - wy) + bottom * wy;

        // Scale the channels by how far the luma moved. The +1 on both sides
        // guards a near-black pixel, whose ratio would otherwise explode and
        // paint shadow noise in colour.
        var ratio = (mapped + 1) / (src + 1);

        // Cap the ratio so the brightest channel lands exactly on 255 rather
        // than past it. Letting a channel clamp on its own is what turns a
        // saturated colour into a different colour: a dark orange being
        // brightened clamps red first, then green, and arrives desaturated
        // and yellow. Giving up some of the brightening on saturated pixels
        // is the cheaper loss, because hue is itself evidence here — the
        // box detector's other class is "label aberration".
        final p = image.getPixel(x, y);
        final peak = math.max(p.r, math.max(p.g, p.b)).toDouble();
        if (peak > 0 && peak * ratio > 255) ratio = 255 / peak;

        image.setPixelRgb(
          x,
          y,
          _clamp255(p.r * ratio),
          _clamp255(p.g * ratio),
          _clamp255(p.b * ratio),
        );
      }
    }
  }

  static int _clamp255(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  /// Runs one photo through the model and returns its surviving detections.
  ///
  /// [sourceIndex] is this photo's position in the caller's list; it rides
  /// along on every [DamageDetection] so an overlay can find the right image
  /// again later.
  ///
  /// The two expensive stages both run off the UI isolate: decoding and
  /// letterboxing via [compute], inference via `runAsync`, which the
  /// onnxruntime package services on an isolate of its own. What is left on
  /// the caller's isolate is the output decode and NMS — a few thousand
  /// comparisons, small enough not to drop a frame.
  Future<_SingleImageResult> _checkOne(
      OrtSession session, String path, int sourceIndex) async {
    final preWatch = Stopwatch()..start();
    final pre =
        await compute(_preprocessWorker, (path, inputSize, claheEqualize));
    // Wall-clock, so it includes spawning the isolate and copying the tensor
    // back across it — that is the wait the user actually pays, not just the
    // decode.
    final preprocessMs = preWatch.elapsedMicroseconds / 1000.0;
    final scale = pre.scale;
    final padX = pre.padX;
    final padY = pre.padY;

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      pre.input,
      [1, 3, inputSize, inputSize],
    );
    final runOptions = OrtRunOptions();
    final inferWatch = Stopwatch()..start();
    List<OrtValue?> outputs;
    try {
      // runAsync hands the run to the package's own isolate and returns null
      // only if it could not start one; the sync path is the fallback so a
      // scan still completes rather than failing over a threading detail.
      outputs = await session.runAsync(
            runOptions,
            {'images': inputTensor},
            const ['output0'],
          ) ??
          session.run(
            runOptions,
            {'images': inputTensor},
            const ['output0'],
          );
    } finally {
      inferWatch.stop();
      inputTensor.release();
      runOptions.release();
    }
    // The forward pass only. Output decoding and NMS below are plain Dart over
    // a few thousand anchors and are reported as neither.
    final inferenceMs = inferWatch.elapsedMicroseconds / 1000.0;

    // output0: [1, 4+nc, anchors] → strip batch, get the 4+nc channel rows.
    final channels = (outputs[0]!.value as List)[0] as List;
    for (final o in outputs) {
      o?.release();
    }

    final numClasses = channels.length - 4;
    final numAnchors = (channels[0] as List).length;

    final candidates = <_Det>[];
    for (var a = 0; a < numAnchors; a++) {
      var bestScore = 0.0;
      var bestCls = -1;
      for (var c = 0; c < numClasses; c++) {
        final s = (channels[4 + c][a] as num).toDouble();
        if (s > bestScore) {
          bestScore = s;
          bestCls = c;
        }
      }
      if (bestScore < confThreshold || bestCls < 0) continue;

      final cx = (channels[0][a] as num).toDouble();
      final cy = (channels[1][a] as num).toDouble();
      final w = (channels[2][a] as num).toDouble();
      final h = (channels[3][a] as num).toDouble();
      candidates.add(
        _Det(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, bestScore, bestCls),
      );
    }

    final kept = _nms(candidates, _iouThreshold);
    final detections = <String>[];
    final boxes = <DamageDetection>[];
    var maxConfidence = 0.0;

    // Undo the letterbox: subtract the padding the model saw, divide out the
    // resize, then divide by the source dimension to land in 0..1. Clamped
    // because a box may legitimately run off the edge of the photo.
    double nx(double v) =>
        (((v - padX) / scale) / pre.srcWidth).clamp(0.0, 1.0);
    double ny(double v) =>
        (((v - padY) / scale) / pre.srcHeight).clamp(0.0, 1.0);

    for (final d in kept) {
      if (nonDamageClasses.contains(d.cls)) continue;
      final label = classNames[d.cls] ?? 'Damage';
      detections.add(label);
      if (d.score > maxConfidence) maxConfidence = d.score;

      final l = nx(d.x1), t = ny(d.y1), r = nx(d.x2), bm = ny(d.y2);
      boxes.add(DamageDetection(
        label: label,
        confidence: d.score,
        left: l,
        top: t,
        width: r - l,
        height: bm - t,
        sourceIndex: sourceIndex,
      ));
    }

    return _SingleImageResult(
      isDamaged: detections.isNotEmpty,
      detections: detections,
      boxes: boxes,
      maxConfidence: maxConfidence,
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
    );
  }

  /// Class-aware non-max suppression: keeps the highest-scoring box and drops
  /// same-class boxes that overlap it beyond [iouThresh].
  static List<_Det> _nms(List<_Det> dets, double iouThresh) {
    dets.sort((a, b) => b.score.compareTo(a.score));
    final removed = List<bool>.filled(dets.length, false);
    final keep = <_Det>[];
    for (var i = 0; i < dets.length; i++) {
      if (removed[i]) continue;
      keep.add(dets[i]);
      for (var j = i + 1; j < dets.length; j++) {
        if (removed[j]) continue;
        if (dets[j].cls == dets[i].cls &&
            _iou(dets[i], dets[j]) > iouThresh) {
          removed[j] = true;
        }
      }
    }
    return keep;
  }

  static double _iou(_Det a, _Det b) {
    final ix1 = math.max(a.x1, b.x1);
    final iy1 = math.max(a.y1, b.y1);
    final ix2 = math.min(a.x2, b.x2);
    final iy2 = math.min(a.y2, b.y2);
    final iw = math.max(0.0, ix2 - ix1);
    final ih = math.max(0.0, iy2 - iy1);
    final inter = iw * ih;
    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final union = areaA + areaB - inter;
    return union <= 0 ? 0.0 : inter / union;
  }
}
