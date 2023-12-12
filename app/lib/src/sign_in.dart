import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'routes.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: FirebaseAuth.instance.signInAnonymously(),
        builder: (ctx, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.done:
              if (snapshot.hasData) {
                return Center(
                  child: FloatingActionButton(
                    onPressed: () => const HomeRoute().go(ctx),
                    child: const Icon(Icons.home),
                  ),
                );
              }

              return ErrorWidget(
                'done? ${snapshot.hasData} - ${snapshot.error}',
              );
            case ConnectionState.waiting:
              return const Center(
                child: Icon(Icons.timelapse),
              );
            default:
              print(
                  'sign_in widget: no support for ${snapshot.connectionState}');
              return ErrorWidget('no support for ${snapshot.connectionState}');
          }
        },
      );
}
