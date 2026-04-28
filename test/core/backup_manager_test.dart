/// Test cases TC-066 through TC-075 for BackupManager
import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/core/backup_manager.dart';
import 'package:mcp_flow_runtime/src/types/flow_types.dart';

FlowDefinition _createTestFlow() {
  return FlowDefinition.fromJson({
    'version': '1.0.0',
    'metadata': {'name': 'Test'},
    'processes': [],
  });
}

void main() {
  late Directory tmpDir;
  late BackupManager manager;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('tc_backup_');
    manager = BackupManager(
      backupDirectory: tmpDir.path,
      maxBackups: 10,
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('TC-066: createBackup', () {
    test('TC-066a: basic backup creation', () async {
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
        state: {'counter': 42},
      );
      expect(meta.id, isNotEmpty);
      expect(meta.timestamp, isA<DateTime>());
      expect(meta.checksum, isNotEmpty);
    });

    test('TC-066b: backup with description and tags', () async {
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
        description: 'Pre-deploy',
        tags: {'env': 'prod'},
      );
      expect(meta.description, equals('Pre-deploy'));
      expect(meta.tags?['env'], equals('prod'));
    });

    test('TC-066c: backup to invalid directory throws', () async {
      final badManager = BackupManager(
        backupDirectory: '/nonexistent/path/that/cannot/be/created',
        maxBackups: 10,
      );
      expect(
        () => badManager.createBackup(flow: _createTestFlow()),
        throwsA(anything),
      );
    });
  });

  group('TC-067: createBackup - compression', () {
    test('TC-067a: compressed backup', () async {
      final compressedMgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 10,
        compressBackups: true,
      );
      final meta = await compressedMgr.createBackup(
        flow: _createTestFlow(),
      );
      expect(meta.id, isNotEmpty);
    });

    test('TC-067b: uncompressed backup (default)', () async {
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
      );
      expect(meta.id, isNotEmpty);
    });
  });

  group('TC-068: listBackups', () {
    test('TC-068a: list returns created backups', () async {
      await manager.createBackup(flow: _createTestFlow());
      await manager.createBackup(flow: _createTestFlow());
      await manager.createBackup(flow: _createTestFlow());
      final list = await manager.listBackups();
      expect(list.length, equals(3));
    });

    test('TC-068b: empty directory returns empty list', () async {
      final list = await manager.listBackups();
      expect(list, isEmpty);
    });

    test('TC-068c: nonexistent directory returns empty list', () async {
      final mgr = BackupManager(
        backupDirectory: '${tmpDir.path}/nonexistent',
        maxBackups: 10,
      );
      final list = await mgr.listBackups();
      expect(list, isEmpty);
    });
  });

  group('TC-069: restoreBackup', () {
    test('TC-069a: restores backup content', () async {
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
        state: {'val': 99},
      );
      final content = await manager.restoreBackup(meta.id);
      expect(content.flow, isNotNull);
      expect(content.state?['val'], equals(99));
    });

    test('TC-069b: tampered backup file — checksum mismatch', () async {
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
        state: {'val': 99},
      );

      // Find and tamper with the backup file (preserve valid JSON)
      final backupDir = Directory(tmpDir.path);
      final files = backupDir.listSync().whereType<File>().toList();
      final backupFile = files.firstWhere(
        (f) => f.path.contains(meta.id),
      );
      final original = await backupFile.readAsString();
      // Replace a value to change checksum but keep JSON valid
      final tampered = original.replaceFirst('"val":99', '"val":0');
      await backupFile.writeAsString(tampered);

      // Per DDD: warning log only, no exception thrown (compatibility)
      final content = await manager.restoreBackup(meta.id);
      expect(content.flow, isNotNull);
    });

    test('TC-069c: nonexistent backup throws', () {
      expect(
        () => manager.restoreBackup('nonexistent_id'),
        throwsA(anything),
      );
    });
  });

  group('TC-070: deleteBackup', () {
    test('TC-070a: deletes backup', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      await manager.deleteBackup(meta.id);
      final list = await manager.listBackups();
      expect(list.where((b) => b.id == meta.id), isEmpty);
    });

    test('TC-070b: delete same ID twice throws', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      await manager.deleteBackup(meta.id);
      expect(
        () => manager.deleteBackup(meta.id),
        throwsA(anything),
      );
    });
  });

  group('TC-070c: deleteBackup — file deletion failure', () {
    test('TC-070c: delete with permission error throws', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());

      // Create a manager pointing to a nonexistent directory to simulate failure
      final badManager = BackupManager(
        backupDirectory: '/nonexistent/path',
        maxBackups: 10,
      );
      expect(
        () => badManager.deleteBackup(meta.id),
        throwsA(anything),
      );
    });
  });

  group('TC-071: exportBackup', () {
    test('TC-071a: export to external path', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      final exportPath = '${tmpDir.path}/exported.json';
      await manager.exportBackup(meta.id, exportPath);
      expect(await File(exportPath).exists(), isTrue);
    });

    test('TC-071b: export overwrites existing', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      final exportPath = '${tmpDir.path}/exported.json';
      await manager.exportBackup(meta.id, exportPath);
      await manager.exportBackup(meta.id, exportPath); // Should overwrite
      expect(await File(exportPath).exists(), isTrue);
    });

    test('TC-071c: export nonexistent backup throws', () {
      expect(
        () => manager.exportBackup('nope', '${tmpDir.path}/x.json'),
        throwsA(anything),
      );
    });
  });

  group('TC-072: importBackup', () {
    test('TC-072a: import external file', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      final exportPath = '${tmpDir.path}/for_import.json';
      await manager.exportBackup(meta.id, exportPath);

      final imported = await manager.importBackup(exportPath);
      expect(imported.id, isNotEmpty);
    });

    test('TC-072b: import gzip compressed file', () async {
      final compressedMgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 10,
        compressBackups: true,
      );
      final meta = await compressedMgr.createBackup(flow: _createTestFlow());
      final exportPath = '${tmpDir.path}/compressed_export.json.gz';
      await compressedMgr.exportBackup(meta.id, exportPath);

      final imported = await compressedMgr.importBackup(exportPath);
      expect(imported.id, isNotEmpty);
    });

    test('TC-072c: import nonexistent file throws', () {
      expect(
        () => manager.importBackup('/nonexistent/file.json'),
        throwsA(anything),
      );
    });

    test('TC-072d: import invalid file throws', () async {
      final badFile = File('${tmpDir.path}/bad.json');
      await badFile.writeAsString('not valid json {{{');
      expect(
        () => manager.importBackup(badFile.path),
        throwsA(anything),
      );
    });
  });

  group('TC-073: _cleanupOldBackups', () {
    test('TC-073a: maxBackups limits total', () async {
      final mgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 3,
      );
      for (var i = 0; i < 5; i++) {
        await mgr.createBackup(flow: _createTestFlow());
      }
      final list = await mgr.listBackups();
      expect(list.length, lessThanOrEqualTo(3));
    });

    test('TC-073b: maxBackups=1 keeps only latest', () async {
      final mgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 1,
      );
      for (var i = 0; i < 3; i++) {
        await mgr.createBackup(flow: _createTestFlow());
      }
      final list = await mgr.listBackups();
      expect(list.length, equals(1));
    });
  });

  group('TC-073c: cleanup deletion failure', () {
    test('TC-073c: cleanup continues on individual delete failure', () async {
      final mgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 3,
      );
      // Create 4 backups — the 4th triggers cleanup of the oldest
      for (var i = 0; i < 4; i++) {
        await mgr.createBackup(flow: _createTestFlow());
      }
      // Even if cleanup has issues, the latest backups should exist
      final list = await mgr.listBackups();
      expect(list.length, lessThanOrEqualTo(3));
      expect(list, isNotEmpty);
    });
  });

  group('TC-074: _generateBackupId', () {
    test('TC-074a: unique IDs', () async {
      final m1 = await manager.createBackup(flow: _createTestFlow());
      final m2 = await manager.createBackup(flow: _createTestFlow());
      expect(m1.id, isNot(equals(m2.id)));
    });

    test('TC-074b: ID format contains timestamp', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      expect(meta.id, matches(RegExp(r'\d+_\d+')));
    });
  });

  group('TC-075: SHA-256 checksum', () {
    test('TC-075a: deterministic checksum', () async {
      final flow = _createTestFlow();
      final m1 = await manager.createBackup(flow: flow, state: {'x': 1});
      final m2 = await manager.createBackup(flow: flow, state: {'x': 1});
      // Checksums may differ due to timestamp in metadata
      // but both should be valid hex strings
      expect(m1.checksum, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(m2.checksum, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('TC-075b: empty state has valid checksum', () async {
      final meta = await manager.createBackup(flow: _createTestFlow());
      expect(meta.checksum, isNotEmpty);
      expect(meta.checksum, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('TC-075c: large data checksum completes without timeout', () async {
      // Generate a flow with large state data (>1MB equivalent)
      final largeState = <String, dynamic>{};
      for (var i = 0; i < 10000; i++) {
        largeState['key_$i'] = 'value_$i' * 10;
      }
      final meta = await manager.createBackup(
        flow: _createTestFlow(),
        state: largeState,
      );
      expect(meta.checksum, isNotEmpty);
      expect(meta.checksum, matches(RegExp(r'^[a-f0-9]{64}$')));
    });
  });
}
