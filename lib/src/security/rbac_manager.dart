import 'package:logging/logging.dart';

/// Role definition with associated permissions
class RoleDefinition {
  final String name;

  /// Permission strings; '*' means full access.
  /// Format: '<resource>.<action>' (e.g. 'process.start', 'state.read')
  final List<String> permissions;

  final String description;

  const RoleDefinition({
    required this.name,
    required this.permissions,
    required this.description,
  });
}

/// Binds a role to a set of subjects
class RoleBinding {
  final String role;

  /// Subject strings. Prefix indicates type:
  ///   'user:<email>', 'group:<name>', 'serviceAccount:<id>'
  final List<String> subjects;

  const RoleBinding({
    required this.role,
    required this.subjects,
  });
}

/// RBAC configuration
class RbacConfig {
  /// Role definitions keyed by role name
  final Map<String, RoleDefinition> roles;

  /// Role bindings that assign roles to subjects
  final List<RoleBinding> bindings;

  const RbacConfig({
    required this.roles,
    required this.bindings,
  });

  /// Creates a default configuration with built-in roles
  factory RbacConfig.withDefaults({
    Map<String, RoleDefinition>? additionalRoles,
    List<RoleBinding> bindings = const [],
  }) {
    final roles = <String, RoleDefinition>{
      'admin': const RoleDefinition(
        name: 'admin',
        permissions: ['*'],
        description: 'Full system access',
      ),
      'operator': const RoleDefinition(
        name: 'operator',
        permissions: [
          'process.start',
          'process.stop',
          'state.read',
          'resource.read',
        ],
        description: 'Operation control',
      ),
      'monitor': const RoleDefinition(
        name: 'monitor',
        permissions: ['state.read', 'resource.read', 'log.read'],
        description: 'Read-only monitoring',
      ),
    };
    if (additionalRoles != null) {
      roles.addAll(additionalRoles);
    }
    return RbacConfig(roles: roles, bindings: bindings);
  }
}

/// Permission denied exception
class PermissionDeniedException implements Exception {
  final String subject;
  final String permission;

  const PermissionDeniedException(this.subject, this.permission);

  @override
  String toString() =>
      'PermissionDeniedException: $subject lacks permission $permission';
}

/// Manages Role-Based Access Control with in-memory caching
class RbacManager {
  final RbacConfig config;

  static final _log = Logger('RbacManager');

  /// Cache of permission check results: (subject, permission) -> bool
  final Map<(String, String), bool> _cache = {};

  /// Cache of subject -> roles mapping
  final Map<String, List<String>> _rolesCache = {};

  /// Cache of subject -> permissions mapping
  final Map<String, Set<String>> _permissionsCache = {};

  RbacManager(this.config);

  /// Returns all roles assigned to the given subject string.
  List<String> getRolesForSubject(String subject) {
    final cached = _rolesCache[subject];
    if (cached != null) return cached;

    final roles = <String>[];
    for (final binding in config.bindings) {
      if (binding.subjects.contains(subject)) {
        roles.add(binding.role);
      }
    }

    _rolesCache[subject] = roles;
    return roles;
  }

  /// Returns all permissions granted to the given subject across all assigned roles.
  Set<String> getPermissionsForSubject(String subject) {
    final cached = _permissionsCache[subject];
    if (cached != null) return cached;

    final permissions = <String>{};
    final roles = getRolesForSubject(subject);

    for (final roleName in roles) {
      final role = config.roles[roleName];
      if (role != null) {
        permissions.addAll(role.permissions);
      }
    }

    _permissionsCache[subject] = permissions;
    return permissions;
  }

  /// Checks whether [subject] holds [permission].
  /// A subject with the '*' wildcard permission always returns true.
  /// Results are cached per (subject, permission) pair.
  bool checkPermission(String subject, String permission) {
    final cacheKey = (subject, permission);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final permissions = getPermissionsForSubject(subject);
    final allowed = permissions.contains('*') ||
        permissions.contains(permission);

    _cache[cacheKey] = allowed;

    if (!allowed) {
      _log.warning('Permission denied: $subject -> $permission');
    }

    return allowed;
  }

  /// Invalidates the permission cache (call after binding changes).
  void invalidateCache() {
    _cache.clear();
    _rolesCache.clear();
    _permissionsCache.clear();
    _log.info('RBAC cache invalidated');
  }
}
