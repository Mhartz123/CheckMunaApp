import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-wide light/dark switch. A single global [ChangeNotifier] instance
/// rather than an InheritedWidget/Theme.of(context) lookup, since the whole
/// app shares one toggle — see `AppColors`, which reads
/// [ThemeController.instance.isDark] directly rather than needing a
/// BuildContext at every color reference. main.dart listens to this and
/// rebuilds the whole app on toggle, so every screen's colors update
/// together.
///
/// Defaults to light on first run. The user's choice — made via the toggle
/// on the Homepage — is persisted as a one-line file in the app documents
/// directory, the same lightweight approach PackagingTypeScreen already uses
/// for its "last used" packaging type, rather than adding a dependency like
/// shared_preferences for a single value.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _fileName = 'theme_mode.txt';

  bool _isDark = false;

  bool get isDark => _isDark;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Reads the persisted preference, if any. Call once at startup — before
  /// `runApp` — so the correct theme is already active on the first frame
  /// instead of flashing light-then-dark for a returning user. A missing or
  /// unreadable file just means "no preference saved yet," which keeps the
  /// light default.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final saved = (await file.readAsString()).trim();
      _isDark = saved == 'dark';
    } catch (_) {
      // Falls back to the light default — not worth surfacing.
    }
  }

  /// Flips the theme, notifies listeners immediately (so the UI updates
  /// without waiting on disk I/O), then persists best-effort.
  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    try {
      final file = await _file();
      await file.writeAsString(_isDark ? 'dark' : 'light');
    } catch (_) {
      // The in-memory toggle already took effect; persistence failing here
      // just means the choice won't survive a restart.
    }
  }
}