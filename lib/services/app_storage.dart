import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Single owner of the app's on-device folder layout.
///
/// ```
/// <app documents>/CheckMuna/
///   captures/            photos for the scan being taken right now
///   records/<Name>/      saved scans (see ScanStore)
/// ```
///
/// Everything lives under app-private documents storage: no runtime storage
/// permission is needed, nothing appears in the device gallery, and Android
/// will not reclaim it under storage pressure the way it reclaims the cache
/// directory the camera plugin writes to by default.
class AppStorage {
  const AppStorage._();

  static const String rootFolderName = 'CheckMuna';
  static const String capturesFolderName = 'captures';
  static const String recordsFolderName = 'records';

  /// Where saved scans lived before the folder layout was named. Migrated
  /// across on first use so scans already on a device are not orphaned.
  static const String legacyRecordsFolderName = 'UI_Prototype_Photos';

  static bool _migrationChecked = false;

  static Future<Directory> _ensure(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// `<app documents>/CheckMuna/`.
  static Future<Directory> rootDir() async {
    final documents = await getApplicationDocumentsDirectory();
    return _ensure(p.join(documents.path, rootFolderName));
  }

  /// Staging area for the scan in progress.
  ///
  /// Photos land here straight off the shutter and are deleted when the flow
  /// ends or the capture is discarded. Anything that survives a crash is
  /// cleared by [clearCaptures] on the next run.
  static Future<Directory> capturesDir() async {
    final root = await rootDir();
    return _ensure(p.join(root.path, capturesFolderName));
  }

  /// Root of the saved-record folders, migrating the legacy location first.
  static Future<Directory> recordsDir() async {
    final documents = await getApplicationDocumentsDirectory();
    if (!_migrationChecked) {
      _migrationChecked = true;
      await migrateLegacyRecords(documents);
    }
    final root = await rootDir();
    return _ensure(p.join(root.path, recordsFolderName));
  }

  /// Moves `<documents>/UI_Prototype_Photos/` to `<documents>/CheckMuna/records/`.
  ///
  /// Takes [documents] rather than looking it up so it can be exercised
  /// without platform channels. Safe to call repeatedly: it does nothing once
  /// the legacy folder is gone, and never overwrites records that already
  /// exist at the destination.
  static Future<void> migrateLegacyRecords(Directory documents) async {
    final legacy = Directory(p.join(documents.path, legacyRecordsFolderName));
    if (!await legacy.exists()) return;

    final destination =
        Directory(p.join(documents.path, rootFolderName, recordsFolderName));

    try {
      if (!await destination.exists()) {
        // Nothing at the destination yet, so the whole folder can move at once.
        await Directory(p.join(documents.path, rootFolderName))
            .create(recursive: true);
        await legacy.rename(destination.path);
        return;
      }

      // Destination already populated — move record folders across one by one
      // and leave any name that already exists alone, so a half-finished
      // migration can be resumed without clobbering newer data.
      for (final entity in legacy.listSync()) {
        if (entity is! Directory) continue;
        final target =
            Directory(p.join(destination.path, p.basename(entity.path)));
        if (await target.exists()) continue;
        await entity.rename(target.path);
      }
      if (legacy.listSync().isEmpty) await legacy.delete();
    } catch (e) {
      // A failed migration must not stop the app from starting; the legacy
      // folder is left untouched so it can be retried on the next launch.
      debugPrint('Record folder migration failed: $e');
      _migrationChecked = false;
    }
  }

  /// Deletes everything staged in [capturesDir].
  static Future<void> clearCaptures() async {
    try {
      final dir = await capturesDir();
      for (final entity in dir.listSync()) {
        await entity.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Clearing staged captures failed: $e');
    }
  }

  /// A unique path inside [capturesDir] for a freshly taken photo.
  static Future<String> newCapturePath({String prefix = 'shot'}) async {
    final dir = await capturesDir();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(dir.path, '${prefix}_$stamp.jpg');
  }

  @visibleForTesting
  static void resetMigrationForTest() => _migrationChecked = false;
}
