import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ui_prototype/services/ocr_geometry.dart';

/// A line whose top edge runs at [degrees] off horizontal, built the way ML
/// Kit reports one: corner points clockwise from the top left.
TextLine _lineAt(double degrees, {String? text}) {
  const length = 100.0;
  const thickness = 20;
  final radians = degrees * math.pi / 180;
  final dx = (length * math.cos(radians)).round();
  final dy = (length * math.sin(radians)).round();
  return TextLine(
    text: text ?? '${degrees.round()} deg',
    elements: const <TextElement>[],
    boundingBox: Rect.fromLTWH(0, 0, length, thickness.toDouble()),
    recognizedLanguages: const <String>[],
    cornerPoints: <math.Point<int>>[
      const math.Point<int>(0, 0),
      math.Point<int>(dx, dy),
      math.Point<int>(dx, dy + thickness),
      const math.Point<int>(0, thickness),
    ],
    confidence: null,
    angle: null,
  );
}

TextElement _element(String text, Rect box) => TextElement(
      text: text,
      symbols: const <TextSymbol>[],
      boundingBox: box,
      recognizedLanguages: const <String>[],
      cornerPoints: const <math.Point<int>>[],
      confidence: null,
      angle: null,
    );

TextLine _lineWith(List<TextElement> elements) => TextLine(
      text: elements.map((e) => e.text).join(' '),
      elements: elements,
      boundingBox: const Rect.fromLTWH(0, 0, 100, 20),
      recognizedLanguages: const <String>[],
      cornerPoints: const <math.Point<int>>[
        math.Point<int>(0, 0),
        math.Point<int>(100, 0),
        math.Point<int>(100, 20),
        math.Point<int>(0, 20),
      ],
      confidence: null,
      angle: null,
    );

RecognizedText _recognized(List<TextLine> lines) => RecognizedText(
      text: lines.map((l) => l.text).join('\n'),
      blocks: <TextBlock>[
        TextBlock(
          text: lines.map((l) => l.text).join('\n'),
          lines: lines,
          boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
          recognizedLanguages: const <String>[],
          cornerPoints: const <math.Point<int>>[],
        ),
      ],
    );

void main() {
  group('lineAngleDegrees', () {
    test('reads the angle off the corner points', () {
      expect(OcrGeometry.lineAngleDegrees(_lineAt(0)), closeTo(0, 0.5));
      expect(OcrGeometry.lineAngleDegrees(_lineAt(10)), closeTo(10, 0.5));
      expect(OcrGeometry.lineAngleDegrees(_lineAt(45)), closeTo(45, 0.5));
      expect(OcrGeometry.lineAngleDegrees(_lineAt(90)), closeTo(90, 0.5));
    });

    test('falls back to zero when corner points are missing', () {
      final line = TextLine(
        text: 'no corners',
        elements: const <TextElement>[],
        boundingBox: const Rect.fromLTWH(0, 0, 100, 20),
        recognizedLanguages: const <String>[],
        cornerPoints: const <math.Point<int>>[],
        confidence: null,
        angle: null,
      );
      expect(OcrGeometry.lineAngleDegrees(line), 0);
    });
  });

  group('horizontalLines', () {
    test('keeps 0 and 10 degrees, drops 45 and 90', () {
      final recognized = _recognized(<TextLine>[
        _lineAt(0, text: 'EXP 03/2028'),
        _lineAt(10, text: 'B.177T78'),
        _lineAt(45, text: 'seal arc text'),
        _lineAt(90, text: 'sideways'),
      ]);

      final kept = OcrGeometry.horizontalLines(recognized);

      expect(kept.map((l) => l.text), <String>['EXP 03/2028', 'B.177T78']);
    });

    test('drops upside-down text, which comes back near 180 degrees', () {
      final recognized = _recognized(<TextLine>[
        _lineAt(0, text: 'EXP 03/2028'),
        _lineAt(180, text: 'ssaerdda detnirp'),
      ]);

      final kept = OcrGeometry.horizontalLines(recognized);

      expect(kept.map((l) => l.text), <String>['EXP 03/2028']);
    });

    test('honours a wider tolerance', () {
      final recognized = _recognized(<TextLine>[_lineAt(18)]);

      expect(OcrGeometry.horizontalLines(recognized), isEmpty);
      expect(
        OcrGeometry.horizontalLines(recognized, maxSkewDegrees: 20),
        hasLength(1),
      );
    });
  });

  group('largestElements', () {
    test('keeps the display type and drops the small print', () {
      final line = _lineWith(<TextElement>[
        _element('BIOFLU', const Rect.fromLTWH(0, 0, 120, 40)),
        _element('Tablet', const Rect.fromLTWH(0, 50, 60, 30)),
        _element('mg', const Rect.fromLTWH(0, 90, 20, 10)),
      ]);

      final kept = OcrGeometry.largestElements(<TextLine>[line]);

      // 40 is tallest; 30 clears the 0.7 cutoff (28), 10 does not.
      expect(kept.map((e) => e.text), <String>['BIOFLU', 'Tablet']);
    });

    test('returns an empty list when there are no elements', () {
      expect(OcrGeometry.largestElements(const <TextLine>[]), isEmpty);
    });
  });
}
