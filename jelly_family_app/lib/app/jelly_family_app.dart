import 'package:flutter/material.dart';
import 'package:jelly_family_app/app/theme/app_theme.dart';
import 'package:jelly_family_app/features/auth/auth_gate.dart';

class JellyFamilyApp extends StatelessWidget {
  const JellyFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JellyFamily',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

