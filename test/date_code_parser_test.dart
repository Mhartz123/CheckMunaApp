import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ui_prototype/services/date_code_parser.dart';

/// Fixed "today" so the ten-year horizon check is deterministic.
final DateTime _today = DateTime(2026, 8, 21);

TextLine _line(String text, Rect box) => TextLine(
      text: text,
      elements: const <TextElement>[],
      boundingBox: box,
      recognizedLanguages: const <String>[],
      cornerPoints: <math.Point<int>>[
        math.Point<int>(box.left.round(), box.top.round()),
        math.Point<int>(box.right.round(), box.top.round()),
        math.Point<int>(box.right.round(), box.bottom.round()),
        math.Point<int>(box.left.round(), box.bottom.round()),
      ],
      confidence: null,
      angle: null,
    );

/// Lines stacked in a single left-aligned column, one under the next.
List<TextLine> _stacked(List<String> texts) => <TextLine>[
      for (var i = 0; i < texts.length; i++)
        _line(texts[i], Rect.fromLTWH(20, 20 + i * 40, 180, 24)),
    ];

DateCode _parse(List<TextLine> lines) =>
    DateCodeParser.parseLines(lines, today: _today);

void main() {
  group('debossed carton sample', () {
    test('reads MFG and EXP off a stacked layout', () {
      final code = _parse(_stacked(<String>[
        'B.177T78',
        'MFG03/2026',
        'EXP03/2028',
      ]));

      expect(code.status, DateCodeStatus.parsed);
      expect(code.manufactured!.year, 2026);
      expect(code.manufactured!.month, 3);
      expect(code.expiry!.year, 2028);
      expect(code.expiry!.month, 3);
    });

    test('leaves the batch code alone through digit normalization', () {
      final code = _parse(_stacked(<String>[
        'B.177T78',
        'MFG03/2026',
        'EXP03/2028',
      ]));

      // The B and the T are real characters. A blanket O->0 / B->8 / T->7 pass
      // over the whole crop would have returned 8.177778.
      expect(code.batch, 'B.177T78');
    });
  });

  group('misaligned overprint', () {
    // The pre-printed label column and the overprinted values sit on different
    // baseline grids: each value drifts 24px up, against a 40px line pitch. So
    // 10/2028 is vertically nearer "Mfg. Date" than "Exp. Date", and
    // nearest-baseline association would report an expired product as fresh.
    List<TextLine> layout() => <TextLine>[
          _line('Batch No.', const Rect.fromLTWH(20, 100, 100, 22)),
          _line('Mfg. Date', const Rect.fromLTWH(20, 140, 100, 22)),
          _line('Exp. Date', const Rect.fromLTWH(20, 180, 100, 22)),
          _line('DBIK5A11', const Rect.fromLTWH(200, 76, 120, 22)),
          _line('11/2025', const Rect.fromLTWH(200, 116, 120, 22)),
          _line('10/2028', const Rect.fromLTWH(200, 156, 120, 22)),
        ];

    test('binds 10/2028 to Exp. Date, not to the nearer Mfg. Date', () {
      final code = _parse(layout());

      expect(code.status, DateCodeStatus.parsed);
      expect(code.expiry!.year, 2028);
      expect(code.expiry!.month, 10);
      expect(code.manufactured!.year, 2025);
      expect(code.manufactured!.month, 11);
    });

    test('the drift really would defeat nearest-baseline matching', () {
      final lines = layout();
      final expiryValue = lines[5].boundingBox.center.dy; // 10/2028 -> 167
      final mfgLabel = lines[1].boundingBox.center.dy; //     Mfg.   -> 151
      final expLabel = lines[2].boundingBox.center.dy; //     Exp.   -> 191

      expect((expiryValue - mfgLabel).abs(),
          lessThan((expiryValue - expLabel).abs()));
    });

    test('reads the batch value out of the value column', () {
      expect(_parse(layout()).batch, 'DBIK5A11');
    });
  });

  group('structural validation', () {
    test('rejects an impossible month', () {
      final code = _parse(_stacked(<String>['EXP 13/2025']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.expiry, isNull);
    });

    test('rejects an expiry before the manufacture date', () {
      final code = _parse(_stacked(<String>['MFG 03/2028', 'EXP 03/2026']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.expiry, isNull);
      expect(code.manufactured, isNull);
      expect(code.note, contains('not after'));
    });

    test('rejects a shelf life under six months', () {
      final code = _parse(_stacked(<String>['MFG 01/2026', 'EXP 03/2026']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.note, contains('months'));
    });

    test('rejects a shelf life over seventy-two months', () {
      final code = _parse(_stacked(<String>['MFG 01/2026', 'EXP 01/2035']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.note, contains('months'));
    });

    test('accepts the shelf life bounds themselves', () {
      final atFloor = _parse(_stacked(<String>['MFG 01/2026', 'EXP 07/2026']));
      expect(atFloor.status, DateCodeStatus.parsed);

      final atCeiling = _parse(_stacked(<String>['MFG 01/2026', 'EXP 01/2032']));
      expect(atCeiling.status, DateCodeStatus.parsed);
    });

    test('rejects an expiry more than ten years out', () {
      final code = _parse(_stacked(<String>['EXP 03/2044']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.expiry, isNull);
    });

    test('an unreadable code never carries a usable date', () {
      final code = _parse(_stacked(<String>['no code here at all']));

      expect(code.status, DateCodeStatus.unreadable);
      expect(code.expiry, isNull);
      expect(code.manufactured, isNull);
      expect(code.note, isNotNull);
    });
  });

  group('unlabelled codes', () {
    test('two bare dates: the later one is the expiry', () {
      final code = _parse(_stacked(<String>['03/2026', '03/2028']));

      expect(code.manufactured!.year, 2026);
      expect(code.expiry!.year, 2028);
    });

    test('a single bare date is assumed to be the expiry, and flagged', () {
      final code = _parse(_stacked(<String>['03/2028']));

      expect(code.status, DateCodeStatus.ambiguous);
      expect(code.expiry!.year, 2028);
      expect(code.expiry!.month, 3);
      expect(code.note, isNotNull);
    });
  });

  group('date formats', () {
    test('expands MM/YY into the 2000s', () {
      final code = _parse(_stacked(<String>['MFG 03/26', 'EXP 03/28']));

      expect(code.manufactured!.year, 2026);
      expect(code.expiry!.year, 2028);
    });

    test('reads DD/MM/YYYY without splitting it into MM/YYYY', () {
      final code = _parse(_stacked(<String>['EXP 15/03/2028']));

      expect(code.expiry, DateTime(2028, 3, 15));
    });

    test('month-precision expiry runs to the last day of the month', () {
      final code = _parse(_stacked(<String>['EXP 02/2028']));

      expect(code.expiry, DateTime(2028, 2, 29));
    });
  });

  group('digit normalization', () {
    test('recovers a date whose zeros came back as letters', () {
      final code = _parse(_stacked(<String>['EXP O3/2O28']));

      expect(code.expiry!.year, 2028);
      expect(code.expiry!.month, 3);
    });
  });

  group('alphabetic month codes', () {
    // ATC Healthcare carton: a spread-out label column beside a value block
    // crammed tighter and drifting upward, with DDMMMYYYY dates. Nearest
    // baseline binds "Mfg. Date" to the batch code sitting 10px away.
    List<TextLine> atcLayout() => <TextLine>[
          _line('Batch No.:', const Rect.fromLTWH(370, 1082, 200, 36)),
          _line('Mfg. Date:', const Rect.fromLTWH(370, 1162, 200, 36)),
          _line('Exp. Date:', const Rect.fromLTWH(370, 1244, 200, 36)),
          _line('FDA FR No.:', const Rect.fromLTWH(370, 1322, 220, 36)),
          _line('GS002B26', const Rect.fromLTWH(630, 1174, 210, 32)),
          _line('04FEB2026', const Rect.fromLTWH(630, 1206, 210, 32)),
          _line('04FEB2028', const Rect.fromLTWH(630, 1249, 210, 32)),
          _line('4000009048522', const Rect.fromLTWH(630, 1289, 330, 32)),
        ];

    test('reads DDMMMYYYY off a drifting value column', () {
      final code = _parse(atcLayout());

      expect(code.status, DateCodeStatus.parsed);
      expect(code.manufactured, DateTime(2026, 2, 4));
      expect(code.expiry, DateTime(2028, 2, 4));
      expect(code.batch, 'GS002B26');
    });

    test('the batch code keeps the letters digit normalization would eat', () {
      // G and B are in the lookalike map; normalizing the batch would give
      // 65002826.
      expect(_parse(atcLayout()).batch, 'GS002B26');
    });

    test('works from the value block alone, with no labels in the crop', () {
      final code = _parse(<TextLine>[
        _line('GS002B26', const Rect.fromLTWH(630, 1174, 210, 32)),
        _line('04FEB2026', const Rect.fromLTWH(630, 1206, 210, 32)),
        _line('04FEB2028', const Rect.fromLTWH(630, 1249, 210, 32)),
      ]);

      expect(code.expiry, DateTime(2028, 2, 4));
      expect(code.manufactured, DateTime(2026, 2, 4));
    });

    test('accepts the spacing and casing variants packaging actually uses', () {
      for (final pair in <List<String>>[
        <String>['MFG 04 FEB 2026', 'EXP 04 FEB 2028'],
        <String>['MFG 04-FEB-2026', 'EXP 04-FEB-2028'],
        <String>['Mfg. Date 04Feb2026', 'Exp. Date 04Feb2028'],
        <String>['MFG 2026-02-04', 'EXP 2028-02-04'],
      ]) {
        final code = _parse(_stacked(pair));
        expect(code.expiry, DateTime(2028, 2, 4), reason: pair.join(' / '));
        expect(code.manufactured, DateTime(2026, 2, 4), reason: pair.join(' / '));
      }
    });

    test('month-and-year only resolves to the ends of the month', () {
      final code = _parse(_stacked(<String>['MFG FEB2026', 'EXP FEB2028']));

      expect(code.manufactured, DateTime(2026, 2, 1));
      expect(code.expiry, DateTime(2028, 2, 29));
    });

    test('a month name is not mistaken for a batch code', () {
      final code = _parse(_stacked(<String>['EXP 04FEB2028']));

      expect(code.expiry, DateTime(2028, 2, 4));
      expect(code.batch, isNull);
    });
  });
}
