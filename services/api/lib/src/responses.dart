import 'dart:convert';

import 'package:shelf/shelf.dart';

/// A JSON response with the content type the clients expect.
Response jsonResponse(Object body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
