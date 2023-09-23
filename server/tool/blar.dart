import 'package:fast_slow_server/src/api_stub.dart';
import 'package:fast_slow_server/src/shared.dart';

Future<void> main() async {
  final silly = await APIStub.create(projectId: 'f3-2023');
  try {
    print(prettyJson(await silly.aggregate()));
  } finally {
    silly.close();
  }
}
