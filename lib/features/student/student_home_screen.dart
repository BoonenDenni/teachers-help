import 'package:flutter/material.dart';

import 'tab_picker_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key, required this.publicToken});

  final String publicToken;

  @override
  Widget build(BuildContext context) {
    return TabPickerScreen(publicToken: publicToken);
  }
}

