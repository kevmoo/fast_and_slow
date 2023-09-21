import 'dart:async';

import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';

FutureOr<JsonWebToken?> tokenFromRequest(
  Request request,
  JsonWebKeyStore store,
) async {
  final auth = request.headers[_authHeader];
  if (auth != null && auth.startsWith(_bearerPrefix)) {
    final jwtString = auth.substring(_bearerPrefix.length);
    return await JsonWebToken.decodeAndVerify(
      jwtString,
      store,
    );
  }
  return null;
}

const _authHeader = 'authorization';
const _bearerPrefix = 'Bearer ';
