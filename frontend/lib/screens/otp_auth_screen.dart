import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

class OtpAuthScreen extends ConsumerStatefulWidget {
  const OtpAuthScreen({super.key});

  @override
  ConsumerState<OtpAuthScreen> createState() => _OtpAuthScreenState();
}

class _OtpAuthScreenState extends ConsumerState<OtpAuthScreen> {
  // OTP Reset Password
  final _resetEmailController = TextEditingController();
  final _resetOtpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _resetFormKey = GlobalKey<FormState>();
  bool _resetOtpSent = false;
  bool _isResetLoading = false;
  bool _obscureNewPassword = true;
  String? _resetError;

  @override
  void dispose() {
    _resetEmailController.dispose();
    _resetOtpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  // --- OTP Password Reset logic ---
  Future<void> _sendResetOtp() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() {
      _isResetLoading = true;
      _resetError = null;
    });

    try {
      final supabaseService = ref.read(supabaseServiceProvider);
      await supabaseService.sendPasswordResetOTP(_resetEmailController.text.trim());
      setState(() {
        _resetOtpSent = true;
      });
    } catch (e) {
      setState(() {
        _resetError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isResetLoading = false;
      });
    }
  }

  Future<void> _verifyResetOtp() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() {
      _isResetLoading = true;
      _resetError = null;
    });

    try {
      final supabaseService = ref.read(supabaseServiceProvider);
      await supabaseService.verifyOTPAndResetPassword(
        email: _resetEmailController.text.trim(),
        token: _resetOtpController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password updated successfully! Welcome.'),
            backgroundColor: ObsidianMintColors.primaryContainer,
          ),
        );
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _resetError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isResetLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Reset Password'),
      ),
      body: Container(
        decoration: BoxDecoration(color: ObsidianMintColors.background),
        child: _buildOtpResetTab(),
      ),
    );
  }

  // OTP Reset Tab Widget Builder
  Widget _buildOtpResetTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _resetFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.lock_reset_rounded,
              color: ObsidianMintColors.primary,
              size: 64,
            ).animate().fade(duration: 400.ms).scale(curve: Curves.easeOutBack),
            const SizedBox(height: 16),
            Text(
              'Reset Password via OTP',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your email to receive a recovery code, then enter your new password.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ObsidianMintColors.textSecondary),
            ),
            const SizedBox(height: 32),

            if (_resetError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ObsidianMintColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ObsidianMintColors.error, width: 0.5),
                ),
                child: Text(_resetError!, style: TextStyle(color: ObsidianMintColors.error)),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _resetEmailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_resetOtpSent,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Email is required';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            if (_resetOtpSent) ...[
              TextFormField(
                controller: _resetOtpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'One-Time Recovery Code',
                  hintText: '123456',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Recovery code is required';
                  if (value.length < 6) return 'Code must be 6 digits';
                  return null;
                },
              ).animate().fade(duration: 300.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNewPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: ObsidianMintColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'New password is required';
                  if (value.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ).animate().fade(duration: 300.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 24),
            ],

            ElevatedButton(
              onPressed: _isResetLoading
                  ? null
                  : (_resetOtpSent ? _verifyResetOtp : _sendResetOtp),
              child: _isResetLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianMintColors.onPrimary),
                    )
                  : Text(_resetOtpSent ? 'Verify & Reset Password' : 'Send Recovery Code'),
            ),

            if (_resetOtpSent) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isResetLoading ? null : () => setState(() => _resetOtpSent = false),
                child: const Text('Change email or resend code'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
