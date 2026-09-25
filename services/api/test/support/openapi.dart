/// The contract test's view of `openapi.yaml`: the spec as plain JSON-like
/// maps, its operations, and a validator for the subset of JSON Schema the
/// spec uses. Hand-written on purpose: the spec is the source of truth and
/// nothing is generated from it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:api/api.dart';
import 'package:yaml/yaml.dart';

/// The spec beside the package root, as maps and lists.
Map<String, dynamic> loadSpec([String path = 'openapi.yaml']) =>
    jsonDecode(jsonEncode(loadYaml(File(path).readAsStringSync())))
        as Map<String, dynamic>;

/// One documented operation: `GET /v1/devices/{token}`.
typedef Operation = ({String method, String path});

String describe(Operation op) => '${op.method} ${op.path}';

const _methods = {'get', 'put', 'post', 'delete', 'patch'};

/// Every operation the spec documents.
List<Operation> documentedOperations(Map<String, dynamic> spec) => [
  for (final MapEntry(key: path, value: item)
      in (spec['paths'] as Map<String, dynamic>).entries)
    for (final method in (item as Map<String, dynamic>).keys)
      if (_methods.contains(method)) (method: method.toUpperCase(), path: path),
];

/// A shelf_router path in the spec's spelling: `<token>` becomes `{token}`.
String specPath(String routerPath) => routerPath.replaceAllMapped(
  RegExp(r'<(\w+)(\|[^>]*)?>'),
  (m) => '{${m[1]}}',
);

/// Routes the router serves that the spec does not document.
List<String> undocumentedRoutes(
  Map<String, dynamic> spec,
  Iterable<ApiRoute> routes,
) {
  final documented = documentedOperations(spec).map(describe).toSet();
  return [
    for (final route in routes)
      if (!documented.contains('${route.method} ${specPath(route.path)}'))
        '${route.method} ${specPath(route.path)}',
  ];
}

/// Operations the spec documents that the router does not serve.
List<String> unservedOperations(
  Map<String, dynamic> spec,
  Iterable<ApiRoute> routes,
) {
  final served = {
    for (final route in routes) '${route.method} ${specPath(route.path)}',
  };
  return [
    for (final op in documentedOperations(spec))
      if (!served.contains(describe(op))) describe(op),
  ];
}

/// The documented response of [op] for [status], or null.
Map<String, dynamic>? responseFor(
  Map<String, dynamic> spec,
  Operation op,
  int status,
) {
  final operation =
      (spec['paths'][op.path] as Map)[op.method.toLowerCase()] as Map;
  final responses = operation['responses'] as Map;
  final response = responses['$status'] as Map<String, dynamic>?;
  return response == null ? null : _deref(spec, response);
}

/// Whether [op] needs a bearer token: its own `security`, or the spec's.
bool requiresSignIn(Map<String, dynamic> spec, Operation op) {
  final operation =
      (spec['paths'][op.path] as Map)[op.method.toLowerCase()] as Map;
  final security = (operation['security'] ?? spec['security']) as List?;
  return security != null && security.isNotEmpty;
}

/// Statuses [op] documents.
Set<int> documentedStatuses(Map<String, dynamic> spec, Operation op) {
  final operation =
      (spec['paths'][op.path] as Map)[op.method.toLowerCase()] as Map;
  return {
    for (final key in (operation['responses'] as Map).keys) int.parse('$key'),
  };
}

Map<String, dynamic> _deref(
  Map<String, dynamic> spec,
  Map<String, dynamic> node,
) {
  final ref = node[r'$ref'];
  if (ref is! String) return node;
  Object? target = spec;
  for (final part in ref.substring(2).split('/')) {
    target = (target as Map)[part];
  }
  return _deref(spec, target as Map<String, dynamic>);
}

/// Every way [value] breaks [schema], as `path: reason`; empty when it fits.
/// Covers what `openapi.yaml` uses: `$ref`, `type` (one or a list),
/// `properties`, `required`, `additionalProperties`, `items`, `enum`,
/// `const`, `allOf`, `oneOf`, `minLength` and `pattern`.
List<String> validate(
  Map<String, dynamic> spec,
  Map<String, dynamic> schema,
  Object? value, [
  String at = r'$',
]) {
  final s = _deref(spec, schema);
  final errors = <String>[];

  final type = s['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    if (!types.any((t) => _isType(t, value))) {
      return ['$at: expected ${types.join('|')}, got ${_typeOf(value)}'];
    }
  }
  if (s.containsKey('const') && value != s['const']) {
    errors.add('$at: expected ${s['const']}');
  }
  final allowed = s['enum'];
  if (allowed is List && !allowed.contains(value)) {
    errors.add('$at: $value not in $allowed');
  }
  if (value is String) {
    final min = s['minLength'];
    if (min is int && value.length < min) errors.add('$at: shorter than $min');
    final pattern = s['pattern'];
    if (pattern is String && !RegExp(pattern).hasMatch(value)) {
      errors.add('$at: does not match $pattern');
    }
  }
  if (value is Map) {
    final properties = (s['properties'] as Map<String, dynamic>?) ?? const {};
    for (final name in (s['required'] as List?) ?? const []) {
      if (!value.containsKey(name)) errors.add('$at.$name: required');
    }
    for (final MapEntry(:key, value: v) in value.entries) {
      final property = properties[key];
      if (property is Map<String, dynamic>) {
        errors.addAll(validate(spec, property, v, '$at.$key'));
      } else if (s['additionalProperties'] == false) {
        errors.add('$at.$key: not allowed');
      } else if (s['additionalProperties'] is Map<String, dynamic>) {
        errors.addAll(
          validate(
            spec,
            s['additionalProperties'] as Map<String, dynamic>,
            v,
            '$at.$key',
          ),
        );
      }
    }
  }
  if (value is List && s['items'] is Map<String, dynamic>) {
    for (var i = 0; i < value.length; i++) {
      errors.addAll(
        validate(spec, s['items'] as Map<String, dynamic>, value[i], '$at[$i]'),
      );
    }
  }
  final allOf = s['allOf'];
  if (allOf is List) {
    for (final part in allOf) {
      errors.addAll(validate(spec, part as Map<String, dynamic>, value, at));
    }
  }
  final oneOf = s['oneOf'];
  if (oneOf is List) {
    final matches = oneOf
        .where((o) => validate(spec, o as Map<String, dynamic>, value).isEmpty)
        .length;
    if (matches != 1) errors.add('$at: matches $matches of oneOf, not 1');
  }
  return errors;
}

bool _isType(String type, Object? value) => switch (type) {
  'null' => value == null,
  'string' => value is String,
  'boolean' => value is bool,
  'integer' => value is int,
  'number' => value is num,
  'array' => value is List,
  'object' => value is Map,
  _ => false,
};

String _typeOf(Object? value) => switch (value) {
  null => 'null',
  String() => 'string',
  bool() => 'boolean',
  int() => 'integer',
  num() => 'number',
  List() => 'array',
  Map() => 'object',
  _ => value.runtimeType.toString(),
};
