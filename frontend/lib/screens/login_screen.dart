import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      
      final supabaseService = ref.read(supabaseServiceProvider);
      
      // 1. Verify if the email is registered in public.users
      final emailExists = await supabaseService.checkEmailExists(email);
      if (!emailExists) {
        throw Exception("User doesn't exist");
      }

      // 2. Attempt login
      try {
        await supabaseService.signIn(
          email: email,
          password: password,
        );
      } on AuthException catch (authErr) {
        final errMsg = authErr.message.toLowerCase();
        if (errMsg.contains('invalid login credentials') ||
            errMsg.contains('invalid credentials') ||
            errMsg.contains('invalid password')) {
          throw Exception("Wrong password");
        } else {
          throw Exception(authErr.message);
        }
      }

      if (mounted) {
        context.go('/home');
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: ObsidianMintColors.primary,
                    size: 64,
                  ).animate().fade(duration: 500.ms).scale(curve: Curves.easeOutBack),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ).animate().fade(delay: 200.ms, duration: 500.ms),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your secure email workspace.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ).animate().fade(delay: 300.ms, duration: 500.ms),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: ObsidianMintColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ObsidianMintColors.error, width: 0.5),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: ObsidianMintColors.error),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ).animate().fade(delay: 400.ms, duration: 500.ms),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_open_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: ObsidianMintColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ).animate().fade(delay: 550.ms, duration: 500.ms),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ObsidianMintColors.onPrimary,
                            ),
                          )
                        : const Text('Sign In'),
                  ).animate().fade(delay: 700.ms, duration: 500.ms),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        context.push('/otp-auth');
                      },
                      child: const Text('Forgot Password?'),
                    ),
                  ).animate().fade(delay: 770.ms, duration: 500.ms),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      context.push('/register');
                    },
                    child: const Text("Don't have an account? Register"),
                  ).animate().fade(delay: 850.ms, duration: 500.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
