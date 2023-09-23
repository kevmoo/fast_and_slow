import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'firestore_extensions.dart';
import 'shared.dart';

class APIStub {
  APIStub({
    required this.projectId,
    required this.authClient,
  });

  final String projectId;
  final AutoRefreshingAuthClient authClient;

  late final FirestoreApi firestoreApi = FirestoreApi(authClient);

  Future<BatchWriteResponse> updateValue(String jwt, num value) async {
    final db = 'projects/$projectId/databases/(default)';

    final result = await firestoreApi.projects.databases.documents.batchWrite(
      BatchWriteRequest(
        writes: [
          Write(
            update: documentFromMap(
              name: '$db/documents/users/$jwt',
              value: {'value': value},
            ),
          ),
        ],
      ),
      db,
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
