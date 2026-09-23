import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_geometry.dart';

/// Lines this fraction of the tallest line's height or larger are considered
/// as the product name. Deliberately looser than [kLargestElementTolerance]:
/// on a Philippine drug carton the brand is set a size below the generic name,
/// and a 0.7 cut drops it right at the boundary (Kremil-S measures ~0.73 of
/// the "Magnesium Hydroxide" line above it).
const double kNameCandidateHeightFloor = 0.45;

/// Share of a line's significant words that must be generic-name terms for the
/// line to count as a generic name rather than a brand.
const double kGenericWordRatio = 0.6;

/// Two lines belong to the same generic-name block when their heights are
/// within this fraction of each other…
const double kGenericBlockHeightTolerance = 0.25;

/// …and the vertical gap between them is at most this many line heights.
const double kGenericBlockGapLineHeights = 0.8;

/// Score added to a brand candidate carrying a registered/trademark sign.
const double kRegisteredMarkBonus = 0.3;

/// Score added to a brand candidate sitting directly above a strength or
/// dosage-form line, within this many of its own heights.
const double kStrengthAdjacencyBonus = 0.2;
const double kStrengthAdjacencyLineHeights = 1.5;

/// Score added per significant word after the first, up to [kNameWordBonusMax].
///
/// A product name is usually more than one word; a logo broken across lines
/// ("daily" / "plus") is one word per line. Both are set large, so height
/// alone cannot separate them — a PearlSkin White Tomato bottle came back as
/// "plus" for exactly that reason. The bonus is deliberately small: short
/// one-word brands (MX3, Ceelin, Neozep) are real and common, so a longer
/// line has to be nearly as large to overtake them, not merely longer.
const double kNameWordBonus = 0.05;
const double kNameWordBonusMax = 0.10;

/// Generic (non-proprietary) names and salt/chemical words common on OTC
/// packaging in the Philippines, lowercase.
///
/// This is a seed list, not a registry. A generic that is missing here and
/// has no stem in [kGenericStems] is treated like any other large line, which
/// is exactly the behaviour before this picker existed — so a gap in coverage
/// costs the old answer, never a worse one. The durable fix for coverage is to
/// generate this set from the FDA drug registry's generic-name column.
const Set<String> kGenericTerms = <String>{
  // Salts, minerals and chemical descriptors.
  'hydroxide', 'hydrochloride', 'hydrobromide', 'sodium', 'potassium',
  'calcium', 'magnesium', 'aluminum', 'aluminium', 'zinc', 'ferrous', 'iron',
  'carbonate', 'bicarbonate', 'citrate', 'sulfate', 'sulphate', 'phosphate',
  'acetate', 'maleate', 'fumarate', 'succinate', 'tartrate', 'gluconate',
  'oxide', 'chloride', 'bromide', 'besilate', 'besylate', 'mesilate',
  'mesylate', 'monohydrate', 'dihydrate', 'trihydrate', 'anhydrous', 'acid',
  'ascorbic', 'folic', 'mefenamic', 'tranexamic',
  // Antacids, antiflatulents, GI.
  'simeticone', 'simethicone', 'dimethicone', 'loperamide', 'bisacodyl',
  'lactulose', 'domperidone', 'attapulgite', 'hyoscine', 'butylbromide',
  'sucralfate', 'alginate',
  // Analgesics and antipyretics.
  'paracetamol', 'acetaminophen', 'ibuprofen', 'naproxen', 'aspirin',
  'diclofenac', 'celecoxib', 'orphenadrine', 'caffeine',
  // Cough, cold and allergy.
  'phenylephrine', 'pseudoephedrine', 'chlorphenamine', 'chlorpheniramine',
  'dextromethorphan', 'guaifenesin', 'carbocisteine', 'ambroxol',
  'bromhexine', 'loratadine', 'desloratadine', 'cetirizine', 'levocetirizine',
  'diphenhydramine', 'meclizine', 'butamirate', 'lagundi', 'salbutamol',
  // Vitamins and supplements.
  'vitamin', 'vitamins', 'multivitamins', 'minerals', 'cyanocobalamin',
  'pyridoxine', 'thiamine', 'thiamin', 'riboflavin', 'niacinamide',
  'cholecalciferol', 'ergocalciferol', 'tocopherol', 'biotin', 'lutein',
  'glucosamine', 'chondroitin', 'lysine',
  // Common anti-infectives and anthelmintics scanned alongside OTC stock.
  'amoxicillin', 'mebendazole', 'albendazole', 'pyrantel', 'pamoate',
  'metronidazole', 'clotrimazole', 'mupirocin',
};

/// INN stems: a word this long ending in one of these is read as a generic
/// name even when it is not in [kGenericTerms]. Restricted to stems specific
/// enough that a coined brand name is unlikely to end in them.
const List<String> kGenericStems = <String>[
  'cillin', 'mycin', 'floxacin', 'oxacin', 'cycline', 'prazole', 'tidine',
  'sartan', 'dipine', 'statin', 'profen', 'olol', 'azole', 'vudine', 'virine',
];
const int kGenericStemMinLength = 7;

/// Words that describe the product without naming it: dosage forms,
/// therapeutic categories and label boilerplate. A line made only of these
/// ("CHEWABLE TABLET", "ANTACID", "FOOD SUPPLEMENT") is never the name.
const Set<String> kDescriptorTerms = <String>{
  'tablet', 'tablets', 'capsule', 'capsules', 'caplet', 'caplets', 'chewable',
  'syrup', 'suspension', 'drops', 'sachet', 'sachets', 'softgel', 'softgels',
  'film', 'coated', 'oral', 'solution', 'powder', 'granules', 'lozenge',
  'lozenges', 'effervescent', 'extended', 'release', 'sustained',
  'antacid', 'antiflatulent', 'analgesic', 'antipyretic', 'decongestant',
  'antihistamine', 'antitussive', 'expectorant', 'mucolytic', 'laxative',
  'antidiarrheal', 'antispasmodic', 'antiemetic', 'anthelmintic',
  'multivitamin', 'food', 'supplement', 'dietary', 'herbal', 'medicine',
  'mcg', 'units',
  // Supplement and cosmetic categories, the same class of word as 'antacid'
  // above: they say what the product is for, never which product it is.
  'whitening', 'slimming', 'nutraceutical',
};

/// Joining words ignored when measuring what a line is made of.
const Set<String> _connectors = <String>{'and', 'with', 'plus', 'for'};

final RegExp _wordSplit = RegExp(r'[^a-z]+');
final RegExp _strength = RegExp(
    r'\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|g|ml|iu|%)(?![a-z])',
    caseSensitive: false);
final RegExp _registeredMark = RegExp(r'[®™]|\((?:R|TM)\)');
/// Something name-like left on a line: two letters in a row, or a letter
/// against a digit (MX3, C2, B12).
final RegExp _letterRun = RegExp(r'[A-Za-z]{2,}|[A-Za-z]\d|\d[A-Za-z]');

/// Chooses which front-panel line is the product's name.
///
/// The earlier rule — the tallest text is the name — holds for supplements,
/// where the brand is the display type, and fails systematically on Philippine
/// drug packaging. The Generics Act (RA 6675) requires the generic name to be
/// printed prominently above the brand, so on a compliant carton the tallest
/// text is the generic: a Kremil-S carton came back as "Aluminum Hydroxide".
///
/// It fails a second way on supplements, where the largest type is a stacked
/// logo rather than the product name: a "daily plus" logo over a PearlSkin
/// White Tomato bottle reported the product as "plus", the single tallest
/// line on the panel.
///
/// So generic-name lines are recognised and set aside, descriptor lines
/// ("ANTACID", "CHEWABLE TABLET", "WHITENING SUPPLEMENT") and lines that are
/// nothing but joining words ("PLUS") are excluded, and the remaining large
/// lines are scored by size, a ® or ™ mark, whether they sit directly above
/// the strength or category line — the brand's position in the generic /
/// brand / strength layout — and how many words they carry, which separates a
/// full product name from one line of a stacked logo. When nothing but
/// generic lines is found, the product has no brand on this panel and the
/// generic name is the right answer, so the tallest line wins exactly as
/// before.
class ProductNamePicker {
  const ProductNamePicker._();

  /// [lines] reordered so the most likely product name comes first, followed
  /// by the other display-type lines in reading order. Callers take the first
  /// usable line as the name.
  static List<TextLine> orderForName(List<TextLine> lines) {
    if (lines.isEmpty) return const <TextLine>[];

    var tallest = 0.0;
    for (final line in lines) {
      final h = lineHeight(line);
      if (h > tallest) tallest = h;
    }
    if (tallest <= 0) return OcrGeometry.prominentLines(lines);

    final candidates = <TextLine>[
      for (final line in lines)
        if (lineHeight(line) >= tallest * kNameCandidateHeightFloor) line,
    ]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final generic = _genericLines(candidates);

    final brandScores = <TextLine, double>{};
    for (final line in candidates) {
      if (generic.contains(line) || isDescriptorLine(line.text)) continue;
      var score = lineHeight(line) / tallest;
      if (_registeredMark.hasMatch(line.text)) score += kRegisteredMarkBonus;
      if (_sitsAboveStrength(line, lines)) score += kStrengthAdjacencyBonus;
      score += _wordCountBonus(line.text);
      brandScores[line] = score;
    }

    if (brandScores.isEmpty) {
      // Generic-only panel. Keep the old tallest-first behaviour, minus any
      // descriptor line that happened to be set large.
      final prominent = OcrGeometry.prominentLines(lines)
          .where((l) => !isDescriptorLine(l.text))
          .toList();
      return prominent.isEmpty ? OcrGeometry.prominentLines(lines) : prominent;
    }

    TextLine best = brandScores.keys.first;
    for (final entry in brandScores.entries) {
      if (entry.value > brandScores[best]!) best = entry.key;
    }
    return <TextLine>[
      best,
      for (final line in candidates)
        if (!identical(line, best) && !isDescriptorLine(line.text)) line,
    ];
  }

  /// Height of a line's display type: its tallest element, which ignores a
  /// small ® or hyphen sharing the line. Falls back to the line box when ML Kit
  /// reported no elements.
  static double lineHeight(TextLine line) {
    var h = 0.0;
    for (final e in line.elements) {
      if (e.boundingBox.height > h) h = e.boundingBox.height;
    }
    return h > 0 ? h : line.boundingBox.height;
  }

  /// Lowercase alphabetic words of three or more letters, connectors removed.
  static List<String> significantWords(String text) => text
      .toLowerCase()
      .split(_wordSplit)
      .where((w) => w.length >= 3 && !_connectors.contains(w))
      .toList();

  /// Whether [word] reads as a generic name or salt, tolerating one OCR
  /// misread on longer words ("hydroxlde", "paracetamoI").
  static bool isGenericWord(String word) {
    if (kGenericTerms.contains(word)) return true;
    if (word.length >= kGenericStemMinLength &&
        kGenericStems.any(word.endsWith)) {
      return true;
    }
    if (word.length >= 6) {
      for (final term in kGenericTerms) {
        if ((term.length - word.length).abs() <= 1 &&
            term.length >= 6 &&
            _withinOneEdit(term, word)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Fraction of [text]'s significant words that are generic terms.
  static double genericRatio(String text) {
    final words = significantWords(text);
    if (words.isEmpty) return 0;
    return words.where(isGenericWord).length / words.length;
  }

  /// A line naming nothing: only dosage forms, categories, units or numbers.
  ///
  /// "No significant words" is not enough on its own to call a line empty: a
  /// short alphanumeric brand like MX3 has no word of three letters, and
  /// treating that as a descriptor dropped the brand of the very carton the
  /// display-type rule was calibrated on. So a line only counts as empty once
  /// its strengths are removed and nothing name-like (see [_letterRun])
  /// remains.
  static bool isDescriptorLine(String text) {
    final words = significantWords(text);
    if (words.isEmpty) {
      // A line that is nothing but joining words — "PLUS", "AND", "WITH" —
      // names nothing on its own, even though it clears the [_letterRun] test
      // that keeps short brands like MX3 alive. Logos routinely set the joiner
      // on its own line in the largest type on the panel, and that line then
      // won the whole panel: a "daily plus" logo above "PearlSkin White
      // Tomato" reported the product as "plus".
      if (_isConnectorOnly(text)) return true;
      return !_letterRun.hasMatch(text.replaceAll(_strength, ''));
    }
    return words.every(kDescriptorTerms.contains);
  }

  /// Whether every alphabetic token on [text] is a joining word.
  static bool _isConnectorOnly(String text) {
    final tokens = text
        .toLowerCase()
        .split(_wordSplit)
        .where((w) => w.isNotEmpty)
        .toList();
    return tokens.isNotEmpty && tokens.every(_connectors.contains);
  }

  /// [kNameWordBonus] per significant word after the first, capped.
  static double _wordCountBonus(String text) {
    final extra = significantWords(text).length - 1;
    if (extra <= 0) return 0;
    final bonus = extra * kNameWordBonus;
    return bonus > kNameWordBonusMax ? kNameWordBonusMax : bonus;
  }

  /// Generic-name lines among [candidates] (sorted top to bottom).
  ///
  /// A line qualifies outright at [kGenericWordRatio]. A line with at least one
  /// generic word also qualifies when it sits in a run with a qualifying line
  /// of the same type size, because generic names are set as one block. That
  /// is what catches a clipped or misread member of the block — a top line cut
  /// off by the guide came back as "Alummum Hydroxide", half generic by word
  /// count but obviously part of the block below it.
  static Set<TextLine> _genericLines(List<TextLine> candidates) {
    final generic = <TextLine>{
      for (final line in candidates)
        if (genericRatio(line.text) >= kGenericWordRatio) line,
    };

    var changed = true;
    while (changed) {
      changed = false;
      for (final line in candidates) {
        if (generic.contains(line)) continue;
        if (genericRatio(line.text) == 0) continue;
        final joinsBlock = generic.any((g) => _sameBlock(line, g));
        if (joinsBlock) {
          generic.add(line);
          changed = true;
        }
      }
    }
    return generic;
  }

  static bool _sameBlock(TextLine a, TextLine b) {
    final ha = lineHeight(a);
    final hb = lineHeight(b);
    final larger = ha > hb ? ha : hb;
    if (larger <= 0) return false;
    if ((ha - hb).abs() / larger > kGenericBlockHeightTolerance) return false;

    final upper = a.boundingBox.top <= b.boundingBox.top ? a : b;
    final lower = identical(upper, a) ? b : a;
    final gap = lower.boundingBox.top - upper.boundingBox.bottom;
    return gap <= larger * kGenericBlockGapLineHeights;
  }

  /// Whether a strength or dosage-form line sits directly below [line] and
  /// overlaps it horizontally.
  static bool _sitsAboveStrength(TextLine line, List<TextLine> all) {
    final h = lineHeight(line);
    final box = line.boundingBox;
    for (final other in all) {
      if (identical(other, line)) continue;
      final o = other.boundingBox;
      final gap = o.top - box.bottom;
      if (gap < -h * 0.25 || gap > h * kStrengthAdjacencyLineHeights) continue;
      final overlaps = o.left < box.right && o.right > box.left;
      if (!overlaps) continue;
      if (_strength.hasMatch(other.text)) return true;
      final words = significantWords(other.text);
      if (words.isNotEmpty && words.every(kDescriptorTerms.contains)) {
        return true;
      }
    }
    return false;
  }

  static bool _withinOneEdit(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
