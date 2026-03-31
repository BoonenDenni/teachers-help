import 'package:flutter/material.dart';

import 'router.dart';

class TeachersHelpApp extends StatelessWidget {
  const TeachersHelpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lerarenhulp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6CF6)),
        useMaterial3: true,
      ),
      routerConfig: teachersHelpRouter,
    );
  }
}

