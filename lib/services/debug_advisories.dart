import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fda_dataset_checker.dart';

/// Product names typed in on the phone that the advisory check treats as
/// listed, for testing the Warning path without rebuilding the app or the
/// bundled FDA list.
///
/// Hidden on purpose: the entry screen opens only from seven quick taps on
/// the Home header logo (see DashboardScreen), so testers and evaluators
/// using the app normally never see it.
///
/// Entries are stored on this phone only, in the app documents directory,
/// and are checked after the real list. Unlike the real list they are not
/// gated: every word typed must appear on the front panel, and that is all —
/// whoever typed the name decided it should flag. A Warning they cause is
/// labelled as a debug entry in the record and is never uploaded to the
/// dashboard (see ReportService.submit).
class DebugAdvisories extends ChangeNotifier {
  DebugAdvisories._();

  static final DebugAdvisories instance = DebugAdvisories._();

  static const String _fileName = 'debug_advisories.json';

  /// Stands in for the advisory number on a debug match.
  static const String advisoryNumber = 'debug entry';
  static const String category = 'added on this phone for testing';

  /// Start of the Warning reason a debug match produces. ReportService keys
  /// off it to keep test Warnings off the dashboard.
  static const String reasonPrefix = 'DEBUG — matches a test entry';

  /// Words at least this long may be matched with one OCR misread.
  static const int _minFuzzyWordLength = 5;

  static final RegExp _wordSplit = RegExp(r'[^a-z0-9]+');

  /// Overrides the storage location. Tests point this at a temp folder so
  /// they don't need path_provider's platform channel.
  @visibleForTesting
  static Directory? debugDirectory;

  final List<String> _names = <String>[];
  Future<void>? _loading;

  List<String> get names => List.unmodifiable(_names);

  static Future<File> _file() async {
    final dir = debugDirectory ?? await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Reads the stored names. Safe to call repeatedly.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      _names
        ..clear()
        ..addAll(list.whereType<String>());
      notifyListeners();
    } catch (e) {
      debugPrint('Loading debug advisories failed: $e');
    }
  }

  /// Adds [name] unless it is blank or already present (ignoring case).
  /// Returns whether it was added.
  Future<bool> add(String name) async {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_words(trimmed).isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (_names.any((n) => n.toLowerCase() == lower)) return false;
    _names.add(trimmed);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> remove(String name) async {
    if (!_names.remove(name)) return;
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_names.isEmpty) return;
    _names.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_names));
    } catch (e) {
      debugPrint('Saving debug advisories failed: $e');
    }
  }

  /// The first entry every word of which is on [frontText], as an advisory
  /// match, or null. Call [ensureLoaded] (and await it) first.
  FdaAdvisoryMatch? match(String frontText) {
    if (_names.isEmpty) return null;
    final textWords = _words(frontText).toSet();
    if (textWords.isEmpty) return null;

    for (final name in _names) {
      final words = _words(name);
      if (words.isEmpty) continue;
      if (words.every((w) => _found(w, textWords))) {
        return FdaAdvisoryMatch(
          productName: name,
          advisoryNumber: advisoryNumber,
          category: category,
          datePosted: '',
        );
      }
    }
    return null;
  }

  static bool _found(String word, Set<String> textWords) {
    if (textWords.contains(word)) return true;
    if (word.length < _minFuzzyWordLength) return false;
    return textWords.any((t) =>
        t.length >= _minFuzzyWordLength &&
        (t.length - word.length).abs() <= 1 &&
        FdaDatasetChecker.withinOneEdit(word, t));
  }

  /// Lowercase alphanumeric runs. No minimum length, unlike the real list:
  /// "Kremil-S" is typed on purpose, and its "s" should count.
  static List<String> _words(String text) => text
      .toLowerCase()
      .split(_wordSplit)
      .where((w) => w.isNotEmpty)
      .toList();

  @visibleForTesting
  void resetForTest() {
    _names.clear();
    _loading = null;
  }
}
