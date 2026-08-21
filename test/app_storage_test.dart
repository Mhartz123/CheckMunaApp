import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ui_prototype/services/app_storage.dart';

/// Stands in for the app documents directory. [migrateLegacyRecords] takes it
/// as a parameter precisely so this can run without platform channels.
late Directory documents;

Directory _legacyRecord(String name) => Directory(
      p.join(documents.path, AppStorage.legacyRecordsFolderName, name),
    )..createSync(recursive: true);

Directory _newRecord(String name) => Directory(
      p.join(documents.path, AppStorage.rootFolderName,
          AppStorage.recordsFolderName, name),
    )..createSync(recursive: true);

File _stamp(Directory dir, String contents) =>
    File(p.join(dir.path, 'data.json'))..writeAsStringSync(contents);

String _recordsPath(String name) => p.join(documents.path,
    AppStorage.rootFolderName, AppStorage.recordsFolderName, name);

void main() {
  setUp(() {
    documents = Directory.systemTemp.createTempSync('checkmuna_storage_test');
    AppStorage.resetMigrationForTest();
  });

  tearDown(() {
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  group('legacy record migration', () {
    test('moves saved scans out of the old folder name', () async {
      _stamp(_legacyRecord('Biogesic_500mg'), '{"name":"Biogesic"}');
      _stamp(_legacyRecord('Neozep'), '{"name":"Neozep"}');

      await AppStorage.migrateLegacyRecords(documents);

      expect(File(p.join(_recordsPath('Biogesic_500mg'), 'data.json')).existsSync(),
          isTrue);
      expect(
          File(p.join(_recordsPath('Neozep'), 'data.json')).existsSync(), isTrue);
      expect(
        Directory(p.join(documents.path, AppStorage.legacyRecordsFolderName))
            .existsSync(),
        isFalse,
      );
    });

    test('does nothing when there is no legacy folder', () async {
      await AppStorage.migrateLegacyRecords(documents);

      expect(
        Directory(p.join(documents.path, AppStorage.rootFolderName)).existsSync(),
        isFalse,
      );
    });

    test('never overwrites a record that already exists at the destination',
        () async {
      _stamp(_legacyRecord('Biogesic'), '{"source":"legacy"}');
      _stamp(_newRecord('Biogesic'), '{"source":"current"}');
      _stamp(_legacyRecord('Neozep'), '{"source":"legacy"}');

      await AppStorage.migrateLegacyRecords(documents);

      // The newer record wins; the untouched one still comes across.
      expect(File(p.join(_recordsPath('Biogesic'), 'data.json')).readAsStringSync(),
          '{"source":"current"}');
      expect(File(p.join(_recordsPath('Neozep'), 'data.json')).readAsStringSync(),
          '{"source":"legacy"}');
    });

    test('is safe to run twice', () async {
      _stamp(_legacyRecord('Biogesic'), '{"name":"Biogesic"}');

      await AppStorage.migrateLegacyRecords(documents);
      await AppStorage.migrateLegacyRecords(documents);

      expect(File(p.join(_recordsPath('Biogesic'), 'data.json')).existsSync(),
          isTrue);
    });

    test('leaves the legacy folder in place if a conflict blocks it', () async {
      _stamp(_legacyRecord('Biogesic'), '{"source":"legacy"}');
      _stamp(_newRecord('Biogesic'), '{"source":"current"}');

      await AppStorage.migrateLegacyRecords(documents);

      // Nothing was moved, so the old copy must still be recoverable by hand
      // rather than silently deleted.
      expect(
        File(p.join(documents.path, AppStorage.legacyRecordsFolderName,
                'Biogesic', 'data.json'))
            .readAsStringSync(),
        '{"source":"legacy"}',
      );
    });
  });
}
