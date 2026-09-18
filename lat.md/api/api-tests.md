# Api tests

What the api's `dart test` suite in `services/api/test/` guards, run by the `api` job of the verify gate ([[deployment#Pipeline]]).

## Health

`health_test.dart` drives the handler directly with shelf requests, no socket, so the route is tested as a function ([[api-architecture#Handler]]).

### GET healthz answers 200 with the version

`GET /healthz` returns 200, a JSON content type, `status` of `ok` and the `version` the package declares.

### Unknown routes answer 404

A path the router does not know returns 404 rather than falling through to anything.
