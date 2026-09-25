import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A product name from an FDA Philippines drug advisory (unregistered,
/// counterfeit, or otherwise flagged) that matched the scanned label's OCR text.
class FdaAdvisoryMatch {
  final String productName;
  final String advisoryNumber;
  final String category;
  final String datePosted;

  const FdaAdvisoryMatch({
    required this.productName,
    required this.advisoryNumber,
    required this.category,
    required this.datePosted,
  });
}

/// Result of a dataset lookup: the confident [match] if an entry passed the
/// gate, plus [bestRatio] — the largest share of any one entry's key words
/// found in the text (0..1), whether or not that entry passed.
class FdaMatchOutcome {
  final FdaAdvisoryMatch? match;
  final double bestRatio;

  const FdaMatchOutcome({required this.match, required this.bestRatio});

  bool get hasConfidentMatch => match != null;
}

class _Entry {
  final String name;
  final String advisory;
  final String category;
  final String date;

  /// The entry's distinctive words — see scripts/convert_fda_dataset.py.
  final List<String> keys;

  /// The keys that are not ordinary words; a subset of [keys].
  final Set<String> anchors;

  const _Entry({
    required this.name,
    required this.advisory,
    required this.category,
    required this.date,
    required this.keys,
    required this.anchors,
  });
}

/// Looks up the product-name OCR against the FDA Philippines drug-advisory
/// list (assets/data/fda_advisories.json, built from the cleaned advisory CSV
/// by scripts/convert_fda_dataset.py).
///
/// A match turns a scan into a Warning, so the gate is built against false
/// flags first. One or two ordinary words in common can never match:
///
/// - Only an entry's *key* words count. Dosage forms, generic drug names,
///   label boilerplate, strengths, and words many entries share are stripped
///   when the asset is built, and entries left with fewer than two keys
///   ("Tetracycline Tablets", "Alcohol 70% Solution") are not shipped at all.
/// - At least [_minMatchedKeys] keys must be found exactly, covering every key
///   of a short name and [_longNameCoverage] of a long one.
/// - At least one exactly-matched key must be an *anchor*: a word that is not
///   ordinary English ("efficascent", not "premium" or "tiger"). Two common
///   words together are still two common words.
/// - The exactly-matched keys must total [_minMatchedKeyChars] letters, so two
///   short syllables ("qing zhu") are not enough.
/// - OCR misreads are tolerated on at most one long key (one edit), and never
///   on the anchor.
///
/// Callers should pass the front-panel text only. The ingredient and expiry
/// panels are full of generic words that a product name is not.
class FdaDatasetChecker {
  static const String _assetPath = 'assets/data/fda_advisories.json';
  static final RegExp _wordSplitRegex = RegExp(r'[^a-z0-9]+');

  static const int _minMatchedKeys = 2;
  static const int _minMatchedKeyChars = 9;

  /// Names with more keys than [_shortNameKeys] need this share of them.
  static const double _longNameCoverage = 0.8;
  static const int _shortNameKeys = 4;

  /// Only keys at least this long may be recovered by a one-edit fuzzy match.
  static const int _minFuzzyWordLength = 6;

  static List<_Entry>? _entries;
  static Future<void>? _loading;

  /// Loads and indexes the advisory dataset. Safe to call repeatedly;
  /// subsequent calls reuse the same in-flight/completed load.
  static Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final jsonStr = await rootBundle.loadString(_assetPath);
    final List<dynamic> raw = json.decode(jsonStr) as List<dynamic>;
    _entries = raw.map((row) {
      final list = row as List<dynamic>;
      return _Entry(
        name: list[0] as String,
        advisory: list[1] as String,
        category: list[2] as String,
        date: list[3] as String,
        keys: (list[4] as List<dynamic>).cast<String>(),
        anchors: (list[5] as List<dynamic>).cast<String>().toSet(),
      );
    }).toList();
  }

  /// Convenience wrapper returning just the confident match (or null).
  static FdaAdvisoryMatch? match(String frontText) =>
      matchOutcome(frontText).match;

  /// Returns the entry that passes the gate with the most matched key
  /// letters, if any. Call [ensureLoaded] (and await it) first.
  static FdaMatchOutcome matchOutcome(String frontText) {
    final entries = _entries;
    if (entries == null) {
      return const FdaMatchOutcome(match: null, bestRatio: 0);
    }

    final textWords = _words(frontText).toSet();
    if (textWords.isEmpty) {
      return const FdaMatchOutcome(match: null, bestRatio: 0);
    }

    var bestRatio = 0.0;
    _Entry? best;
    var bestChars = 0;
    for (final entry in entries) {
      final exact = entry.keys.where(textWords.contains).toList();
      final ratio = exact.length / entry.keys.length;
      if (ratio > bestRatio) bestRatio = ratio;

      if (exact.length < _minMatchedKeys) continue;
      if (!exact.any(entry.anchors.contains)) continue;
      final chars = exact.fold<int>(0, (sum, w) => sum + w.length);
      if (chars < _minMatchedKeyChars) continue;

      final required = entry.keys.length <= _shortNameKeys
          ? entry.keys.length
          : (entry.keys.length * _longNameCoverage).ceil();
      var matched = exact.length;
      if (matched < required && matched + 1 >= required) {
        // One key short: let a single OCR misread of a long key make it up.
        final recovered = entry.keys.any((k) =>
            !textWords.contains(k) &&
            k.length >= _minFuzzyWordLength &&
            _hasSingleEditMatch(k, textWords));
        if (recovered) matched++;
      }
      if (matched < required) continue;

      if (chars > bestChars) {
        best = entry;
        bestChars = chars;
      }
    }

    if (best == null) return FdaMatchOutcome(match: null, bestRatio: bestRatio);
    return FdaMatchOutcome(
      match: FdaAdvisoryMatch(
        productName: best.name,
        advisoryNumber: best.advisory,
        category: best.category,
        datePosted: best.date,
      ),
      bestRatio: bestRatio,
    );
  }

  /// True if any word in [textWords] of at least [_minFuzzyWordLength] is
  /// within edit distance 1 of [target] — one substitution, insertion, or
  /// deletion, the shape of a typical single-character OCR misread.
  static bool _hasSingleEditMatch(String target, Set<String> textWords) {
    for (final candidate in textWords) {
      if (candidate.length < _minFuzzyWordLength) continue;
      if ((candidate.length - target.length).abs() > 1) continue;
      if (_withinOneEdit(target, candidate)) return true;
    }
    return false;
  }

  static bool _withinOneEdit(String a, String b) {
    if (a == b) return true;
    final la = a.length;
    final lb = b.length;
    if (la == lb) {
      var diffs = 0;
      for (var i = 0; i < la; i++) {
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
          if (++diffs > 1) return false;
        }
      }
      return diffs == 1;
    }
    // Lengths differ by 1: allow exactly one insertion/deletion.
    final shorter = la < lb ? a : b;
    final longer = la < lb ? b : a;
    var i = 0;
    var j = 0;
    var edited = false;
    while (i < shorter.length && j < longer.length) {
      if (shorter.codeUnitAt(i) == longer.codeUnitAt(j)) {
        i++;
        j++;
      } else {
        if (edited) return false;
        edited = true;
        j++; // skip the extra char in the longer string
      }
    }
    return true;
  }

  /// Same split the asset builder uses: lowercase alphanumeric runs of at
  /// least 3 characters.
  static List<String> _words(String text) {
    return text
        .toLowerCase()
        .split(_wordSplitRegex)
        .where((w) => w.length >= 3)
        .toList();
  }
}
