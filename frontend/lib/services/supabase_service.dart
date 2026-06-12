import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_config.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get current user
  User? get currentUser => _client.auth.currentUser;

  // Get current session
  Session? get currentSession => _client.auth.currentSession;

  // Check if authenticated
  bool get isAuthenticated => _client.auth.currentSession != null;

  // Listen to Auth State changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // Helper to send EmailJS OTP
  Future<void> sendEmailOTP({
    required String email,
    required String otpCode,
    required String subject,
    String? toName,
  }) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    
    // Format variables commonly used in EmailJS templates
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'origin': 'http://localhost',
      },
      body: jsonEncode({
        'service_id': AppConfig.emailJsServiceId,
        'template_id': AppConfig.emailJsTemplateId,
        'user_id': AppConfig.emailJsPublicKey,
        'template_params': {
          'to_email': email,
          'to_name': toName ?? email.split('@')[0],
          'otp_code': otpCode,
          'message': 'Your verification code is: $otpCode',
          'subject': subject,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send OTP email via EmailJS: ${response.body}');
    }
  }

  // Generate a random 6-digit OTP code
  String generateOTP() {
    final random = Random();
    final code = 100000 + random.nextInt(900000);
    return code.toString();
  }

  // Check if email exists in public.users table (bypasses RLS using RPC)
  Future<bool> checkEmailExists(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final res = await _client.rpc('check_user_email_exists', params: {
        'email_param': cleanEmail,
      });
      return res as bool? ?? false;
    } catch (_) {
      // Fallback in case RPC is not yet created or fails
      try {
        final res = await _client
            .from('users')
            .select('id')
            .ilike('email', cleanEmail)
            .maybeSingle();
        return res != null;
      } catch (_) {
        return false;
      }
    }
  }

  // Sign Up
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  // Sign In with Email/Password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      final userId = currentUser?.id;
      if (userId != null) {
        await _client.from('users').update({'status': 'offline'}).eq('id', userId);
      }
    } catch (_) {}
    await _client.auth.signOut();
  }

  // Trigger Sign In with OTP (Generates code, saves to DB, sends via EmailJS)
  Future<void> signInWithOtp(String email) async {
    final exists = await checkEmailExists(email);
    if (!exists) {
      throw Exception('No user found with this email address.');
    }

    final code = generateOTP();
    
    // Save OTP to DB securely via RPC
    await _client.rpc('store_login_otp', params: {
      'user_email': email,
      'otp_code': code,
    });

    // Send OTP via EmailJS
    await sendEmailOTP(
      email: email,
      otpCode: code,
      subject: 'EChat Passcode - Sign In',
    );
  }

  // Verify OTP for login/magiclink (Uses temp-password swap method)
  Future<AuthResponse> verifyLoginOTP(String email, String token) async {
    final tempPassword = 'temp_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    // 1. Swap user's password to a temp password using OTP check in DB
    final oldHash = await _client.rpc('set_temp_password_with_otp', params: {
      'user_email': email,
      'otp_code': token,
      'temp_password': tempPassword,
    });

    if (oldHash == null) {
      throw Exception('Failed to verify OTP code.');
    }

    try {
      // 2. Sign in with the temp password
      final authResponse = await signIn(email: email, password: tempPassword);

      // 3. Immediately restore the original password hash
      await _client.rpc('restore_password_hash', params: {
        'user_email': email,
        'old_hash': oldHash,
      });

      return authResponse;
    } catch (e) {
      // In case sign-in fails, restore password hash anyway
      await _client.rpc('restore_password_hash', params: {
        'user_email': email,
        'old_hash': oldHash,
      });
      rethrow;
    }
  }

  // Send Password Reset OTP
  Future<void> sendPasswordResetOTP(String email) async {
    final exists = await checkEmailExists(email);
    if (!exists) {
      throw Exception('No user found with this email address.');
    }

    final code = generateOTP();

    // Save OTP to DB
    await _client.rpc('store_login_otp', params: {
      'user_email': email,
      'otp_code': code,
    });

    // Send OTP via EmailJS
    await sendEmailOTP(
      email: email,
      otpCode: code,
      subject: 'EChat Passcode - Reset Password',
    );
  }

  // Verify OTP and Update Password
  Future<void> verifyOTPAndResetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    // Call DB RPC to check OTP and reset password securely
    await _client.rpc('reset_password_with_otp', params: {
      'user_email': email,
      'otp_code': token,
      'new_password': newPassword,
    });

    // Immediately sign the user in so they have a session
    await signIn(email: email, password: newPassword);
  }

  // Direct signup verification check for general verifyOTP references
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    required OtpType type,
  }) async {
    // If it's a signup type, it's checked inline in ConfirmEmailScreen, 
    // but we support fallback check here or mock it if already verified.
    return await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: type,
    );
  }
}

// Provides the SupabaseService instance
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// Provides stream of auth state changes
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseServiceProvider).authStateChanges;
});

// Provides current session status
final sessionProvider = Provider<Session?>((ref) {
  // We can watch authStateProvider to trigger rebuilds when state changes
  ref.watch(authStateProvider);
  return ref.read(supabaseServiceProvider).currentSession;
});
