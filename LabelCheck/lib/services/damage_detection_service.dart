import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../models/scan_record.dart';

class _SingleImageResult {
  final bool isDamaged;

  /// Class name of each surviving detection.
  final List<String> detections;

  /// Confidence of each surviving detection, index-aligned with [detections].
  final List<double> scores;

  final double maxConfidence;

  const _SingleImageResult({
    required this.isDamaged,
    required this.detections,
    required this.scores,
    required this.maxConfidence,
  });
}

/// One decoded detection box (in 640×640 letterbox space) with its score and
/// class index. Coordinates are only used for NMS overlap — the app reports
/// classes/confidence, not box geometry, so we never map them back to the
/// original image.
class _Det {
  final double x1, y1, x2, y2, score;
  final int cls;
  const _Det(this.x1, this.y1, this.x2, this.y2, this.score, this.cls);
}

/// Packaging-damage check backed by an **on-device** YOLO11n model
/// (`assets/damage_yolo11n.onnx`), run through the `onnxruntime` engine already
/// bundled for the semantic matcher. No network, no API key, no per-scan cost —
/// scans work fully offline.
///
/// Pipeline per box photo: decode → letterbox to 640 → CHW float32 (÷255) →
/// model → decode the [1, 4+nc, 8400] output → confidence filter → class-aware
/// NMS. Any surviving detection counts as damage, and each box side that comes
/// back dirty becomes one [DamageFinding] so the report can say *where* the
/// damage is and how bad the model thinks it is.
///
/// The shipped model is single-class, so it cannot say what *kind* of damage
/// it found — see [_classNames].
///
/// Failures (bad decode, model load error) are reported through
/// [DamageCheckResult.available] rather than thrown, so a scan still completes
/// with damage marked unavailable.
class DamageDetectionService {
  static const String _modelAsset = 'assets/damage_yolo11n.onnx';
  static const int _inputSize = 640;

  /// Class index → display name. The shipped YOLO11n model has a single generic
  /// damage class (metadata `names = {0: 'Damage-detection-on-medicine-v2'}`,
  /// trained on a `nc: 1` dataset), mapped here to a clean label for the UI.
  /// It therefore reports *that* a box is damaged, not what kind of damage it
  /// is. To report dent/tear/crush separately, re-annotate the dataset with
  /// those classes, retrain, and add the new indices here — the name flows
  /// through [DamageFinding.label] into the reports with no other app change.
  static const Map<int, String> _classNames = {0: 'Damage'};

  /// Minimum class score for a detection to survive, and IoU above which two
  /// same-class boxes are treated as duplicates during NMS. 0.40 matches the
  /// confidence Roboflow was configured with, and suppresses borderline
  /// false positives (a random non-box image scored a spurious ~0.25 box).
  static const double _confThreshold = 0.40;
  static const double _iouThreshold = 0.45;

  static Future<OrtSession>? _sessionLoad;

  /// Loads the ONNX session once; later calls reuse the same in-flight/loaded
  /// session. Safe to call from warm-up and from [check] concurrently.
  static Future<OrtSession> _session() => _sessionLoad ??= _loadSession();

  static Future<OrtSession> _loadSession() async {
    OrtEnv.instance.init();
    final raw = await rootBundle.load(_modelAsset);
    return OrtSession.fromBuffer(
      raw.buffer.asUint8List(),
      OrtSessionOptions(),
    );
  }

  /// Kicks off the model load early (e.g. from CameraScreen.initState) so the
  /// first scan doesn't pay full load latency. Errors are swallowed — [check]
  /// re-reports them if loading truly failed.
  static Future<void> warmUp() async {
    try {
      await _session();
    } catch (e) {
      debugPrint('Damage model warm-up failed: $e');
    }
  }

  /// Runs the detector over each captured box side. Keying by [BoxSlot] (rather
  /// than a bare path list) is what lets a finding name the side it came from.
  static Future<DamageCheckResult> check(
      Map<BoxSlot, String> photoPathsBySlot) async {
    if (photoPathsBySlot.isEmpty) {
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
      return const DamageCheckResult(
        available: false,
        message: 'Damage check unavailable (model failed to load).',
      );
    }

    final findings = <DamageFinding>[];
    var anySucceeded = false;
    var maxConfidence = 0.0;

    // Iterate BoxSlot.values (not the map) so findings are always ordered
    // front → side → side → back regardless of capture/insertion order.
    for (final slot in BoxSlot.values) {
      final path = photoPathsBySlot[slot];
      if (path == null) continue;
      try {
        final result = _checkOne(session, path);
        anySucceeded = true;
        debugPrint('Damage[${slot.sideName}] '
            '${result.detections.isEmpty ? 'clean' : result.detections.join(', ')}'
            ' (max ${(result.maxConfidence * 100).toStringAsFixed(0)}%)');
        if (!result.isDamaged) continue;

        // One finding per side per damage type, so a multi-class retrain
        // reports "Front — Dent" and "Front — Tear" separately.
        final spotsByLabel = <String, int>{};
        final confByLabel = <String, double>{};
        for (var i = 0; i < result.detections.length; i++) {
          final label = result.detections[i];
          spotsByLabel[label] = (spotsByLabel[label] ?? 0) + 1;
          final score = result.scores[i];
          if (score > (confByLabel[label] ?? 0.0)) confByLabel[label] = score;
        }
        for (final entry in spotsByLabel.entries) {
          findings.add(DamageFinding(
            slot: slot,
            label: entry.key,
            spotCount: entry.value,
            confidence: confByLabel[entry.key] ?? 0.0,
          ));
        }
        if (result.maxConfidence > maxConfidence) {
          maxConfidence = result.maxConfidence;
        }
      } catch (e) {
        debugPrint('Damage check failed for $path: $e');
      }
    }

    final anyDamaged = findings.isNotEmpty;
    debugPrint('Damage: scanned ${photoPathsBySlot.length} box photo(s); '
        'damaged=$anyDamaged; sides=${findings.map((f) => f.slot.sideName)}');

    if (!anySucceeded) {
      return const DamageCheckResult(
        available: false,
        message: 'Damage check unavailable (inference failed).',
      );
    }

    final sides = findings.map((f) => f.slot.sideName).toSet().join(', ');
    final message = anyDamaged
        ? 'Packaging damage detected on: $sides.'
        : 'No packaging damage detected on any side.';

    return DamageCheckResult(
      available: true,
      message: message,
      isDamaged: anyDamaged,
      findings: findings,
      maxConfidence: maxConfidence,
    );
  }

  /// Runs one box photo through the model and returns its surviving detections.
  static _SingleImageResult _checkOne(OrtSession session, String path) {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Could not decode image at $path');
    }
    final oriented = img.bakeOrientation(decoded);

    // ── Letterbox to 640×640 (preserve aspect ratio, pad with gray 114) ──
    final scale =
        math.min(_inputSize / oriented.width, _inputSize / oriented.height);
    final newW = (oriented.width * scale).round();
    final newH = (oriented.height * scale).round();
    final resized = img.copyResize(oriented, width: newW, height: newH);

    final canvas = img.Image(width: _inputSize, height: _inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    final padX = ((_inputSize - newW) / 2).round();
    final padY = ((_inputSize - newH) / 2).round();
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    // ── HWC uint8 → CHW float32, RGB, normalized 0..1 ──
    final input = Float32List(3 * _inputSize * _inputSize);
    final plane = _inputSize * _inputSize;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final p = canvas.getPixel(x, y);
        final idx = y * _inputSize + x;
        input[idx] = p.r / 255.0; // R plane
        input[plane + idx] = p.g / 255.0; // G plane
        input[2 * plane + idx] = p.b / 255.0; // B plane
      }
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      input,
      [1, 3, _inputSize, _inputSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs;
    try {
      outputs = session.run(
        runOptions,
        {'images': inputTensor},
        const ['output0'],
      );
    } finally {
      inputTensor.release();
      runOptions.release();
    }

    // output0: [1, 4+nc, 8400] → strip batch, get the 4+nc channel rows.
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
      if (bestScore < _confThreshold || bestCls < 0) continue;

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
    final scores = <double>[];
    var maxConfidence = 0.0;
    for (final d in kept) {
      detections.add(_classNames[d.cls] ?? 'Damage');
      scores.add(d.score);
      if (d.score > maxConfidence) maxConfidence = d.score;
    }

    return _SingleImageResult(
      isDamaged: detections.isNotEmpty,
      detections: detections,
      scores: scores,
      maxConfidence: maxConfidence,
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
