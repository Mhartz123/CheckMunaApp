import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The user's answer to the data-sharing notice.
enum SharingDecision {
  /// Scans (photos + results) are uploaded to the FDA monitoring dashboard.
  granted,

  /// Scans stay on the phone. Nothing is uploaded.
  declined,
}

/// How thoroughly a label capture is read, trading inference time for
/// accuracy.
///
/// The two modes differ in ONE thing: how many frames each label slot is
/// photographed with. Everything downstream — preprocessing, the dual
/// original/enhanced recognition, the date-code parser — is identical, so a
/// scan in either mode goes through the same decision logic and only the
/// evidence behind it changes.
enum OcrMode {
  /// Three frames per label slot, fused word by word (`OcrFusion`), so a word
  /// one frame misreads is repaired by the two that read it correctly. Roughly
  /// three times the recognition cost of [fast]. The default.
  accurate,

  /// One frame per label slot — the pipeline as it stood before multi-shot
  /// capture. The extra frames only pay for themselves when the capture is
  /// marginal (shake, glare, a dot-matrix date); on a sharp, well-lit label
  /// the single frame reaches the same answer in a third of the time.
  fast,
}

extension OcrModeX on OcrMode {
  /// Frames taken per label slot.
  int get frameCount => switch (this) {
        OcrMode.accurate => 3,
        OcrMode.fast => 1,
      };

  String get label => switch (this) {
        OcrMode.accurate => 'Accurate',
        OcrMode.fast => 'Fast',
      };

  /// One line for the mode picker, describing the trade rather than the
  /// implementation.
  String get description => switch (this) {
        OcrMode.accurate =>
          'Three shots per step, combined into one reading. Slower, and the '
              'one to use when the light is poor or the print is small.',
        OcrMode.fast =>
          'One shot per step. About three times faster to read, and just as '
              'accurate when the label is sharp and well lit.',
      };
}

/// Small app-wide preferences: whether onboarding has been seen, the user's
/// data-sharing consent, and which [OcrMode] label captures run in.
///
/// Stored as one JSON file in the app documents directory, the same
/// dependency-free approach [ThemeController] uses for the theme.
///
/// Consent is recorded with the [consentVersion] of the notice the user
/// actually read and when they answered. If the notice's wording changes in a
/// way that matters (what is collected, who sees it), bump [consentVersion]
/// and every user is asked again. Until they answer, nothing is uploaded.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();

  static final AppPrefs instance = AppPrefs._();

  static const String _fileName = 'app_prefs.json';

  /// Version of the data-sharing notice text in `ConsentScreen`. A stored
  /// decision given against an older version no longer counts.
  static const int consentVersion = 1;

  bool _onboardingDone = false;
  OcrMode _ocrMode = OcrMode.accurate;
  SharingDecision? _decision;
  int? _decisionVersion;
  DateTime? _decidedAt;

  /// Overrides the storage location. Tests point this at a temp folder so
  /// they don't need path_provider's platform channel.
  @visibleForTesting
  static Directory? debugDirectory;

  bool get onboardingDone => _onboardingDone;

  /// Which reading mode label captures use. Defaults to [OcrMode.accurate]:
  /// a slow correct answer is the one this app exists to give, so the faster
  /// mode is something the user opts into once they can see their captures
  /// are clean.
  OcrMode get ocrMode => _ocrMode;

  /// The current, still-valid decision, or null if the user has never
  /// answered or answered an older version of the notice.
  SharingDecision? get decision =>
      _decisionVersion == consentVersion ? _decision : null;

  DateTime? get decidedAt => decision == null ? null : _decidedAt;

  /// True when the user must be shown the consent screen before using the app.
  bool get needsConsent => decision == null;

  /// The only gate the upload path checks. Anything short of an explicit,
  /// current "yes" means no upload.
  bool get sharingAllowed => decision == SharingDecision.granted;

  static Future<File> _file() async {
    final dir = debugDirectory ?? await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Reads the stored preferences. Call once before `runApp`. A missing or
  /// corrupt file leaves the safe defaults: onboarding not done, no consent.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _onboardingDone = map['onboardingDone'] == true;
      _ocrMode = _ocrModeFromName(map['ocrMode'] as String?);
      final consent = map['consent'];
      if (consent is Map<String, dynamic>) {
        _decision = switch (consent['decision']) {
          'granted' => SharingDecision.granted,
          'declined' => SharingDecision.declined,
          _ => null,
        };
        _decisionVersion = (consent['version'] as num?)?.toInt();
        _decidedAt = DateTime.tryParse(consent['decidedAt'] as String? ?? '');
      }
    } catch (_) {
      // Keep defaults. Asking again is the safe failure mode for consent.
    }
  }

  Future<void> completeOnboarding() async {
    if (_onboardingDone) return;
    _onboardingDone = true;
    notifyListeners();
    await _save();
  }

  Future<void> setOcrMode(OcrMode value) async {
    if (_ocrMode == value) return;
    _ocrMode = value;
    notifyListeners();
    await _save();
  }

  /// An unknown or missing name falls back to the default rather than
  /// throwing, so a prefs file written by a future build still loads.
  static OcrMode _ocrModeFromName(String? name) {
    for (final mode in OcrMode.values) {
      if (mode.name == name) return mode;
    }
    return OcrMode.accurate;
  }

  Future<void> setSharingDecision(SharingDecision value) async {
    _decision = value;
    _decisionVersion = consentVersion;
    _decidedAt = DateTime.now();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'onboardingDone': _onboardingDone,
        'ocrMode': _ocrMode.name,
        if (_decision != null)
          'consent': {
            'decision': _decision!.name,
            'version': _decisionVersion,
            'decidedAt': _decidedAt?.toIso8601String(),
          },
      }));
    } catch (e) {
      // In-memory state already applied. The worst case is the user being
      // asked again on the next launch, which is safe.
      debugPrint('Saving app prefs failed: $e');
    }
  }

  @visibleForTesting
  void resetForTest() {
    _onboardingDone = false;
    _ocrMode = OcrMode.accurate;
    _decision = null;
    _decisionVersion = null;
    _decidedAt = null;
  }
}
