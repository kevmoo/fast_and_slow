import 'dart:convert';

import 'package:google_cloud/google_cloud.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stack_trace/stack_trace.dart';

import 'firestore_extensions.dart';
import 'openid_config.dart';
import 'service_exception.dart';
import 'shared.dart';
import 'token_helpers.dart';
import 'wip_config.dart' as config;

part 'app_server.g.dart';

class AppServer {
  AppServer._({
    required String projectId,
    required AutoRefreshingAuthClient client,
    required bool hosted,
    required List<Uri> keySetUrls,
  })  : _hosted = hosted,
        _projectId = projectId,
        _client = client {
    for (var uri in keySetUrls) {
      _jsonWebKeyStore.addKeySetUrl(uri);
    }
  }

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

    final authClient = await clientViaApplicationDefaultCredentials(
      scopes: [FirestoreApi.datastoreScope],
    );

    final openIdConfigurationUris = [
      // See https://cloud.google.com/endpoints/docs/openapi/authenticating-users-firebase#configuring_your_openapi_document
      Uri.parse(
        'https://securetoken.google.com/$projectId/.well-known/openid-configuration',
      ),
      Uri.parse(
        'https://accounts.google.com/.well-known/openid-configuration',
      ),
    ];

    final keySetUrls = await jwksUris(openIdConfigurationUris);

    return AppServer._(
      projectId: projectId,
      client: authClient,
      hosted: hosted,
      keySetUrls: keySetUrls,
    );
  }

  final _jsonWebKeyStore = JsonWebKeyStore();

  final String _projectId;
  final bool _hosted;
  final AutoRefreshingAuthClient _client;

  late final FirestoreApi _firestoreApi = FirestoreApi(_client);
  late final handler =
      createLoggingMiddleware(projectId: _hosted ? _projectId : null)
          .addMiddleware(_errorAndCacheMiddleware)
          .addHandler(_$AppServerRouter(this).call);

  @Route.get('/api/increment')
  Future<Response> _incrementHandler(Request request) async {
    final result = await _firestoreApi.projects.databases.documents.commit(
      _incrementRequest(_projectId),
      'projects/$_projectId/databases/(default)',
    );

    return _okJsonResponse(result);
  }

  @Route.options('/api/updateValue')
  Response _options(Request request) => Response(
        204,
        headers: {
          'Allow': 'OPTIONS, POST',
          'Access-Control-Allow-Origin': 'http://localhost:8080',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Allow-Headers': 'Authorization',
        },
      );

  @Route.post('/api/updateValue')
  Future<Response> _updateValue(Request request) async {
    final jwt = await _jwtSubjectFromRequest(request);

    final body = jsonDecode(await request.readAsString()) as JsonMap;

    final db = 'projects/$_projectId/databases/(default)';

    final result = await _firestoreApi.projects.databases.documents.batchWrite(
      BatchWriteRequest(
        writes: [
          Write(
            update: documentFromMap(
              name: '$db/documents/users/$jwt',
              value: {'value': body['value'] as num},
            ),
          ),
        ],
      ),
      db,
    );

    return Response.ok(
      jsonEncode(result),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': 'http://localhost:8080',
      },
    );
  }

  void close() {
    _client.close();
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
}

CommitRequest _incrementRequest(String projectId) => CommitRequest(
      writes: [
        Write(
          transform: DocumentTransform(
            document:
                'projects/$projectId/databases/(default)/documents/settings/count',
            fieldTransforms: [
              FieldTransform(
                fieldPath: 'count',
                increment: Value(integerValue: '1'),
              ),
            ],
          ),
        ),
      ],
    );

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

Document documentFromMap({required String name, required JsonMap value}) =>
    Document(
      name: name,
      fields: {
        for (var entry in value.entries)
          entry.key: valueFromLiteral(entry.value),
      },
    );
