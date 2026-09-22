import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ui_prototype/services/product_name_picker.dart';

/// A horizontal line at [left],[top] whose words are each an element [height]
/// tall, unless [heights] overrides a word (a small ® or hyphen).
TextLine _line(
  String text, {
  required double left,
  required double top,
  required double width,
  required double height,
  Map<String, double> heights = const <String, double>{},
}) {
  final words = text.split(' ');
  final step = width / words.length;
  final elements = <TextElement>[
    for (var i = 0; i < words.length; i++)
      TextElement(
        text: words[i],
        symbols: const <TextSymbol>[],
        boundingBox: Rect.fromLTWH(
            left + step * i, top, step, heights[words[i]] ?? height),
        recognizedLanguages: const <String>[],
        cornerPoints: const <math.Point<int>>[],
        confidence: null,
        angle: null,
      ),
  ];
  return TextLine(
    text: text,
    elements: elements,
    boundingBox: Rect.fromLTWH(left, top, width, height),
    recognizedLanguages: const <String>[],
    cornerPoints: <math.Point<int>>[
      math.Point<int>(left.round(), top.round()),
      math.Point<int>((left + width).round(), top.round()),
      math.Point<int>((left + width).round(), (top + height).round()),
      math.Point<int>(left.round(), (top + height).round()),
    ],
    confidence: null,
    angle: null,
  );
}

String _pick(List<TextLine> lines) =>
    ProductNamePicker.orderForName(lines).first.text;

void main() {
  group('Philippine drug carton (generic above brand)', () {
    // Geometry measured off a real Kremil-S capture, 2000x1125 crop. The top
    // line is clipped by the guide and misread; the brand is set a size below
    // the generic block and carries a small ®.
    List<TextLine> kremilPanel() => <TextLine>[
          _line('Alummum Hydroxide',
              left: 20, top: 0, width: 1960, height: 110),
          _line('Magnesium Hydroxide',
              left: 0, top: 120, width: 2000, height: 150),
          _line('Simeticone', left: 450, top: 270, width: 1060, height: 130),
          _line('Kremil - S ®',
              left: 590,
              top: 530,
              width: 870,
              height: 100,
              heights: const {'-': 20, '®': 35}),
          _line('178 mg / 233 mg / 30 mg',
              left: 505, top: 755, width: 730, height: 50),
          _line('ANTACID', left: 1320, top: 755, width: 270, height: 55),
          _line('CHEWABLE TABLET',
              left: 510, top: 835, width: 620, height: 50),
          _line('ANTIFLATULENT',
              left: 1315, top: 835, width: 490, height: 55),
        ];

    test('picks the brand, not the larger generic name above it', () {
      expect(_pick(kremilPanel()), 'Kremil - S ®');
    });

    test('order of arrival does not matter', () {
      expect(_pick(kremilPanel().reversed.toList()), 'Kremil - S ®');
    });

    test('finds the brand without the ® when OCR drops it', () {
      final lines = kremilPanel();
      lines[3] = _line('Kremil - S',
          left: 590,
          top: 530,
          width: 870,
          height: 100,
          heights: const {'-': 20});
      expect(_pick(lines), 'Kremil - S');
    });

    test('a misread clipped generic line joins the generic block', () {
      // "Alummum" is not a generic term, so the line is only half generic by
      // word count — it must still be recognised by the block it sits in.
      final ordered = ProductNamePicker.orderForName(kremilPanel());
      expect(ordered.first.text, isNot('Alummum Hydroxide'));
    });

    test('Medicol-style: brand below a single generic word', () {
      final lines = <TextLine>[
        _line('IBUPROFEN', left: 0, top: 0, width: 900, height: 120),
        _line('Medicol Advance', left: 100, top: 160, width: 700, height: 90),
        _line('200 mg Capsule', left: 100, top: 280, width: 500, height: 40),
      ];
      expect(_pick(lines), 'Medicol Advance');
    });
  });

  group('panels with no brand to prefer', () {
    test('generic-only product keeps the generic name', () {
      final lines = <TextLine>[
        _line('Paracetamol', left: 0, top: 0, width: 800, height: 120),
        _line('500 mg Tablet', left: 0, top: 150, width: 500, height: 50),
      ];
      expect(_pick(lines), 'Paracetamol');
    });

    test('a large category label is never taken as the name', () {
      final lines = <TextLine>[
        _line('ANTACID', left: 0, top: 0, width: 800, height: 130),
        _line('Aluminum Hydroxide', left: 0, top: 150, width: 900, height: 120),
      ];
      expect(_pick(lines), 'Aluminum Hydroxide');
    });
  });

  group('supplements (brand is the display type)', () {
    test('MX3 still resolves to the brand, as before', () {
      final lines = <TextLine>[
        _line('MX3', left: 0, top: 0, width: 60, height: 40),
        _line('COFFEE MIX', left: 0, top: 50, width: 105, height: 36),
        _line('With Mangosteen', left: 0, top: 100, width: 75, height: 8),
      ];
      expect(_pick(lines), 'MX3');
    });

    test('a vitamin line below the brand does not displace it', () {
      final lines = <TextLine>[
        _line('Ceelin', left: 0, top: 0, width: 600, height: 110),
        _line('Ascorbic Acid', left: 0, top: 130, width: 500, height: 70),
      ];
      expect(_pick(lines), 'Ceelin');
    });
  });

  group('scoring signals', () {
    test('sitting above the strength line outweighs a slightly larger tagline',
        () {
      final lines = <TextLine>[
        _line('FAST RELIEF', left: 0, top: 0, width: 800, height: 100),
        _line('Neozep', left: 0, top: 300, width: 600, height: 90),
        _line('500 mg Tablet', left: 0, top: 400, width: 500, height: 40),
      ];
      expect(_pick(lines), 'Neozep');
    });

    test('a ® breaks a tie between two similar lines', () {
      final lines = <TextLine>[
        _line('Daily Care', left: 0, top: 0, width: 600, height: 100),
        _line('Biogesic ®',
            left: 0,
            top: 400,
            width: 600,
            height: 98,
            heights: const {'®': 30}),
      ];
      expect(_pick(lines), 'Biogesic ®');
    });
  });

  group('word classification', () {
    test('generic words tolerate one OCR misread on longer terms', () {
      expect(ProductNamePicker.isGenericWord('hydroxlde'), isTrue);
      expect(ProductNamePicker.isGenericWord('paracetamoi'), isTrue);
    });

    test('INN stems catch generics missing from the seed list', () {
      expect(ProductNamePicker.isGenericWord('esomeprazole'), isTrue);
      expect(ProductNamePicker.isGenericWord('azithromycin'), isTrue);
    });

    test('coined brand names are not generic', () {
      for (final brand in ['kremil', 'medicol', 'biogesic', 'neozep', 'alaxan']) {
        expect(ProductNamePicker.isGenericWord(brand), isFalse, reason: brand);
      }
    });

    test('descriptor lines are recognised', () {
      expect(ProductNamePicker.isDescriptorLine('CHEWABLE TABLET'), isTrue);
      expect(ProductNamePicker.isDescriptorLine('178 mg / 233 mg / 30 mg'), isTrue);
      expect(ProductNamePicker.isDescriptorLine('FOOD SUPPLEMENT'), isTrue);
      expect(ProductNamePicker.isDescriptorLine('Kremil - S'), isFalse);
      // Short alphanumeric brands have no three-letter word but are names.
      expect(ProductNamePicker.isDescriptorLine('MX3'), isFalse);
      expect(ProductNamePicker.isDescriptorLine('C2'), isFalse);
    });
  });
}
