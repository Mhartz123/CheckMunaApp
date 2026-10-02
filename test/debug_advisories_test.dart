import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';
import 'package:ui_prototype/services/debug_advisories.dart';
import 'package:ui_prototype/widgets/debug_advisory_sheet.dart';

void main() {
  late Directory tmp;
  final debug = DebugAdvisories.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('debug_advisories_test');
    DebugAdvisories.debugDirectory = tmp;
    debug.resetForTest();
  });

  tearDown(() {
    DebugAdvisories.debugDirectory = null;
    debug.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  group('matching', () {
    test('needs every typed word on the front panel', () async {
      await debug.add('Kremil-S');
      expect(debug.match('KREMIL-S\nChewable Tablet'), isNotNull);
      expect(debug.match('KREMIL\nChewable Tablet'), isNull);
    });

    test('a single typed brand word is enough', () async {
      await debug.add('biogesic');
      final match = debug.match('BIOGESIC\nParacetamol 500 mg Tablet');
      expect(match, isNotNull);
      expect(match!.productName, 'biogesic');
      expect(match.advisoryNumber, DebugAdvisories.advisoryNumber);
    });

    test('tolerates one OCR misread on a longer word', () async {
      await debug.add('Biogesic');
      expect(debug.match('BIOGES1C Paracetamol'), isNotNull);
    });

    test('matches whole words, not substrings', () async {
      await debug.add('Neo');
      expect(debug.match('NEOZEP Forte'), isNull);
    });

    test('nothing matches with no entries', () {
      expect(debug.match('BIOGESIC'), isNull);
    });
  });

  group('the list', () {
    test('ignores blanks and case-insensitive duplicates', () async {
      expect(await debug.add('   '), isFalse);
      expect(await debug.add('Biogesic'), isTrue);
      expect(await debug.add('  BIOGESIC '), isFalse);
      expect(debug.names, ['Biogesic']);
    });

    test('survives a restart', () async {
      await debug.add('Biogesic');
      await debug.add('Kremil-S');
      await debug.remove('Biogesic');

      debug.resetForTest();
      await debug.ensureLoaded();
      expect(debug.names, ['Kremil-S']);
    });
  });

  group('through the engine', () {
    Future<ScanRecord> analyze(String front) => ComplianceEngine.analyzeLabel(
          textBySlot: {
            PhotoSlot.front: front,
            PhotoSlot.expiration: 'EXP 10/2099',
            PhotoSlot.ingredients: 'Paracetamol 500 mg',
          },
          combinedText: front,
          dateCode: DateCode(
            expiry: DateTime(2099, 10, 31),
            status: DateCodeStatus.parsed,
          ),
          packagingType: PackagingType.box,
        );

    test('a debug entry turns the scan into a marked Warning', () async {
      await debug.add('Biogesic');
      final record = await analyze('BIOGESIC\nParacetamol 500 mg Tablet');

      expect(record.status, ComplianceStatus.warning);
      expect(record.reasons.single, startsWith(DebugAdvisories.reasonPrefix));
      expect(record.reasons.single, contains('Not a real FDA advisory'));
    });

    test('without the entry the same scan is compliant', () async {
      final record = await analyze('BIOGESIC\nParacetamol 500 mg Tablet');
      expect(record.status, ComplianceStatus.compliant);
    });
  });

  group('hidden trigger', () {
    Future<void> tapLogo(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byType(DebugAdvisoryTrigger));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Widget app() => const MaterialApp(
          home: Scaffold(
            body: DebugAdvisoryTrigger(
              child: SizedBox(width: 40, height: 40),
            ),
          ),
        );

    testWidgets('six taps show nothing', (tester) async {
      await tester.pumpWidget(app());
      await tapLogo(tester, 6);
      expect(find.byType(DebugAdvisorySheet), findsNothing);
    });

    testWidgets('seven quick taps open the sheet', (tester) async {
      await tester.pumpWidget(app());
      await tapLogo(tester, 7);
      expect(find.byType(DebugAdvisorySheet), findsOneWidget);
    });

    testWidgets('a pause resets the count', (tester) async {
      await tester.pumpWidget(app());
      await tapLogo(tester, 4);
      await tester.pump(const Duration(seconds: 2));
      await tapLogo(tester, 4);
      expect(find.byType(DebugAdvisorySheet), findsNothing);
    });
  });
}
