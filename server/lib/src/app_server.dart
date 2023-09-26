import 'dart:convert';

import 'package:google_cloud/google_cloud.dart';
import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stack_trace/stack_trace.dart';

import 'api_stub.dart';
import 'openid_config.dart';
import 'service_exception.dart';
import 'shared.dart';
import 'token_helpers.dart';
import 'wip_config.dart' as config;

part 'app_server.g.dart';

class AppServer {
  AppServer._({
    required APIStub stub,
    required bool hosted,
    required JsonWebKeyStore keyStore,
  })  : _hosted = hosted,
        _stub = stub,
        _jsonWebKeyStore = keyStore;

  final JsonWebKeyStore _jsonWebKeyStore;

  static Future<AppServer> create() async {
    String? projectId;
    bool hosted;

    try {
      projectId = await projectIdFromMetadataServer();
      hosted = true;
    } on BadConfigurationException {
      projectId = projectIdFromEnvironment();
      hosted = false;
    }

    if (projectId == null) {
      throw BadConfigurationException(
        '''
Could not contact GCP metadata server or find the project-id in one of these
environment variables:
  ${gcpProjectIdEnvironmentVariables.join('\n  ')}''',
      );
    }

    print('Current GCP project id: $projectId');

    final stub = await APIStub.create(projectId: projectId);

    return AppServer._(
      stub: stub,
      hosted: hosted,
      keyStore: await createKeyStore(projectId),
    );
  }

  final APIStub _stub;

  String get _projectId => _stub.projectId;

  final bool _hosted;

  late final handler =
      createLoggingMiddleware(projectId: _hosted ? _projectId : null)
          .addMiddleware(_errorAndCacheMiddleware)
          .addHandler(_$AppServerRouter(this).call);

  @Route.get('/api/increment')
  Future<Response> _incrementHandler(Request request) async {
    final result = await _stub.increment();

    return _okJsonResponse(result);
  }

  @Route.post('/api/updateValue')
  Future<Response> _updateValue(Request request) async {
    final jwt = await _jwtSubjectFromRequest(request);

    final body = jsonDecode(await request.readAsString()) as JsonMap;

    final result = await _stub.updateValue(jwt, body['value'] as num);

    await _stub.queueAggregateTask();

    return Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  @Route.post('/api/update-aggregate')
  Future<Response> _updateAggregate(Request request) async {
    final jwt = await _jwtFromRequest(request, expectServiceRequest: true);

    currentLogger.debug(
      {
        'headers': request.headers,
        'jwt': jwt.claims,
        'body': await request.readAsString(),
      },
    );

    final result = await _stub.aggregate();

    currentLogger.debug(result.toJson());

    return Response.ok('okay!');
  }

  Future<String> _jwtSubjectFromRequest(Request request) async {
    final jwt = await _jwtFromRequest(request, expectServiceRequest: false);

    final hasAudience = jwt.claims.audience?.contains(_projectId);

    if (hasAudience != true) {
      throw ServiceException.authorizationTokenValidation(
        'Audience does not contain expected project "$_projectId".',
      );
    }

    return jwt.claims.subject!;
  }

  Future<JsonWebToken> _jwtFromRequest(
    Request request, {
    required bool expectServiceRequest,
  }) async {
    JsonWebToken? jwt;
    try {
      jwt = await tokenFromRequest(request, _jsonWebKeyStore);
    } catch (error, stack) {
      throw ServiceException(
        ServiceExceptionKind.authorizationTokenValidation,
        'Error parsing the authorization header.',
        innerError: error,
        innerStack: stack,
      );
    }

    if (jwt == null) {
      throw ServiceException.authorizationTokenValidation(
        'No authorization information present.',
      );
    }

    if (jwt.isVerified == true) {
      if (expectServiceRequest) {
        if (jwt.claims['email_verified'] == true &&
            jwt.claims['email'] == config.serviceAccountEmail) {
          return jwt;
        }

        print(prettyJson(jwt.claims));
        throw ServiceException.authorizationTokenValidation(
          'Expected a verified email associated with the configured service '
          'account.',
        );
      }
      return jwt;
    }

    throw ServiceException.authorizationTokenValidation(
      'Token could not be verified.',
    );
  }

  void close() {
    _stub.close();
  }
}

Response _okJsonResponse(Object json) => Response.ok(
      jsonEncode(json),
      headers: {
        'Content-Type': 'application/json',
      },
    );

Handler _errorAndCacheMiddleware(Handler innerHandler) =>
    (Request request) async {
      try {
        var response = await innerHandler(request);

        if (!response.headers.containsKey('Cache-Control')) {
          response = response.change(
            headers: {
              'Cache-Control': 'no-store',
            },
          );
        }

        return response;
      } on ServiceException catch (e, stack) {
        final clientErrorStatusCode = e.clientErrorStatusCode;
        print(
          [
            if (e.innerError != null) e.innerError!,
            if (e.innerStack != null) Trace.from(e.innerStack!).terse,
            e,
            Trace.from(stack).terse,
          ].join('\n'),
        );
        return Response(
          clientErrorStatusCode,
          body: 'Bad request! Check the `x-cloud-trace-context` response '
              'header in the server logs to learn more.',
        );
      }
    };
