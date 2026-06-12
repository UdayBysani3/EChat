import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized app configuration.
/// All sensitive values are loaded from the .env file at runtime.
class AppConfig {
  // ── Supabase ──
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // ── EmailJS ──
  static String get emailJsServiceId => dotenv.env['EMAILJS_SERVICE_ID'] ?? '';
  static String get emailJsTemplateId => dotenv.env['EMAILJS_TEMPLATE_ID'] ?? '';
  static String get emailJsPublicKey => dotenv.env['EMAILJS_PUBLIC_KEY'] ?? '';

  // ── ZEGOCLOUD ──
  static int get zegoAppId => int.tryParse(dotenv.env['ZEGO_APP_ID'] ?? '') ?? 0;
  static String get zegoAppSign => dotenv.env['ZEGO_APP_SIGN'] ?? '';
}

class SupabaseConfig {
  static String get url => AppConfig.supabaseUrl;
  static String get publishableKey => AppConfig.supabaseAnonKey;
}
