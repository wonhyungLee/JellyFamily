import 'package:flutter/material.dart';
import 'package:jelly_family_app/app/jelly_family_app.dart';
import 'package:jelly_family_app/config/supabase_config.dart';
import 'package:jelly_family_app/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  await NotificationService.configure();

  runApp(const JellyFamilyApp());
}
