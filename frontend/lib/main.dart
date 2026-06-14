import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_config.dart';
import 'config/theme.dart';
import 'config/router.dart';
import 'services/chat_service.dart';
import 'services/global_notification_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env
  await dotenv.load(fileName: '.env');

  // Initialize SharedPreferences
  final sharedPrefs = await SharedPreferences.getInstance();

  // Initialize Supabase Auth
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e) {
    debugPrint('Supabase Initialization Error: $e');
    // Note: During local design building, if credentials are placeholders, 
    // it will catch here and continue. We handle this grace period for developers.
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ],
      child: const EChatApp(),
    ),
  );
}

class EChatApp extends ConsumerWidget {
  const EChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'EChat',
      theme: ObsidianMintTheme.lightTheme,
      darkTheme: ObsidianMintTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        ref.watch(globalNotificationControllerProvider);
        return child!;
      },
    );
  }
}
