import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite/auth_controller.dart';
import 'teacher_dashboard_screen.dart';
import 'teacher_login_screen.dart';

class TeacherGate extends ConsumerWidget {
  const TeacherGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      data: (user) => user == null ? const TeacherLoginScreen() : TeacherDashboardScreen(userId: user.$id),
      error: (e, _) => Scaffold(body: Center(child: Text('Authenticatiefout: $e'))),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

