import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'user_model.dart';

enum AppSignInState {
  signedIn,
  signedOut,
  unknown,
}

class CurrentUserWidget extends InheritedNotifier<UserListenable> {
  CurrentUserWidget({
    super.key,
    required super.child,
    required UserListenable super.notifier,
  });

  UserModel? get currentUser => notifier!.value;

  AppSignInState get signInState => notifier!.signInState;

  @override
  bool updateShouldNotify(covariant CurrentUserWidget oldWidget) =>
      oldWidget.currentUser != currentUser;

  static CurrentUserWidget of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<CurrentUserWidget>();
    assert(result != null, 'No FrogColor found in context');
    return result!;
  }
}

class UserListenable
    with ChangeNotifier
    implements ValueListenable<UserModel?> {
  UserListenable({required FirebaseAuth auth}) : _auth = auth {
    _userChangesSub = _auth.userChanges().listen(_setValue);
  }

  late final StreamSubscription<User?> _userChangesSub;

  final FirebaseAuth _auth;

  @override
  UserModel? get value => _value;
  UserModel? _value;

  AppSignInState _signInState = AppSignInState.unknown;

  AppSignInState get signInState => _signInState;

  void _setValue(User? newValue) {
    final current = _value;

    if (current == null) {
      if (newValue == null) {
        _signInState = AppSignInState.signedOut;
        return;
      }
    } else {
      if (newValue == null) {
        _signInState = AppSignInState.signedOut;
        return;
      } else if (current.sameUser(newValue)) {
        return;
      }
    }

    current?.dispose();

    _value = HttpPostUserModel(newValue);

    if (_value == null) {
      _signInState = AppSignInState.signedOut;
    } else {
      _signInState = AppSignInState.signedIn;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();

    _value?.dispose();

    _userChangesSub.cancel();
  }
}
