import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/core/backup_manager.dart';

void main() {
  group('Configuration Backup/Restore', () {
    late McpFlowRuntime runtime;
    late String backupDir;

    setUp(() async {
      // Create a temporary backup directory
      backupDir = 'test_backups_${DateTime.now().millisecondsSinceEpoch}';
      runtime = McpFlowRuntime(
        backupManager: BackupManager(
          backupDirectory: backupDir,
          maxBackups: 5,
        ),
      );
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
      
      // Clean up backup directory
      try {
        final dir = Directory(backupDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('create and list backups', () async {
      final flow = {
        'version': '1.0.0',
        'metadata': {
          'name': 'Test Flow',
          'description': 'Flow for backup testing',
        },
        'state': {
          'counter': {'type': 'number', 'initial': 0},
          'message': {'type': 'string', 'initial': 'Hello'},
        },
        'processes': [],
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Create a backup
      final metadata = await runtime.createBackup(
        description: 'Test backup',
        tags: {'test': true, 'version': 1},
      );

      expect(metadata.description, equals('Test backup'));
      expect(metadata.tags?['test'], isTrue);
      expect(metadata.version, equals('1.0.0'));
      expect(metadata.checksum, isNotNull);
      expect(metadata.size, greaterThan(0));

      // List backups
      final backups = await runtime.listBackups();
      expect(backups.length, equals(1));
      expect(backups.first.id, equals(metadata.id));
    });

    test('backup includes state', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'count': {'type': 'number', 'initial': 10},
          'items': {'type': 'array', 'initial': ['a', 'b', 'c']},
          'config': {
            'type': 'object',
            'initial': {'enabled': true, 'timeout': 5000},
          },
        },
        'processes': [],
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Modify state
      await runtime.setState('count', 42);
      await runtime.setState('items', ['x', 'y', 'z']);
      await runtime.setState('config', {'enabled': false, 'timeout': 3000});

      // Create backup
      final metadata = await runtime.createBackup(
        description: 'State backup',
        includeState: true,
      );

      // Create new runtime and restore
      final runtime2 = McpFlowRuntime(
        backupManager: BackupManager(
          backupDirectory: backupDir,
        ),
      );

      await runtime2.restoreBackup(metadata.id);
      await runtime2.start();

      // Verify state was restored
      expect(runtime2.getState('count'), equals(42));
      expect(runtime2.getState('items'), equals(['x', 'y', 'z']));
      expect(runtime2.getState('config'), equals({'enabled': false, 'timeout': 3000}));

      await runtime2.stop();
    });

    test('restore flow configuration', () async {
      final flow = {
        'version': '2.0.0',
        'metadata': {
          'name': 'Complex Flow',
          'author': 'Test Suite',
        },
        'resources': {
          'sensor': {
            'type': 'gpio',
            'config': {
              'pin': 5,
              'mode': 'input'
            },
          },
        },
        'state': {
          'sensorValue': {'type': 'number', 'initial': 0},
        },
        'processes': [
          {
            'id': 'read_sensor',
            'trigger': {'type': 'schedule', 'interval': 1000},
            'steps': [
              {
                'action': 'gpioRead',
                'params': {'pin': 5},
                'bindTo': 'sensorValue',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      
      // Create backup
      final metadata = await runtime.createBackup(
        description: 'Flow configuration backup',
      );

      // Create new runtime and restore
      final runtime2 = McpFlowRuntime(
        backupManager: BackupManager(
          backupDirectory: backupDir,
        ),
      );

      await runtime2.restoreBackup(metadata.id);
      
      // Start the runtime to verify flow was restored correctly
      await runtime2.start();
      
      // Verify flow was restored by checking state variables exist
      expect(runtime2.getState('sensorValue'), equals(0)); // Initial value
      
      // Verify the runtime is working with the restored flow
      expect(runtime2.status, equals(RuntimeStatus.running));
      
      await runtime2.stop();
    });

    test('multiple backups with cleanup', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'value': {'type': 'number', 'initial': 0},
        },
        'processes': [],
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Create multiple backups (more than maxBackups=5)
      final backupIds = <String>[];
      for (int i = 0; i < 7; i++) {
        await runtime.setState('value', i);
        final metadata = await runtime.createBackup(
          description: 'Backup $i',
        );
        backupIds.add(metadata.id);
        
        // Small delay to ensure different timestamps
        await Future.delayed(Duration(milliseconds: 10));
      }

      // List backups - should only have 5 (maxBackups)
      final backups = await runtime.listBackups();
      expect(backups.length, equals(5));

      // Oldest backups should be deleted
      expect(backups.any((b) => b.id == backupIds[0]), isFalse);
      expect(backups.any((b) => b.id == backupIds[1]), isFalse);
      
      // Newest backups should exist
      expect(backups.any((b) => b.id == backupIds[6]), isTrue);
      expect(backups.any((b) => b.id == backupIds[5]), isTrue);
    });

    test('export and import backup', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'data': {'type': 'string', 'initial': 'original'},
        },
        'processes': [],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.setState('data', 'modified');

      // Create and export backup
      final metadata = await runtime.createBackup(
        description: 'Export test',
      );
      
      final exportPath = '$backupDir/exported_backup.json';
      await runtime.exportBackup(metadata.id, exportPath);

      // Verify export file exists
      expect(await File(exportPath).exists(), isTrue);

      // Delete original backup
      await runtime.deleteBackup(metadata.id);
      expect((await runtime.listBackups()).any((b) => b.id == metadata.id), isFalse);

      // Import backup
      final importedMetadata = await runtime.importBackup(exportPath);
      expect(importedMetadata.id, equals(metadata.id));
      expect(importedMetadata.description, equals('Export test'));

      // Verify imported backup exists
      expect((await runtime.listBackups()).any((b) => b.id == metadata.id), isTrue);

      // Restore from imported backup
      await runtime.stop();
      await runtime.restoreBackup(importedMetadata.id);
      await runtime.start();
      
      expect(runtime.getState('data'), equals('modified'));
    });

    test('backup without state', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'secret': {'type': 'string', 'initial': 'password123'},
        },
        'processes': [],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.setState('secret', 'new-password');

      // Create backup without state
      final metadata = await runtime.createBackup(
        description: 'No state backup',
        includeState: false,
      );

      // Restore in new runtime
      final runtime2 = McpFlowRuntime(
        backupManager: BackupManager(
          backupDirectory: backupDir,
        ),
      );

      await runtime2.restoreBackup(metadata.id);
      await runtime2.start();

      // State should have initial value, not backed up value
      expect(runtime2.getState('secret'), equals('password123'));

      await runtime2.stop();
    });

    test('compressed backups', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'largeData': {
            'type': 'string',
            'initial': 'x' * 1000, // Large string
          },
        },
        'processes': [],
      };

      // Create runtime with compression enabled
      final compressedRuntime = McpFlowRuntime(
        backupManager: BackupManager(
          backupDirectory: backupDir,
          compressBackups: true,
        ),
      );

      await compressedRuntime.loadFlow(flow);
      await compressedRuntime.start();

      // Create compressed backup
      final metadata = await compressedRuntime.createBackup(
        description: 'Compressed backup',
      );

      // Check that backup file is compressed
      final backupFile = File('$backupDir/backup_${metadata.id}.json.gz');
      expect(await backupFile.exists(), isTrue);

      // Restore from compressed backup
      await compressedRuntime.stop();
      await compressedRuntime.restoreBackup(metadata.id);
      await compressedRuntime.start();

      expect(compressedRuntime.getState('largeData'), equals('x' * 1000));

      await compressedRuntime.stop();
    });
  });
}