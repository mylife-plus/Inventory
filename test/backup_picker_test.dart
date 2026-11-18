import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_app/data/backup/app_backup_service.dart';
import 'package:inventory_app/data/db/app_database.dart';

class _FakePicker extends FilePicker {
  _FakePicker(this.file);
  final PlatformFile? file;
  FileType? type;
  List<String>? extensions;
  bool? withData;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    this.withData = withData;
    return file == null ? null : FilePickerResult([file!]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final backupJson = jsonEncode({
    'format': 'softthrive_inventory_backup',
    'version': AppBackupService.formatVersion,
  });

  test('upload picker accepts any file (our .inventorybak has no OS type)',
      () async {
    final saved = PlatformFile(
      name: 'inventory_backup_1731400000000.${AppBackupService.fileExtension}',
      size: backupJson.length,
      bytes: Uint8List.fromList(utf8.encode(backupJson)),
    );
    final fake = _FakePicker(saved);
    FilePicker.platform = fake;

    final picked = await AppBackupService.pickBackupFile();

    // An extension filter silently drops "inventorybak" on iOS (dyn. UTI)
    // and Android (no MIME), leaving the saved backup greyed out.
    expect(fake.type, FileType.any);
    expect(fake.extensions, isNull);
    expect(fake.withData, isTrue);
    expect(picked?.name, endsWith('.inventorybak'));
    expect(await AppBackupService.readPickedBackup(picked!), backupJson);
  });

  test('cancelled pick returns null', () async {
    FilePicker.platform = _FakePicker(null);
    expect(await AppBackupService.pickBackupFile(), isNull);
  });

  test('a picked file that is not a backup is rejected before any data changes',
      () async {
    final service = AppBackupService(AppDatabase.instance);
    await expectLater(
      service.restoreFromJson('{"format":"something_else"}'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.restoreFromJson('not json'),
      throwsA(isA<FormatException>()),
    );
  });
}
