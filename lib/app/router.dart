import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/student/student_home_screen.dart';
import '../features/teacher/teacher_home_screen.dart';

/// Single instance — do not create [GoRouter] inside [Widget.build] (breaks web URL sync).
final GoRouter teachersHelpRouter = GoRouter(
  initialLocation: '/login',
  debugLogDiagnostics: kDebugMode,
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      redirect: (BuildContext context, GoRouterState state) => '/login',
    ),
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
  errorBuilder: (BuildContext context, GoRouterState state) {
    return Scaffold(
      body: Center(
        child: Text('Onbekende route: ${state.uri}'),
      ),
    );
  },
);

