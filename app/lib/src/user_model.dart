import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:stats/stats.dart';

abstract class UserModel with ChangeNotifier {
  UserModel(this._user);

  final User _user;

  bool sameUser(User user) => user == _user;

  double get value;
  set value(double val);

  String get syncValue;

  LightStats<double> get stats;
}

class HttpPostUserModel extends UserModel {
  HttpPostUserModel(super.user) {
    final userDoc = FirebaseFirestore.instance.doc('users/${_user.uid}');
    final statsDoc = FirebaseFirestore.instance.doc('settings/summary');

    _snapShotSub = userDoc.snapshots().listen(_docSnapshot);
    _settingsSub = statsDoc.snapshots().listen(_settingsSnapshot);
  }

  static const _valueKey = 'value';

  double _value = _defaultValue;
  String __syncValue = '???';

  @override
  double get value => _value;
  @override
  String get syncValue => __syncValue;

  bool _uploading = false;

  @override
  set value(double val) {
    if (val != _value) {
      _value = val;

      Future.microtask(_post);

      notifyListeners();
    }
  }

  set _syncValue(String val) {
    if (val != __syncValue) {
      __syncValue = val;
      notifyListeners();
    }
  }

  LightStats<double> _stats = LightStats<double>.fromData([5.0]);

  @override
  LightStats<double> get stats => _stats;

  Future<void> _post() async {
    if (!_uploading) {
      _uploading = true;
      final valueToSend = _value;
      final token = await _user.getIdToken();

      await http.post(
        Uri.parse('/api/updateValue'),
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode(
          {'value': valueToSend},
        ),
      );

      _uploading = false;

      if (valueToSend != _value) {
        // need to post again
        unawaited(Future.microtask(_post));
      } else {
        // no change
      }
    } else {
      // upload already pending
    }
  }

  late final StreamSubscription<DocumentSnapshot> _snapShotSub;
  late final StreamSubscription<DocumentSnapshot> _settingsSub;

  String get uid => _user.uid;

  void _docSnapshot(DocumentSnapshot incomingValue) {
    final snapshotVal = incomingValue.data();

    if (snapshotVal case {_valueKey: num x}) {
      value = x.toDouble();
      _syncValue = value.toString();
    } else {
      // bad value!
      _syncValue = snapshotVal.toString();
    }
  }

  void _settingsSnapshot(DocumentSnapshot incomingValue) {
    final snapshotVal = incomingValue.data();

    _stats = LightStats<double>.fromJson(snapshotVal as Map<String, dynamic>);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    _snapShotSub.cancel();
    _settingsSub.cancel();
  }
}

class ValueUserModel extends UserModel {
  ValueUserModel(super.user) {
    _userDoc = FirebaseFirestore.instance.doc('users/${_user.uid}');

    _snapShotSub =
        _userDoc.snapshots(includeMetadataChanges: true).listen(_docSnapshot);
  }

  static const _valueKey = 'value';

  double _value = _defaultValue;
  String __syncValue = '???';

  @override
  double get value => _value;
  @override
  String get syncValue => __syncValue;

  @override
  set value(double val) {
    if (val != _value) {
      _value = val;
      _userDoc.set({_valueKey: val});
      notifyListeners();
    }
  }

  set _syncValue(String val) {
    if (val != __syncValue) {
      __syncValue = val;
      notifyListeners();
    }
  }

  @override
  LightStats<double> get stats => throw UnimplementedError();

  late final DocumentReference _userDoc;
  late final StreamSubscription<DocumentSnapshot> _snapShotSub;

  String get uid => _user.uid;

  void _docSnapshot(DocumentSnapshot incomingValue) {
    final snapshotVal = incomingValue.data();

    if (snapshotVal case {_valueKey: num x}) {
      value = x.toDouble();
      _syncValue = value.toString();
    } else {
      _syncValue = snapshotVal.toString();
      print('Bad value! $snapshotVal');
    }
  }

  @override
  void dispose() {
    super.dispose();
    _snapShotSub.cancel();
  }
}

const _defaultValue = 5.0;
