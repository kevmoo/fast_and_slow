// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: require_trailing_commas

part of 'app_server.dart';

// **************************************************************************
// ShelfRouterGenerator
// **************************************************************************

Router _$AppServerRouter(AppServer service) {
  final router = Router();
  router.add(
    'GET',
    r'/api/increment',
    service._incrementHandler,
  );
  router.add(
    'POST',
    r'/api/updateValue',
    service._updateValue,
  );
  return router;
}
