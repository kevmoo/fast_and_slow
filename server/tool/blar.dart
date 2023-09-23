import 'package:fast_slow_server/src/api_stub.dart';
import 'package:fast_slow_server/src/shared.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

Future<void> main() async {
  final authClient = await clientViaApplicationDefaultCredentials(
    scopes: [FirestoreApi.datastoreScope],
  );

  final silly = APIStub(projectId: 'f3-2023', authClient: authClient);
  try {
    print(prettyJson(await silly.updateValue('_12345', 6)));
  } finally {
    silly.close();
  }
}
