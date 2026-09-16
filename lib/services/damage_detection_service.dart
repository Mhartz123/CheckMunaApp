import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

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
/// Pipeline per photo: decode → letterbox to [inputSize] → CHW float32 (÷255)
/// → model → decode the [1, 4+nc, anchors] output → confidence filter →
/// class-aware NMS. Any surviving detection counts as damage; raw class names
/// are preserved so downstream checks like [DamageCheckResult.hasScratch]
/// keep working.
///
/// Failures (bad decode, model load error) are reported through
/// [DamageCheckResult.available] rather than thrown, so a scan still completes
/// with damage marked unavailable.
class DamageDetectionService {
  /// Cardboard boxes: YOLO11n at 416 px (`results/boxes.onnx`, repaired).
  ///
  /// 0.35 measured over real photos: fires on 42 of 60 damaged boxes and 4 of
  /// 60 clean ones. Test-set F1 0.53 / mAP50 0.51 (`results/Boxes`).
  static final DamageDetectionService box = DamageDetectionService(
    modelAsset: 'assets/box_damage_yolo11n_int8.onnx',
    inputSize: 416,
    // names = {0: 'Label_aberration', 1: 'Structural_Deformation'}
    classNames: const {0: 'Label aberration', 1: 'Structural deformation'},
    confThreshold: 0.35,
    subject: 'box',
  );

  /// Bottles: YOLOv8n at 416 px (`results/bottles.onnx`, repaired).
  ///
  /// 0.35 is the F1 optimum of the bottle confidence sweep
  /// (`results/Bottles/confidence_sweep.csv`: P 0.71, R 0.54, F1 0.61).
  static final DamageDetectionService bottle = DamageDetectionService(
    modelAsset: 'assets/bottle_damage_yolov8n_int8.onnx',
    inputSize: 416,
    // names = {0: 'label_abberation'}
    classNames: const {0: 'Label aberration'},
    confThreshold: 0.35,
    subject: 'bottle',
  );

  /// Foil packaging (sachets, blister packs): YOLOv5nu at 416 px
  /// (`results/Foils/model/yolov5nu_416_int8.onnx`, repaired).
  ///
  /// 0.25 from the foil confidence sweep (`results/Foils/csv/confidence_sweep.csv`:
  /// P 0.71, R 0.82, F1 0.76) — within 0.003 F1 of the lowest thresholds but
  /// with better precision.
  ///
  /// Class 0 is an explicit "No-Damage" class, so its boxes are skipped
  /// rather than reported as damage.
  static final DamageDetectionService foil = DamageDetectionService(
    modelAsset: 'assets/foil_damage_yolov5nu_int8.onnx',
    inputSize: 416,
    // names = {0: 'No-Damage', 1: 'Structural_Deformation'}
    classNames: const {0: 'No damage', 1: 'Structural deformation'},
    nonDamageClasses: const {0},
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

  /// IoU above which two same-class boxes are treated as duplicates in NMS.
  static const double _iouThreshold = 0.45;

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
  /// a colour gradient, then fixed-seed noise. Both repaired 416 px models
  /// score well above zero on at least one; a dead head scores exactly 0 on
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

  Future<DamageCheckResult> check(List<String> photoPaths) async {
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
      }
    }
    debugPrint('Damage: scanned ${photoPaths.length} $subject photo(s); '
        'damaged=$anyDamaged; classes=${allDetections.toSet()}');

    if (!anySucceeded) {
      return DamageCheckResult(
        available: false,
        message: 'Damage check unavailable (inference failed).',
        timings: timings.build(),
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
    );
  }

  /// Decodes and letterboxes one photo. Runs on a background isolate.
  ///
  /// Everything in here is pure Dart over a multi-megapixel still: the JPEG
  /// decode alone runs into seconds on a phone, and the CHW conversion walks
  /// every input pixel on top of that. On the UI isolate — where this used to
  /// live — that is a hard freeze for the whole scan, which is exactly what
  /// made damage checks look like the app had hung.
  static _Preprocessed _preprocessWorker((String, int) request) {
    final (path, inputSize) = request;
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
    final pre = await compute(_preprocessWorker, (path, inputSize));
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
