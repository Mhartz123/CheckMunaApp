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

/// Small app-wide preferences: whether onboarding has been seen, and the
/// user's data-sharing consent.
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
  SharingDecision? _decision;
  int? _decisionVersion;
  DateTime? _decidedAt;

  /// Overrides the storage location. Tests point this at a temp folder so
  /// they don't need path_provider's platform channel.
  @visibleForTesting
  static Directory? debugDirectory;

  bool get onboardingDone => _onboardingDone;

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
    _decision = null;
    _decisionVersion = null;
    _decidedAt = null;
  }
}
