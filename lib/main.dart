import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/storage_service.dart';
import 'state/character_controller.dart';
import 'ui/app_theme.dart';
import 'ui/dashboard_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// True only when both keys were supplied via --dart-define-from-file.
bool isCloudSyncConfigured =
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isCloudSyncConfigured) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.signInAnonymously();
      }
    } catch (e) {
      debugPrint('Cloud sync unavailable: $e');
    }
  }
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
