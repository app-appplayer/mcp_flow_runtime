/// DatabaseService - Database abstraction for MCP Flow Runtime
///
/// MOD-SVC-005: Provides a unified CRUD interface with transaction support.
/// Concrete backends (SQLite, PostgreSQL, InfluxDB) can be swapped via
/// the DatabaseBackendType strategy.
import 'dart:async';
import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Supported database backend types.
enum DatabaseBackendType { sqlite, postgresql, influxdb }

/// Configuration for a database connection.
class DatabaseConfig {
  final DatabaseBackendType backend;
  final String connectionString;
  final int? maxConnections;
  final Duration? connectionTimeout;

  const DatabaseConfig({
    required this.backend,
    required this.connectionString,
    this.maxConnections,
    this.connectionTimeout,
  });
}

/// Transaction handle for atomic database operations.
abstract class DatabaseTransaction {
  /// Executes a SELECT query within the transaction.
  Future<List<Map<String, dynamic>>> query(String sql,
      {List<dynamic> params = const []});

  /// Inserts a row and returns the row ID.
  Future<int> insert(String table, Map<String, dynamic> data);

  /// Updates rows matching [where] and returns affected count.
  Future<int> update(String table, Map<String, dynamic> data, String where,
      {List<dynamic> whereParams = const []});

  /// Deletes rows matching [where] and returns affected count.
  Future<int> delete(String table, String where,
      {List<dynamic> whereParams = const []});
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by database operations.
class DatabaseServiceException implements Exception {
  final String serviceId = 'database';
  final String operation;
  final String message;
  final dynamic cause;
  final String? database;
  final String? sql;
  final int? errorCode;

  const DatabaseServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.database,
    this.sql,
    this.errorCode,
  });

  @override
  String toString() =>
      'DatabaseServiceException($operation): $message${database != null ? ' [db=$database]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract database service.
abstract class DatabaseService extends SystemService {
  /// Executes a SELECT query and returns a list of row maps.
  Future<List<Map<String, dynamic>>> query(
    String database,
    String sql, {
    List<dynamic> params = const [],
  });

  /// Inserts [data] into [table] in [database]. Returns the inserted row ID.
  Future<int> insert(
    String database,
    String table,
    Map<String, dynamic> data,
  );

  /// Updates rows in [table] matching [where] in [database]. Returns affected row count.
  Future<int> update(
    String database,
    String table,
    Map<String, dynamic> data,
    String where, {
    List<dynamic> whereParams = const [],
  });

  /// Deletes rows from [table] matching [where] in [database]. Returns affected row count.
  Future<int> delete(
    String database,
    String table,
    String where, {
    List<dynamic> whereParams = const [],
  });

  /// Executes [operations] atomically. Rolls back on any exception.
  Future<T> transaction<T>(
    String database,
    Future<T> Function(DatabaseTransaction tx) operations,
  );

  /// Creates a backup of [database] to [destinationPath].
  Future<void> backup(String database, String destinationPath);
}

// ---------------------------------------------------------------------------
// In-memory implementation (key-value store for development/testing)
// ---------------------------------------------------------------------------

/// Simple in-memory database implementation backed by nested maps.
///
/// Data structure: _databases[dbName][tableName] = List<Map<String, dynamic>>
/// This is suitable for testing and lightweight use cases.
class InMemoryDatabaseService extends DatabaseService {
  final Logger _log = Logger('InMemoryDatabaseService');
  bool _ready = false;

  /// Storage: database -> table -> rows
  final Map<String, Map<String, List<Map<String, dynamic>>>> _databases = {};

  /// Auto-increment counters: database -> table -> nextId
  final Map<String, Map<String, int>> _counters = {};

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('InMemoryDatabaseService initialized');
  }

  @override
  Future<void> dispose() async {
    _databases.clear();
    _counters.clear();
    _ready = false;
    _log.info('InMemoryDatabaseService disposed');
  }

  @override
  bool get isReady => _ready;

  Map<String, List<Map<String, dynamic>>> _getDb(String database) {
    return _databases.putIfAbsent(database, () => {});
  }

  List<Map<String, dynamic>> _getTable(String database, String table) {
    final db = _getDb(database);
    return db.putIfAbsent(table, () => []);
  }

  int _nextId(String database, String table) {
    final dbCounters = _counters.putIfAbsent(database, () => {});
    final current = dbCounters[table] ?? 0;
    dbCounters[table] = current + 1;
    return current + 1;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String database,
    String sql, {
    List<dynamic> params = const [],
  }) async {
    // Simple implementation: parse "SELECT * FROM tableName" style queries
    final match = RegExp(r'SELECT\s+\*\s+FROM\s+(\w+)', caseSensitive: false)
        .firstMatch(sql);
    if (match == null) {
      throw DatabaseServiceException(
        operation: 'query',
        message: 'QUERY_SYNTAX_ERROR: Only "SELECT * FROM table" is supported in InMemoryDatabaseService',
        database: database,
        sql: sql,
      );
    }
    final table = match.group(1)!;
    return List<Map<String, dynamic>>.from(
      _getTable(database, table).map((row) => Map<String, dynamic>.from(row)),
    );
  }

  @override
  Future<int> insert(
    String database,
    String table,
    Map<String, dynamic> data,
  ) async {
    final id = _nextId(database, table);
    final row = Map<String, dynamic>.from(data)..['_id'] = id;
    _getTable(database, table).add(row);
    _log.fine('Inserted row $id into $database.$table');
    return id;
  }

  @override
  Future<int> update(
    String database,
    String table,
    Map<String, dynamic> data,
    String where, {
    List<dynamic> whereParams = const [],
  }) async {
    final rows = _getTable(database, table);
    int affected = 0;
    for (final row in rows) {
      if (_matchWhere(row, where, whereParams)) {
        row.addAll(data);
        affected++;
      }
    }
    return affected;
  }

  @override
  Future<int> delete(
    String database,
    String table,
    String where, {
    List<dynamic> whereParams = const [],
  }) async {
    final rows = _getTable(database, table);
    final before = rows.length;
    rows.removeWhere((row) => _matchWhere(row, where, whereParams));
    return before - rows.length;
  }

  @override
  Future<T> transaction<T>(
    String database,
    Future<T> Function(DatabaseTransaction tx) operations,
  ) async {
    // Snapshot current state for rollback
    final db = _getDb(database);
    final snapshot = <String, List<Map<String, dynamic>>>{};
    for (final entry in db.entries) {
      snapshot[entry.key] =
          entry.value.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    try {
      final tx = _InMemoryTransaction(this, database);
      final result = await operations(tx);
      return result;
    } catch (e) {
      // Rollback: restore snapshot
      db.clear();
      db.addAll(snapshot);
      _log.warning('Transaction rolled back for $database: $e');
      rethrow;
    }
  }

  @override
  Future<void> backup(String database, String destinationPath) async {
    // TODO: Serialize in-memory data to file at destinationPath
    _log.info('Backup requested for $database to $destinationPath (no-op in memory)');
  }

  /// Simple where clause matching: supports "column = ?" pattern.
  bool _matchWhere(
      Map<String, dynamic> row, String where, List<dynamic> params) {
    final match =
        RegExp(r'(\w+)\s*=\s*\?').firstMatch(where);
    if (match == null) return false;
    final column = match.group(1)!;
    if (params.isEmpty) return false;
    return row[column] == params.first;
  }
}

/// Transaction handle for the in-memory database.
class _InMemoryTransaction extends DatabaseTransaction {
  final InMemoryDatabaseService _service;
  final String _database;

  _InMemoryTransaction(this._service, this._database);

  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List<dynamic> params = const []}) {
    return _service.query(_database, sql, params: params);
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) {
    return _service.insert(_database, table, data);
  }

  @override
  Future<int> update(String table, Map<String, dynamic> data, String where,
      {List<dynamic> whereParams = const []}) {
    return _service.update(_database, table, data, where,
        whereParams: whereParams);
  }

  @override
  Future<int> delete(String table, String where,
      {List<dynamic> whereParams = const []}) {
    return _service.delete(_database, table, where,
        whereParams: whereParams);
  }
}

// ---------------------------------------------------------------------------
// Stub implementations for other backends
// ---------------------------------------------------------------------------

// TODO: Implement SqliteDatabaseService using sqflite or sqlite3 package
// TODO: Implement PostgresDatabaseService using postgres package
// TODO: Implement InfluxDatabaseService using influxdb_client package
