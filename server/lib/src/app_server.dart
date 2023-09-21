import 'dart:convert';

import 'package:google_cloud/google_cloud.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

part 'app_server.g.dart';

class AppServer {
  AppServer._({
    required String projectId,
    required AutoRefreshingAuthClient client,
    required bool hosted,
  })  : _hosted = hosted,
        _projectId = projectId,
        _client = client;

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

    return AppServer._(
      projectId: projectId,
      client: authClient,
      hosted: hosted,
    );
  }

  Router get router => _$AppServerRouter(this);

  final String _projectId;
  final bool _hosted;
  final AutoRefreshingAuthClient _client;

  late final FirestoreApi _firestoreApi = FirestoreApi(_client);
  late final handler =
      createLoggingMiddleware(projectId: _hosted ? _projectId : null)
          .addHandler(_$AppServerRouter(this).call);

  @Route.get('/api/increment')
  Future<Response> _incrementHandler(Request request) async {
    final result = await _firestoreApi.projects.databases.documents.commit(
      _incrementRequest(_projectId),
      'projects/$_projectId/databases/(default)',
    );

    return Response.ok(
      JsonUtf8Encoder(' ').convert(result),
      headers: {'content-type': 'application/json'},
    );
  }

  void close() {
    _client.close();
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
