import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'current_user_notifier.dart';
import 'routes.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final UserListenable _userListenable;

  @override
  void initState() {
    super.initState();
    _userListenable = UserListenable(auth: FirebaseAuth.instance);
  }

  @override
  void dispose() {
    super.dispose();
    _userListenable.dispose();
  }

  @override
  Widget build(BuildContext context) => CurrentUserWidget(
        notifier: _userListenable,
        child: MaterialApp.router(
          title: 'Fast & Slow',
          routerConfig: GoRouter(
            routes: $appRoutes,
            redirect: (BuildContext context, GoRouterState state) {
              if (CurrentUserWidget.of(context).signInState ==
                      AppSignInState.signedIn &&
                  state.matchedLocation == const SignInRoute().location) {
                return const HomeRoute().location;
              }
              return null;
            },
          ),
        ),
      );
}
