import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract class UserModel with ChangeNotifier {
  UserModel(this._user);

  final User _user;

  bool sameUser(User user) => user == _user;

  double get value;
  set value(double val);

  String get syncValue;
}

class ValueUserModel extends UserModel {
  ValueUserModel(super.user) {
    _userDoc = FirebaseFirestore.instance.doc('users/${_user.uid}');

    _snapShotSub =
        _userDoc.snapshots(includeMetadataChanges: true).listen(_docSnapshot);
  }

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

const _valueKey = 'value';
const _defaultValue = 5.0;
