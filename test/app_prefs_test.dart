import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/app_prefs.dart';
import 'package:ui_prototype/services/report_service.dart';

/// Consent is the gate that decides whether scan photos leave the phone, so
/// every way it can be missing or stale has to fail closed.
void main() {
  late Directory tmp;
  final prefs = AppPrefs.instance;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('app_prefs_test');
    AppPrefs.debugDirectory = tmp;
    prefs.resetForTest();
  });

  tearDown(() {
    AppPrefs.debugDirectory = null;
    prefs.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  File prefsFile() => File('${tmp.path}/app_prefs.json');

  test('a fresh install has not onboarded and has not consented', () async {
    await prefs.load();
    expect(prefs.onboardingDone, isFalse);
    expect(prefs.needsConsent, isTrue);
    expect(prefs.sharingAllowed, isFalse);
  });

  test('onboarding and consent survive a restart', () async {
    await prefs.completeOnboarding();
    await prefs.setSharingDecision(SharingDecision.granted);

    prefs.resetForTest();
    await prefs.load();

    expect(prefs.onboardingDone, isTrue);
    expect(prefs.decision, SharingDecision.granted);
    expect(prefs.sharingAllowed, isTrue);
    expect(prefs.decidedAt, isNotNull);
  });

  test('declining is remembered and blocks sharing', () async {
    await prefs.setSharingDecision(SharingDecision.declined);
    prefs.resetForTest();
    await prefs.load();

    expect(prefs.needsConsent, isFalse);
    expect(prefs.sharingAllowed, isFalse);
  });

  test('consent given to an older notice no longer counts', () async {
    prefsFile().writeAsStringSync(jsonEncode({
      'onboardingDone': true,
      'consent': {
        'decision': 'granted',
        'version': AppPrefs.consentVersion - 1,
        'decidedAt': '2026-01-01T00:00:00.000',
      },
    }));
    await prefs.load();

    expect(prefs.onboardingDone, isTrue);
    expect(prefs.needsConsent, isTrue);
    expect(prefs.sharingAllowed, isFalse);
  });

  test('a corrupt prefs file falls back to asking again', () async {
    prefsFile().writeAsStringSync('{not json');
    await prefs.load();
    expect(prefs.onboardingDone, isFalse);
    expect(prefs.sharingAllowed, isFalse);
  });

  test('ReportService uploads nothing without consent', () async {
    final record = ScanRecord(
      kind: ScanKind.label,
      status: ComplianceStatus.compliant,
      matchedKeyword: '—',
      reasons: const [],
      productName: 'Apple Cider',
      expiration: '—',
      ingredients: '—',
      extractedText: '',
      damageCheck:
          const DamageCheckResult(available: false, message: 'Not run.'),
      scannedAt: DateTime.parse('2026-09-05T10:00:00.000'),
    );

    for (final decision in [null, SharingDecision.declined]) {
      prefs.resetForTest();
      if (decision != null) await prefs.setSharingDecision(decision);
      // Returns before touching the network: the record folder doesn't even
      // need to exist.
      final sent = await ReportService.submit(
        recordDir: Directory('${tmp.path}/missing'),
        record: record,
        productName: 'Apple Cider',
      );
      expect(sent, isFalse, reason: 'decision: $decision');
    }
  });
}
