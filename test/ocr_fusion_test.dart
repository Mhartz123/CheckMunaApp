import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ui_prototype/services/ocr_fusion.dart';

/// Builds a RecognizedText with one block per paragraph ('\n\n'), one line
/// per '\n', one element per word, laid out on a simple grid so geometry is
/// present the way ML Kit provides it.
RecognizedText reading(String text) {
  final blocks = <TextBlock>[];
  var y = 0;
  for (final para in text.split('\n\n')) {
    final lines = <TextLine>[];
    for (final lineText in para.split('\n')) {
      final elements = <TextElement>[];
      var x = 0;
      for (final word in lineText.split(' ').where((w) => w.isNotEmpty)) {
        final box = Rect.fromLTWH(x.toDouble(), y.toDouble(),
            word.length * 10.0, 20);
        elements.add(TextElement(
          text: word,
          symbols: const [],
          boundingBox: box,
          recognizedLanguages: const [],
          cornerPoints: _corners(box),
          confidence: null,
          angle: 0,
        ));
        x += word.length * 10 + 10;
      }
      final box = Rect.fromLTWH(0, y.toDouble(), x.toDouble(), 20);
      lines.add(TextLine(
        text: lineText,
        elements: elements,
        boundingBox: box,
        recognizedLanguages: const [],
        cornerPoints: _corners(box),
        confidence: null,
        angle: 0,
      ));
      y += 30;
    }
    final box = Rect.fromLTWH(0, 0, 500, y.toDouble());
    blocks.add(TextBlock(
      text: para,
      lines: lines,
      boundingBox: box,
      recognizedLanguages: const [],
      cornerPoints: _corners(box),
    ));
  }
  return RecognizedText(text: text.replaceAll('\n\n', '\n'), blocks: blocks);
}

List<Point<int>> _corners(Rect r) => [
      Point(r.left.round(), r.top.round()),
      Point(r.right.round(), r.top.round()),
      Point(r.right.round(), r.bottom.round()),
      Point(r.left.round(), r.bottom.round()),
    ];

String fused(List<String?> frames) => OcrFusion.fuse(
        [for (final f in frames) f == null ? null : reading(f)])!
    .text
    .text;

void main() {
  group('word vote', () {
    test('identical frames come back unchanged', () {
      const t = 'Biogesic\nParacetamol 500mg';
      final r = OcrFusion.fuse([reading(t), reading(t), reading(t)])!;
      expect(r.text.text, t);
      expect(r.report.repairs, 0);
      expect(r.report.framesAgreeing, 3);
      expect(r.report.agreement, 1.0);
    });

    test('one misread word is replaced by the two frames that agree', () {
      expect(
        fused([
          'Paracetamol 500mg Tablet',
          'Paracetam0l 500mg Tablet',
          'Paracetamol 500mg Tablet',
        ]),
        'Paracetamol 500mg Tablet',
      );
    });

    test('a different word misread in every frame is still repaired', () {
      // Each frame gets exactly one word wrong, and a different one.
      expect(
        fused([
          'Ascorbic Acid 5OOmg',
          'Ascorb1c Acid 500mg',
          'Ascorbic Aci0 500mg',
        ]),
        'Ascorbic Acid 500mg',
      );
    });

    test('a word only one frame hallucinated is dropped', () {
      expect(
        fused([
          'Sodium Chloride',
          'Sodium ~~ Chloride',
          'Sodium Chloride',
        ]),
        'Sodium Chloride',
      );
    });

    test('a word one frame missed is kept because the majority read it', () {
      final r = OcrFusion.fuse([
        reading('Magnesium Stearate Talc'),
        reading('Magnesium Stearate Talc'),
        reading('Magnesium Talc'),
      ])!;
      expect(r.report.inserted, 0); // pivot already had it; nothing to insert
      expect(r.text.text, 'Magnesium Stearate Talc');
    });

    test('insertion is also recovered when the pivot is the short frame', () {
      // The short frame is weighted just enough to become the pivot, but the
      // two frames that read "Stearate" still hold a weight majority
      // (2 of 3.5), so the word must be inserted into the pivot's reading.
      final r = OcrFusion.fuse([
        reading('Magnesium Talc'),
        reading('Magnesium Stearate Talc'),
        reading('Magnesium Stearate Talc'),
      ], weights: [1.5, 1, 1])!;
      expect(r.report.pivotIndex, 0);
      expect(r.report.inserted, 1);
      expect(r.text.text, 'Magnesium Stearate Talc');
    });
  });

  group('character vote', () {
    test('three different misreads of one word fuse to the right spelling',
        () {
      expect(
        fused(['Parac3tamol', 'Paracetamo1', 'Paracetam0l']),
        'Paracetamol',
      );
    });

    test('a 1-vs-1 tie is broken toward the character that fits the word',
        () {
      // Third frame lost the word entirely.
      final r = OcrFusion.fuse([
        reading('Ibuprofen 200mg'),
        reading('Ibupr0fen 200mg'),
        reading('200mg'),
      ])!;
      expect(r.text.text, 'Ibuprofen 200mg');
    });

    test('digits win inside a number', () {
      expect(OcrFusion.fuseCharacters(['2O27', '2027']), '2027');
      expect(OcrFusion.fuseCharacters(['l2/2027', '12/2O27', '12/2027']),
          '12/2027');
    });
  });

  group('robustness', () {
    test('frames that read nothing are ignored', () {
      expect(fused([null, 'Loratadine 10mg', '']), 'Loratadine 10mg');
    });

    test('nothing read anywhere returns null', () {
      expect(OcrFusion.fuse([null, reading(''), null]), isNull);
    });

    test('a single frame passes through untouched', () {
      final only = reading('Cetirizine');
      final r = OcrFusion.fuse([only])!;
      expect(identical(r.text, only), isTrue);
    });

    test('the fused result keeps the pivot layout for downstream geometry',
        () {
      final r = OcrFusion.fuse([
        reading('BIOGESIC\nParacetamol 500mg\n\nUnilab Inc'),
        reading('BI0GESIC\nParacetamol 500mg\n\nUnilab Inc'),
        reading('BIOGESIC\nParacetamol 5OOmg\n\nUnilab Inc'),
      ])!;
      expect(r.text.blocks.length, 2);
      expect(r.text.blocks.first.lines.map((l) => l.text),
          ['BIOGESIC', 'Paracetamol 500mg']);
      expect(r.text.blocks.first.lines[1].elements.length, 2);
      expect(r.text.blocks.first.lines[1].elements[1].boundingBox.width,
          greaterThan(0));
    });

    test('the odd frame out is reported as not agreeing', () {
      final r = OcrFusion.fuse([
        reading('Vitamin C Ascorbic Acid 500mg Tablet'),
        reading('Vitamin C Ascorbic Acid 500mg Tablet'),
        reading('Vltamin G Asc0rbic Acld 5O0mg Tab1et'),
      ])!;
      expect(r.text.text, 'Vitamin C Ascorbic Acid 500mg Tablet');
      expect(r.report.framesAgreeing, 2);
      expect(r.report.pivotIndex, isNot(2));
    });

    test('a long ingredient list fuses in reasonable time', () {
      final words = List.generate(200, (i) => 'ingredient$i').join(' ');
      final noisy = words.replaceAll('ingredient1', 'lngredient1');
      final watch = Stopwatch()..start();
      final out = fused([words, noisy, words]);
      watch.stop();
      expect(out, words);
      expect(watch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
