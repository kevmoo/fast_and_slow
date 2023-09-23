import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:stats/stats.dart';

import 'firestore_extensions.dart';
import 'shared.dart';

class APIStub {
  APIStub._({
    required this.projectId,
    required this.authClient,
  });

  static Future<APIStub> create({required String projectId}) async {
    final authClient = await clientViaApplicationDefaultCredentials(
      scopes: [FirestoreApi.datastoreScope],
    );

    return APIStub._(projectId: projectId, authClient: authClient);
  }

  final String projectId;
  final AutoRefreshingAuthClient authClient;

  late final FirestoreApi _firestoreApi = FirestoreApi(authClient);

  String get _database => 'projects/$projectId/databases/(default)';

  ProjectsDatabasesDocumentsResource get documents =>
      _firestoreApi.projects.databases.documents;

  Future<LightStats<double>> aggregate() async =>
      await documents.withTransaction(
        (tx) async {
          final value = await LightStats.fromStream(
            documents
                .listAll('$_database/documents', 'users')
                .expand((element) => element)
                .map((event) {
                  final val = event.fields!['value']?.doubleValue;
                  return val;
                })
                .where((event) => event != null)
                .cast<double>(),
          );

          await documents.batchWrite(
            BatchWriteRequest(
              writes: [
                Write(
                  update: documentFromMap(
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
    final result = await documents.batchWrite(
      BatchWriteRequest(
        writes: [
          Write(
            update: documentFromMap(
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
    authClient.close();
  }
}

Document documentFromMap({required String name, required JsonMap value}) =>
    Document(
      name: name,
      fields: {
        for (var entry in value.entries)
          entry.key: valueFromLiteral(entry.value),
      },
    );
