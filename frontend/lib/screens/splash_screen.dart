import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Wait for the animation to look nice
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final supabaseService = ref.read(supabaseServiceProvider);
    if (supabaseService.isAuthenticated) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ObsidianMintColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: ObsidianMintColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ObsidianMintColors.primary,
                      width: 2,
                    ),
                    boxShadow: [ObsidianMintColors.emeraldGlow],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                )
                .animate()
                .fade(duration: 800.ms)
                .scale(
                  delay: 200.ms,
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 24),
            Text(
                  'EChat',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: ObsidianMintColors.primary,
                    letterSpacing: 2.0,
                  ),
                )
                .animate()
                .fade(delay: 500.ms, duration: 800.ms)
                .slideY(begin: 0.2, end: 0, curve: Curves.easeInOut),
            const SizedBox(height: 8),
            Text(
              'Secure. Elegant. Email-First.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ObsidianMintColors.textSecondary,
              ),
            ).animate().fade(delay: 1000.ms, duration: 800.ms),
          ],
        ),
      ),
    );
  }
}
