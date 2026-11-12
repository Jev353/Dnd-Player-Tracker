import 'package:flutter/material.dart';

import 'services/storage_service.dart';
import 'state/character_controller.dart';
import 'ui/app_theme.dart';
import 'ui/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = CharacterController(StorageService());
  await controller.load();
  runApp(DnDTrackerApp(controller: controller));
}

class DnDTrackerApp extends StatelessWidget {
  const DnDTrackerApp({super.key, required this.controller});

  final CharacterController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D&D Player Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DashboardScreen(ctrl: controller),
    );
  }
}

