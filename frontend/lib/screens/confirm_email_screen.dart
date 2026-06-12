import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/chat_service.dart';
import '../config/theme.dart';

class ConfirmEmailScreen extends ConsumerStatefulWidget {
  final String email;
  final Map<String, dynamic>? registrationData;

  const ConfirmEmailScreen({
    super.key,
    required this.email,
    this.registrationData,
  });

  @override
  ConsumerState<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends ConsumerState<ConfirmEmailScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final code = _otpController.text.trim();
      
      if (widget.registrationData != null) {
        final correctCode = widget.registrationData!['otp_code'] as String?;
        if (correctCode != code) {
          throw Exception('Invalid verification code.');
        }

        // 1. Correct code! Now perform signup in Supabase
        final supabaseService = ref.read(supabaseServiceProvider);
        final authResponse = await supabaseService.signUp(
          email: widget.registrationData!['email'] as String,
          password: widget.registrationData!['password'] as String,
          data: {
            'username': widget.registrationData!['username'],
          },
        );

        final user = authResponse.user;
        if (user != null) {
          String? profileImageUrl;

          // Now that user is authenticated and logged in, we upload the profile pic
          final profileImageBytes = widget.registrationData!['profile_image_bytes'] as Uint8List?;
          final selectedPresetUrl = widget.registrationData!['selected_preset_url'] as String?;

          if (profileImageBytes != null) {
            final chatService = ref.read(chatServiceProvider);
            profileImageUrl = await chatService.uploadBytes(
              profileImageBytes,
              'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
          } else if (selectedPresetUrl != null) {
            profileImageUrl = selectedPresetUrl;
          }

          if (profileImageUrl != null) {
            // Update the user profile in public.users directly
            await Supabase.instance.client
                .from('users')
                .update({'profile_image': profileImageUrl})
                .eq('id', user.id);
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account created and verified! Welcome to EChat.'),
              backgroundColor: ObsidianMintColors.primaryContainer,
            ),
          );
          context.go('/home');
        }
      } else {
        // Fallback for direct Supabase OTP verification if no registrationData
        final supabaseService = ref.read(supabaseServiceProvider);
        await supabaseService.verifyOTP(
          email: widget.email,
          token: code,
          type: OtpType.signup,
        );
        if (mounted) {
          context.go('/home');
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  color: ObsidianMintColors.primary,
                  size: 72,
                ).animate().fade(duration: 500.ms).scale(curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                Text(
                  'Confirm Your Email',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ).animate().fade(delay: 200.ms, duration: 500.ms),
                const SizedBox(height: 12),
                Text(
                  'We have sent a verification code to:',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ObsidianMintColors.textSecondary,
                      ),
                ).animate().fade(delay: 300.ms, duration: 500.ms),
                const SizedBox(height: 8),
                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ObsidianMintColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ).animate().fade(delay: 400.ms, duration: 500.ms),
                const SizedBox(height: 24),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ObsidianMintColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ObsidianMintColors.error, width: 0.5),
                    ),
                    child: Text(_errorMessage!, style: TextStyle(color: ObsidianMintColors.error)),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    hintText: '123456',
                    prefixIcon: Icon(Icons.password_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Verification code is required';
                    if (value.length < 6) return 'Code must be 6 digits';
                    return null;
                  },
                ).animate().fade(delay: 450.ms, duration: 500.ms),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ObsidianMintColors.onPrimary,
                          ),
                        )
                      : const Text('Verify Account'),
                ).animate().fade(delay: 500.ms, duration: 500.ms),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Login'),
                ).animate().fade(delay: 550.ms, duration: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
