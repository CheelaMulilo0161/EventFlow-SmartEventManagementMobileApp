import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_state.dart';
import 'home_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthState>(
      builder: (context, auth, _) {
        if (auth.initializing) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_activity, size: 56, color: Color(0xFF0B6B3A)),
                  SizedBox(height: 20),
                  CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }
        return auth.isLoggedIn ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
