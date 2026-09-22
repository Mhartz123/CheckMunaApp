import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../models/scan_record.dart';
import 'app_prefs.dart';
import 'scan_store.dart';

/// Downscale ladder for uploaded photos: longest edge in pixels, then JPEG
/// quality. The first rung whose output fits [_maxImageBytes] wins; if none
/// do, the smallest is sent anyway rather than nothing.
///
/// Top-level so [_downscaleWorker] can read them — it runs on a background
/// isolate and can't reach [ReportService]'s private statics.
const List<(int, int)> _downscaleSteps = [(900, 78), (720, 65), (560, 50)];

/// Ceiling for one uploaded photo, before base64 (which adds about a third).
/// The dashboard shows these at a few hundred pixels wide, so this is sized
/// for the overlay to stay legible, not for archival quality — the full-
/// resolution originals never leave the phone.
const int _maxImageBytes = 200 * 1024;

/// Shrinks each photo to a `data:image/jpeg;base64,...` URL, or null for one
/// that can't be read or decoded.
///
/// Runs on a background isolate via [compute]: decoding and re-encoding four
/// multi-megapixel stills is seconds of pure Dart, and submit is called
/// straight after a save, while the user is looking at the result screen.
///
/// [img.bakeOrientation] applies the EXIF rotation and the re-encode drops the
/// tag with it, so the uploaded bytes are already the right way up. That is
/// what keeps the dashboard's damage overlay aligned: [DamageDetection]'s
/// coordinates are normalised against the *oriented* photo, so a browser
/// rotating the image a second time would slide every box off its damage.
///
/// The whole list is done in one call — [compute] spawns an isolate per
/// invocation, and four of those costs more than the work itself.
List<String?> _downscaleWorker(List<String> paths) =>
    paths.map(_downscaleOne).toList();

String? _downscaleOne(String path) {
  try {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);

    Uint8List? smallest;
    for (final (edge, quality) in _downscaleSteps) {
      // Never upscale: a photo already smaller than the rung is re-encoded at
      // that quality but keeps its dimensions.
      final longest =
          oriented.width > oriented.height ? oriented.width : oriented.height;
      final scaled = longest <= edge
          ? oriented
          : img.copyResize(
              oriented,
              width: oriented.width >= oriented.height ? edge : null,
              height: oriented.height > oriented.width ? edge : null,
            );
      final bytes = img.encodeJpg(scaled, quality: quality);
      smallest = bytes;
      if (bytes.lengthInBytes <= _maxImageBytes) break;
    }
    if (smallest == null) return null;
    return 'data:image/jpeg;base64,${base64Encode(smallest)}';
  } catch (_) {
    // A photo that won't encode costs the dashboard a preview, not the
    // record — the scan is already saved on the device either way.
    return null;
  }
}

/// Submits scan results to the CheckMuna central dashboard hosted on
/// Vercel + Supabase.
///
/// Nothing is sent unless the user has given current, explicit consent on
/// the data-sharing notice ([AppPrefs.sharingAllowed]) — see ConsentScreen.
/// The camera screen also lets the user withhold a single scan.
///
/// Every shared scan is submitted, not just flagged ones — the dashboard needs
/// clean results too, otherwise it can't show how many boxes came back
/// undamaged or what share of labels passed.
///
/// The payload mirrors [ScanRecord.kind]: a label scan carries the label
/// block, a damage scan carries the damage block, and an inspection scan
/// ([ScanKind.both]) carries both. The server splits these across its
/// `report_label_checks` / `report_damage_checks` tables accordingly.
///
/// Setup:
///   1. Deploy the website folder to Vercel (see its README.md)
///   2. Replace _endpoint below with your actual Vercel URL
///   3. Make sure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set
///      in Vercel Project Settings → Environment Variables
class ReportService {
  // ── CONFIGURE THIS ─────────────────────────────────────────────────────────
  // Replace with your actual Vercel deployment URL, e.g.:
  //   https://your-project-name.vercel.app/api/report
  //
  // DO NOT use http://localhost or a LAN IP here — those only work
  // when the server is running on the same network.
  static const String _endpoint =
      'https://label-check-website.vercel.app/api/report';

  // Set to false to disable image uploads (saves bandwidth / Supabase storage).
  // With this off the dashboard still gets every finding, just no previews.
  static const bool _includeImage = true;
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a scan result. Returns true on success, false on any failure.
  /// Network errors are non-fatal — the scan is already saved on the device,
  /// so a failed submit only means the dashboard misses this row.
  static Future<bool> submit({
    required Directory recordDir,
    required ScanRecord record,
    required String productName,
  }) async {
    // Informed consent is a hard gate: no answer, an answer to an older
    // version of the notice, or "no" all mean nothing leaves the phone.
    if (!AppPrefs.instance.sharingAllowed) return false;

    // Skip if endpoint hasn't been configured yet
    if (_endpoint.contains('YOUR_PROJECT_NAME')) {
      return false;
    }

    try {
      final payload = await _buildPayload(
        recordDir: recordDir,
        record: record,
        productName: productName,
      );

      final response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200;
    } catch (e) {
      // Network errors are non-fatal — the scan is already saved locally.
      return false;
    }
  }

  /// The packaging capture slot a photo came from ('front', 'side1', …), or
  /// null for a file that isn't one of them. The dashboard captions a photo
  /// with this; without it the photo is labelled by position instead.
  static String? _slotName(File f) {
    final base = p.basenameWithoutExtension(f.path);
    for (final slot in BoxSlot.values) {
      if (slot.fileBaseName == base) return slot.name;
    }
    return null;
  }

  static Future<Map<String, dynamic>> _buildPayload({
    required Directory recordDir,
    required ScanRecord record,
    required String productName,
  }) async {
    // The packaging shots, in the order the detector was fed them — the order
    // DamageDetection.sourceIndex indexes into.
    final boxPhotos = ScanStore.boxPhotosInOrder(recordDir);
    // The record's cover photo: the first label close-up, or the first
    // packaging shot on a damage-only scan.
    final all = ScanStore.photosInOrder(recordDir);
    final cover = all.isNotEmpty ? all.first : null;

    // Encoded once each. On a damage-only scan the cover *is* the first
    // packaging shot, and shrinking a multi-megapixel still twice is a second
    // of work for a byte-identical result.
    var encoded = <String, String>{};
    if (_includeImage) {
      final paths = <String>{
        if (cover != null) cover.path,
        ...boxPhotos.map((f) => f.path),
      }.toList();
      if (paths.isNotEmpty) {
        final results = await compute(_downscaleWorker, paths);
        for (var i = 0; i < paths.length; i++) {
          final data = results[i];
          if (data != null) encoded[paths[i]] = data;
        }
      }
    }

    final imageBase64 = cover == null ? null : encoded[cover.path];

    // One entry per packaging photo, in capture order, INCLUDING any that
    // failed to encode. The server numbers these by position and drops the
    // empty ones, so a photo that couldn't be read leaves a gap rather than
    // shifting every later photo out from under the detections that point at
    // it by sourceIndex.
    final images = boxPhotos.map((f) {
      final data = encoded[f.path];
      return {
        'slot': _slotName(f),
        if (data != null) 'imageBase64': data,
      };
    }).toList();

    final damage = record.damageCheck;

    return {
      'id': '${DateTime.now().millisecondsSinceEpoch}_${productName.hashCode.abs()}',
      // Which check(s) this record represents — drives how the server splits
      // the blocks below across its per-check tables.
      'kind': record.kind.name,
      // Null for a label-only scan; the packaging the damage step ran against.
      'packagingType': record.packagingType?.name,
      // The name the user saved the record under.
      'productName': productName,
      'status': record.statusLabel,
      'matchedKeyword': record.matchedKeyword,
      'reasons': record.reasons,
      'scannedAt': record.scannedAt.toIso8601String(),
      if (imageBase64 != null) 'imageBase64': imageBase64,

      // ── Label block — omitted entirely for a damage-only scan ──
      if (record.hasLabelData)
        'label': {
          // What OCR read off the front label, as opposed to productName
          // above which is the user's own record name.
          'detectedProductName': record.productName,
          'expiration': record.expiration,
          'ingredients': record.ingredients,
          'extractedText': record.extractedText,
        },

      // ── Damage block — omitted entirely for a label-only scan ──
      if (record.hasDamageData)
        'damage': {
          'available': damage.available,
          'message': damage.message,
          'isDamaged': damage.isDamaged,
          // Per-detection class names, e.g. ['Dent', 'Dent', 'Scratches'].
          'detections': damage.detections,
          // Same detections with geometry: normalised 0..1 rect on the source
          // photo, per-detection confidence, and which packaging shot it came
          // from. Lets the dashboard redraw the overlay the app showed.
          'boxes': damage.boxes.map((b) => b.toJson()).toList(),
          'maxConfidence': damage.maxConfidence,
          // Per-photo latency and confidence figures (see DamageSessionReport).
          // Additive: a server that does not know the field ignores it.
          if (damage.report != null) 'report': damage.report!.toJson(),
          // The photos those boxes are drawn on. Without these the dashboard
          // can say a box was dented but not show it.
          if (_includeImage) 'images': images,
        },
    };
  }
}
