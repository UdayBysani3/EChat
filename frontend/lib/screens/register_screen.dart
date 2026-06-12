import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  Uint8List? _profileImageBytes;
  String? _selectedPresetUrl;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  final List<String> _avatarPresets = [
    'https://api.dicebear.com/7.x/adventurer/png?seed=Felix',
    'https://api.dicebear.com/7.x/adventurer/png?seed=Aneka',
    'https://api.dicebear.com/7.x/adventurer/png?seed=Jack',
    'https://api.dicebear.com/7.x/adventurer/png?seed=Molly',
    'https://api.dicebear.com/7.x/adventurer/png?seed=Buddy',
    'https://api.dicebear.com/7.x/adventurer/png?seed=Lucky',
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 60,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _profileImageBytes = bytes;
          _selectedPresetUrl = null; // Clear preset selection
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking profile image: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  void _showProfileImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianMintColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: ObsidianMintColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Select Profile Picture',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ObsidianMintColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSourceItem(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: ObsidianMintColors.primary,
                      onTap: () {
                        Navigator.pop(context);
                        _pickProfileImage(ImageSource.camera);
                      },
                    ),
                    _buildSourceItem(
                      icon: Icons.image_rounded,
                      label: 'Gallery',
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _pickProfileImage(ImageSource.gallery);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Or Choose an Avatar Preset',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ObsidianMintColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarPresets.length,
                    itemBuilder: (context, index) {
                      final url = _avatarPresets[index];
                      final isSelected = _selectedPresetUrl == url;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedPresetUrl = url;
                            _profileImageBytes = null;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? ObsidianMintColors.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: ObsidianMintColors.surfaceElevated,
                            backgroundImage: NetworkImage(url),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: ObsidianMintColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final username = _usernameController.text.trim();

      final supabaseService = ref.read(supabaseServiceProvider);
      
      // Check if email already registered
      final emailExists = await supabaseService.checkEmailExists(email);
      if (emailExists) {
        throw Exception('An account with this email already exists.');
      }

      // Generate OTP
      final otpCode = supabaseService.generateOTP();

      // Send OTP via EmailJS
      await supabaseService.sendEmailOTP(
        email: email,
        otpCode: otpCode,
        subject: 'EChat - Confirm Your Email',
        toName: username,
      );

      if (mounted) {
        context.go(
          '/confirm-email?email=$email',
          extra: {
            'username': username,
            'email': email,
            'password': password,
            'profile_image_bytes': _profileImageBytes,
            'selected_preset_url': _selectedPresetUrl,
            'otp_code': otpCode,
          },
        );
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
          onPressed: () => context.pop(),
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
                  Icons.person_add_alt_1_outlined,
                  color: ObsidianMintColors.primary,
                  size: 64,
                ).animate().fade(duration: 500.ms).scale(curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ).animate().fade(delay: 200.ms, duration: 500.ms),
                const SizedBox(height: 8),
                Text(
                  'Join the secure email chat ecosystem.',
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
                
                // Profile Picture Picker
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _showProfileImageSourceSheet,
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: ObsidianMintColors.surfaceElevated,
                          backgroundImage: _profileImageBytes != null
                              ? MemoryImage(_profileImageBytes!)
                              : (_selectedPresetUrl != null
                                  ? NetworkImage(_selectedPresetUrl!) as ImageProvider
                                  : null),
                          child: (_profileImageBytes == null && _selectedPresetUrl == null)
                              ? Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 36,
                                  color: ObsidianMintColors.primary,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showProfileImageSourceSheet,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: ObsidianMintColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: ObsidianMintColors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fade(delay: 350.ms, duration: 500.ms),
                const SizedBox(height: 8),
                Text(
                  'Tap to select profile picture / preset avatar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ObsidianMintColors.textSecondary,
                    fontSize: 12,
                  ),
                ).animate().fade(delay: 350.ms, duration: 500.ms),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _usernameController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'johndoe',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Username is required';
                    }
                    if (value.trim().length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ).animate().fade(delay: 400.ms, duration: 500.ms),
                const SizedBox(height: 16),
                
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
                ).animate().fade(delay: 450.ms, duration: 500.ms),
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
                ).animate().fade(delay: 500.ms, duration: 500.ms),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: ObsidianMintColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ).animate().fade(delay: 550.ms, duration: 500.ms),
                const SizedBox(height: 24),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ObsidianMintColors.onPrimary,
                          ),
                        )
                      : const Text('Register'),
                ).animate().fade(delay: 600.ms, duration: 500.ms),
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: () {
                    context.pop();
                  },
                  child: const Text('Already have an account? Sign In'),
                ).animate().fade(delay: 650.ms, duration: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
