import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'current_user_notifier.dart';
import 'routes.dart';
import 'user_widget.dart';

class HomeWidget extends StatelessWidget {
  const HomeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final signInState = CurrentUserWidget.of(context).signInState;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Top Bug🐞'),
      ),
      body: signInState == AppSignInState.signedIn
          ? UserWidget(user: CurrentUserWidget.of(context).currentUser!)
          : Text('Please login! ($signInState)'),
      floatingActionButton: _authButton(context),
    );
  }

  Widget _authButton(BuildContext context) =>
      switch (CurrentUserWidget.of(context).signInState) {
        AppSignInState.unknown => FloatingActionButton(
            onPressed: () => const SignInRoute().go(context),
            tooltip: 'Sign in (maybe?)',
            child: const Icon(Icons.login),
          ),
        AppSignInState.signedIn => FloatingActionButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            tooltip: 'Sign out',
            child: const Icon(Icons.logout),
          ),
        AppSignInState.signedOut => FloatingActionButton(
            onPressed: () => const SignInRoute().go(context),
            tooltip: 'Sign in',
            child: const Icon(Icons.login),
          ),
      };
}
