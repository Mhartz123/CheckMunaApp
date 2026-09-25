import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/services/fda_dataset_checker.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FdaDatasetChecker.ensureLoaded();
  });

  group('matches a listed product', () {
    test('from front-panel OCR split across lines', () {
      const front = '''
        Maden
        Povidone-Iodine
        (Thetadine)
        10% Solution 30 mL
      ''';
      final match = FdaDatasetChecker.match(front);
      expect(match, isNotNull);
      expect(match!.productName, contains('Thetadine'));
      expect(match.category, 'Drug Advisories');
    });

    test('with one long key misread by a single character', () {
      // ZAOREN read as ZAOREM: the two exact keys carry the anchor, and the
      // fuzzy pass makes up the third.
      final match =
          FdaDatasetChecker.match('OTC Dezhong Zaorem Anshen Jiaonang');
      expect(match, isNotNull);
      expect(match!.advisoryNumber, 'FDA Advisory No. 2021-1044');
    });
  });

  group('never matches on one or two common words', () {
    // Every one of these is a product name on the advisory CSV. Each is also
    // what a legitimate product's front panel says, so none may match.
    for (final front in const [
      'Tetracycline Tablets',
      'Alcohol 70% Solution 1L',
      'Snow King Medicated Oil 15 ml',
      'Tiger Balm Red Ointment',
    ]) {
      test('"$front" is not shipped as a matchable entry', () {
        expect(FdaDatasetChecker.match(front), isNull);
      });
    }

    test('a single distinctive word is not enough', () {
      // "Richskin Germs Away …" is listed; its brand alone is one key.
      expect(FdaDatasetChecker.match('RICHSKIN'), isNull);
      expect(FdaDatasetChecker.match('Richskin Germs Away'), isNotNull);
    });

    test('two keys with no anchor are not enough', () {
      // "Richskin Case Germs Away" has keys richskin, case, away; without
      // the anchor "richskin", "case" and "away" are just English.
      expect(FdaDatasetChecker.match('Case Germs Away'), isNull);
    });
  });

  group('does not flag ordinary products', () {
    for (final front in const [
      'BIOGESIC Paracetamol 500 mg Tablet Unilab',
      'Aluminum Hydroxide Magnesium Hydroxide Simeticone KREMIL-S '
          'Chewable Tablet Antacid',
      'Casino Ethyl Alcohol 70% Solution 500 mL',
      'Green Cross Isopropyl Alcohol 70% Solution with Moisturizer 500 mL',
      'Betadine Povidone-Iodine Antiseptic Solution 60 mL',
      'Canesten Clotrimazole Cream 1% 20 g',
      'Hydrite Oral Rehydration Salts',
      'Efficascent Oil Extra Strength 100 mL',
      'Vicks VapoRub Ointment 50 g',
      'Pedzinc Multivitamins Syrup FDA Reg. No. DR-XY12345',
    ]) {
      test(front, () => expect(FdaDatasetChecker.match(front), isNull));
    }
  });

  test('returns null for empty text', () {
    expect(FdaDatasetChecker.match(''), isNull);
  });

  test('matchOutcome reports a partial overlap without matching', () {
    final outcome = FdaDatasetChecker.matchOutcome('Dezhong');
    expect(outcome.match, isNull);
    expect(outcome.bestRatio, greaterThan(0));
    expect(outcome.bestRatio, lessThan(1));
  });
}
