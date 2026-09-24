import 'package:shelf_router/shelf_router.dart';

/// One route the api serves, in shelf_router's spelling:
/// `DELETE /v1/devices/<token>`.
class ApiRoute {
  const ApiRoute(this.method, this.path);

  final String method;
  final String path;

  @override
  String toString() => '$method $path';
}

/// A shelf_router [Router] that also records what it serves, because the
/// router keeps its routes private and the contract test must compare them
/// with `openapi.yaml`. Every route is added through [add].
class RouteTable {
  final Router router = Router();
  final List<ApiRoute> routes = [];

  void add(String method, String path, Function handler) {
    router.add(method, path, handler);
    routes.add(ApiRoute(method, path));
  }
}
