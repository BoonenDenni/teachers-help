import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pops back to the [TeacherDashboardScreen] (first route in this navigator).
void popToTeacherClassList(BuildContext context) {
  Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
}

/// Main [LoginScreen]: student class code, ping, continue as teacher.
void goToTeachersHelpStart(BuildContext context) {
  context.go('/login');
}
