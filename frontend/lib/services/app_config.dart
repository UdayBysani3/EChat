import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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

  // ── Backend ──
  static String get backendUrl {
    final configured = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    if (!kIsWeb && Platform.isAndroid) {
      return configured
          .replaceAll('localhost', '10.0.2.2')
          .replaceAll('127.0.0.1', '10.0.2.2');
    }
    return configured;
  }

  // ── Message Encryption ──
  static String get messageEncryptionSecret =>
      dotenv.env['MESSAGE_ENCRYPTION_SECRET'] ?? 'default_echat_secure_secret_key_32_chars';
}

class SupabaseConfig {
  static String get url => AppConfig.supabaseUrl;
  static String get publishableKey => AppConfig.supabaseAnonKey;
}

