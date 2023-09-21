// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:fast_slow_server/src/app_server.dart';
import 'package:google_cloud/google_cloud.dart';

Future<void> main() async {
  final server = await AppServer.create();

  try {
    await serveHandler(server.handler);
  } finally {
    server.close();
  }
}
