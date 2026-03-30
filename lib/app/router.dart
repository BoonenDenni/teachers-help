import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/student/student_home_screen.dart';
import '../features/teacher/teacher_home_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) {
          return const LoginScreen();
        },
      ),
      GoRoute(
        path: '/teacher',
        builder: (BuildContext context, GoRouterState state) {
          return const TeacherHomeScreen();
        },
      ),
      GoRoute(
        path: '/class/:publicToken',
        builder: (BuildContext context, GoRouterState state) {
          final String publicToken = state.pathParameters['publicToken']!;
          return StudentHomeScreen(publicToken: publicToken);
        },
      ),
    ],
  );
}

