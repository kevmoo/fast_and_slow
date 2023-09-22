import 'package:fast_slow_server/src/app_server.dart';
import 'package:fast_slow_server/src/shared.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

Future<void> main() async {
  final _projectId = 'f3-2023';

  final authClient = await clientViaApplicationDefaultCredentials(
    scopes: [FirestoreApi.datastoreScope],
  );

  final _firestoreApi = FirestoreApi(authClient);

  final db = 'projects/$_projectId/databases/(default)';

  final result = await _firestoreApi.projects.databases.documents.batchWrite(
    BatchWriteRequest(
      writes: [
        Write(
          update: documentFromMap(
            name: '$db/documents/users/a12345',
            value: {'value': 6},
          ),
        ),
      ],
    ),
    db,
  );

  print(prettyJson(result));
}
