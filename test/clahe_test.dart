import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ui_prototype/services/damage_detection_service.dart';

/// BT.601 luma, the same one [DamageDetectionService.applyClahe] equalises.
double _luma(img.Pixel p) => 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

/// Standard deviation of luma over a rectangle — the stand-in for "local
/// contrast" in these tests.
double _localContrast(img.Image image, int x0, int y0, int w, int h) {
  final values = <double>[];
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      values.add(_luma(image.getPixel(x, y)));
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length;
  return math.sqrt(variance);
}

/// A 128x128 frame lit brightly on the left and in shadow on the right, with
/// a faint checker texture on top — the shape of the problem CLAHE is here to
/// solve. The texture amplitude is the same everywhere, so a correct
/// implementation should raise contrast in the shadowed half without needing
/// the bright half to lose any.
img.Image _unevenlyLitTexture() {
  final image = img.Image(width: 128, height: 128);
  for (var y = 0; y < 128; y++) {
    for (var x = 0; x < 128; x++) {
      final illumination = 200 - (x / 127) * 170; // 200 -> 30
      final texture = ((x ~/ 4) + (y ~/ 4)).isEven ? 4.0 : -4.0;
      final v = (illumination + texture).clamp(0, 255).round();
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  group('applyClahe', () {
    test('lifts local contrast in a shadowed region', () {
      final image = _unevenlyLitTexture();
      final before = _localContrast(image, 100, 48, 24, 24);

      DamageDetectionService.applyClahe(image);
      final after = _localContrast(image, 100, 48, 24, 24);

      // The dark end is where a box crease disappears into shadow; that is
      // the whole reason this stage exists, so require a real gain, not just
      // "not worse". The gain is bounded by design — the clip limit is what
      // stops a low-contrast tile from being stretched to full range — so
      // this asks for a solid lift rather than a dramatic one.
      expect(after, greaterThan(before * 1.25));
    });

    test('keeps every channel inside 0..255', () {
      final image = _unevenlyLitTexture();
      DamageDetectionService.applyClahe(image);

      for (final p in image) {
        expect(p.r, inInclusiveRange(0, 255));
        expect(p.g, inInclusiveRange(0, 255));
        expect(p.b, inInclusiveRange(0, 255));
      }
    });

    test('leaves no seam at the tile borders', () {
      // A smooth gradient has no edges in it. Without the bilinear blend
      // between neighbouring tile LUTs, each tile would get its own mapping
      // and the borders would show up as steps — which the detector would
      // read as box edges that are not there. On a 128 px frame with an 8x8
      // grid the borders sit every 16 px.
      final image = img.Image(width: 128, height: 128);
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          final v = (x * 255 / 127).round();
          image.setPixelRgb(x, y, v, v, v);
        }
      }

      DamageDetectionService.applyClahe(image);

      var maxStep = 0.0;
      for (var y = 0; y < 128; y++) {
        for (var x = 1; x < 128; x++) {
          final step =
              (_luma(image.getPixel(x, y)) - _luma(image.getPixel(x - 1, y)))
                  .abs();
          if (step > maxStep) maxStep = step;
        }
      }
      // A seam would be a double-digit jump; ordinary equalisation of a
      // 2 grey-level-per-pixel ramp stays small.
      expect(maxStep, lessThan(8.0));
    });

    test('preserves hue on a coloured patch', () {
      // Equalising each channel on its own would pull a colour towards gray.
      // Scaling R/G/B by the luma ratio should keep the ratios between them.
      final image = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final shade = 1.0 - (x / 63) * 0.6;
          image.setPixelRgb(
              x, y, (180 * shade).round(), (90 * shade).round(), (45 * shade).round());
        }
      }

      DamageDetectionService.applyClahe(image);

      for (final p in image) {
        expect(p.r / p.g, closeTo(180 / 90, 0.15));
        expect(p.g / p.b, closeTo(90 / 45, 0.15));
      }
    });

    test('is a no-op on an image smaller than the tile grid', () {
      final image = img.Image(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          image.setPixelRgb(x, y, 10 + x, 20 + y, 30);
        }
      }

      DamageDetectionService.applyClahe(image);

      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final p = image.getPixel(x, y);
          expect([p.r, p.g, p.b], [10 + x, 20 + y, 30]);
        }
      }
    });

    test('does not blow out a flat frame into noise', () {
      // Clipping is what stops a near-uniform tile from having its sensor
      // noise stretched across the full range. A perfectly flat frame has no
      // noise to stretch, so it must come back flat.
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(130, 130, 130));

      DamageDetectionService.applyClahe(image);

      expect(_localContrast(image, 0, 0, 64, 64), lessThan(1.0));
    });
  });

  group('detector presets', () {
    test('CLAHE is on for boxes and off for bottles and foils', () {
      expect(DamageDetectionService.box.claheEqualize, isTrue);
      expect(DamageDetectionService.bottle.claheEqualize, isFalse);
      expect(DamageDetectionService.foil.claheEqualize, isFalse);
    });

    test('all three detectors run at the tuned 640 px input', () {
      expect(DamageDetectionService.box.inputSize, 640);
      expect(DamageDetectionService.bottle.inputSize, 640);
      expect(DamageDetectionService.foil.inputSize, 640);
    });

    test('foil class 0 is damage now that No-Damage is gone', () {
      // The retrained foil model dropped the explicit No-Damage class, so
      // treating class 0 as non-damage would suppress every foil detection.
      expect(DamageDetectionService.foil.nonDamageClasses, isEmpty);
      expect(DamageDetectionService.foil.classNames[0], 'Structural deformation');
    });
  });
}
