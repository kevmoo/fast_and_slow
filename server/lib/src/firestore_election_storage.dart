import 'dart:async';

import 'package:googleapis/cloudtasks/v2.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'cloud_headers.dart';
import 'firestore_extensions.dart';
import 'header_access_middleware.dart';
import 'service_config.dart';
import 'trace_context.dart';

Future<FirestoreElectionStorage> createElectionStorage(
  ServiceConfig config,
) async {
  final client = await clientViaApplicationDefaultCredentials(
    scopes: [
      FirestoreApi.datastoreScope,
      CloudTasksApi.cloudTasksScope,
    ],
  );

  return FirestoreElectionStorage(client, config);
}

class FirestoreElectionStorage {
  final AutoRefreshingAuthClient _client;
  final FirestoreApi _firestore;
  final CloudTasksApi _tasks;
  final ServiceConfig config;

  FirestoreElectionStorage(this._client, this.config)
      : _firestore = FirestoreApi(_client),
        _tasks = CloudTasksApi(_client);

  Future<void> updateBallot(String userId, double value) async {
    await _documents.patch(
      Document(fields: {'rank': valueFromLiteral(value)}),
      _ballotPath(userId),
    );

    await _queElectionUpdateTask();
  }

  Future<void> updateElection() async {
    final ballots = await _withTransaction(
      (tx) => _documents
          .listAll(
            _electionDocumentPath(),
            'ballots',
            transaction: tx,
          )
          .expand((ballotList) => ballotList)
          .toList(),
    );

    await _documents.patch(
      Document(
        fields: {
          'places': valueFromLiteral({}),
          'ballotCount': valueFromLiteral(ballots.length),
        },
      ),
      _resultsPath(),
    );
  }

  Future<void> _queElectionUpdateTask() async {
    final updateUri = '${config.webHost}/api/update-aggregate';

    if (updateUri.startsWith('https')) {
      final traceParent = currentRequestHeaders?[traceParentHeaderName];

      await _tasks.projects.locations.queues.tasks.create(
        CreateTaskRequest(
          task: Task(
            httpRequest: HttpRequest(
              url: updateUri,
              oidcToken: OidcToken(
                serviceAccountEmail: config.serviceAccountEmail,
              ),
              headers: traceParent == null
                  ? null
                  : {
                      traceParentHeaderName: TraceContext.parse(traceParent)
                          .randomize()
                          .toString(),
                    },
            ),
          ),
        ),
        'projects/${config.projectId}/locations/${config.electionUpdateTaskLocation}/queues/${config.electionUpdateTaskQueueId}',
      );
    } else {
      await http.post(
        Uri.parse(updateUri),
        headers: {
          googleCloudTaskQueueName: config.electionUpdateTaskQueueId,
        },
      );
    }
  }

  void close() {
    _client.close();
  }

  String get _databaseId => 'projects/${config.projectId}/databases/(default)';

  String get _documentsPath => '$_databaseId/documents';

  String _resultsPath() => '$_documentsPath/something';

  String _electionDocumentPath() => '$_documentsPath/somethingElse';

  String _ballotPath(String userId) => '/ballots/$userId';

  ProjectsDatabasesDocumentsResource get _documents =>
      _firestore.projects.databases.documents;

  Future<T> _withTransaction<T>(
    FutureOr<T> Function(String) action,
  ) =>
      _documents.withTransaction(action, _databaseId);
}
