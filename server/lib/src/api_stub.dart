import 'package:googleapis/cloudtasks/v2.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:stats/stats.dart';

import 'firestore_extensions.dart';
import 'shared.dart';
import 'wip_config.dart' as config;

class APIStub {
  APIStub._({
    required this.projectId,
    required AutoRefreshingAuthClient authClient,
  }) : _authClient = authClient;

  static Future<APIStub> create({required String projectId}) async {
    final authClient = await clientViaApplicationDefaultCredentials(
      scopes: [
        FirestoreApi.datastoreScope,
        CloudTasksApi.cloudTasksScope,
      ],
    );

    return APIStub._(projectId: projectId, authClient: authClient);
  }

  final String projectId;
  final AutoRefreshingAuthClient _authClient;

  late final _firestoreApi = FirestoreApi(_authClient);
  late final _cloudTasks = CloudTasksApi(_authClient);

  late final String _database = 'projects/$projectId/databases/(default)';

  ProjectsDatabasesDocumentsResource get _documents =>
      _firestoreApi.projects.databases.documents;

  Future<Task> queueAggregateTask() async {
    final updateUri = '${config.webHost}/api/update-aggregate';

    final result = await _cloudTasks.projects.locations.queues.tasks.create(
      CreateTaskRequest(
        task: Task(
          httpRequest: HttpRequest(
            url: updateUri,
            oidcToken: OidcToken(
              serviceAccountEmail: config.serviceAccountEmail,
            ),
          ),
        ),
      ),
      'projects/$projectId/locations/${config.taskLocation}/queues/${config.taskQueue}',
    );

    return result;
  }

  Future<CommitResponse> increment() async => await _documents.commit(
        CommitRequest(
          writes: [
            Write(
              transform: DocumentTransform(
                document: '$_database/documents/settings/count',
                fieldTransforms: [
                  FieldTransform(
                    fieldPath: 'count',
                    increment: Value(integerValue: '1'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _database,
      );

  Future<LightStats<double>> aggregate() async =>
      await _documents.withTransaction(
        (tx) async {
          final value = await LightStats.fromStream(
            _documents
                .listAll('$_database/documents', 'users', transaction: tx)
                .expand((element) => element)
                .map(
                  (event) =>
                      (event.literalValues?['value'] as num?)?.toDouble(),
                )
                .where((event) => event != null)
                .cast<double>(),
          );

          await _documents.batchWrite(
            BatchWriteRequest(
              writes: [
                Write(
                  update: _documentFromMap(
                    name: '$_database/documents/settings/summary',
                    value: value.toJson(),
                  ),
                ),
              ],
            ),
            _database,
          );

          return value;
        },
        _database,
      );

  Future<BatchWriteResponse> updateValue(String jwt, num value) async {
    final result = await _documents.batchWrite(
      BatchWriteRequest(
        writes: [
          Write(
            update: _documentFromMap(
              name: '$_database/documents/users/$jwt',
              value: {'value': value},
            ),
          ),
        ],
      ),
      _database,
    );

    return result;
  }

  void close() {
    _authClient.close();
  }
}

Document _documentFromMap({required String name, required JsonMap value}) =>
    Document(
      name: name,
      fields: {
        for (var entry in value.entries)
          entry.key: valueFromLiteral(entry.value),
      },
    );
