import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/scan_record.dart';
import 'scan_store.dart';

/// Submits flagged (NON-COMPLIANT or BANNED) scan results to the
/// LabelCheck central dashboard hosted on Vercel + Supabase.
///
/// Setup:
///   1. Deploy the server folder to Vercel (see README.md in server folder)
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
  static const bool _includeImage = true;

  // Max image size in bytes included in the payload (default 200 KB).
  static const int _maxImageBytes = 200 * 1024;
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a scan result. Only flagged records are sent — a non-compliant or
  /// banned label check, or a damage check that found damage. Returns true on
  /// success, false on failure or if the record is clean.
  static Future<bool> submit({
    required Directory recordDir,
    required ScanRecord record,
    required String productName,
  }) async {
    final flagged = record.isDamageCheck
        ? record.damageCheck.available && record.damageCheck.isDamaged
        : record.status != ComplianceStatus.compliant;
    if (!flagged) return false;

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
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (e) {
      // Network errors are non-fatal — the scan is already saved locally.
      return false;
    }
  }

  static Future<Map<String, dynamic>> _buildPayload({
    required Directory recordDir,
    required ScanRecord record,
    required String productName,
  }) async {
    String? imageBase64;

    if (_includeImage) {
      final photos = ScanStore.photosInOrder(recordDir);
      if (photos.isNotEmpty) {
        final bytes = await photos.first.readAsBytes();
        if (bytes.lengthInBytes <= _maxImageBytes) {
          imageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        }
      }
    }

    // The dashboard reads scanType to route a submission to the right report:
    // label checks carry the OCR/FDA fields, damage checks carry the detector
    // findings. Both keep the shared envelope (id, name, status, reasons).
    return {
      'id': '${DateTime.now().millisecondsSinceEpoch}_${productName.hashCode.abs()}',
      'scanType': record.type.id,
      'productName': productName,
      'status': record.statusLabel,
      'matchedKeyword': record.matchedKeyword,
      'reasons': record.reasons,
      'scannedAt': record.scannedAt.toIso8601String(),
      if (record.isLabelCheck) ...{
        'detectedProductName': record.productName,
        'expiration': record.expiration,
        'allLabelsPresent': record.allLabelsPresent,
        'ingredients': record.ingredients,
        'extractedText': record.extractedText,
      },
      if (record.isDamageCheck) ...{
        'isDamaged': record.damageCheck.isDamaged,
        'damageTypes': record.damageCheck.damageTypes,
        'affectedSides': record.damageCheck.affectedSides,
        'damageSpots': record.damageCheck.totalSpots,
        'maxConfidence': record.damageCheck.maxConfidence,
        'findings': [
          for (final f in record.damageCheck.findings) f.toJson(),
        ],
      },
      if (imageBase64 != null) 'imageBase64': imageBase64,
    };
  }
}