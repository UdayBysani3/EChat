import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echat/services/chat_service.dart';

// Riverpod theme provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeModeNotifier(this._prefs) : super(ThemeMode.dark) {
    // Read theme mode from prefs, defaulting to ThemeMode.dark
    final themeString = _prefs.getString('theme_mode');
    if (themeString == 'light') {
      state = ThemeMode.light;
      ObsidianMintColors.setDark(false);
    } else {
      state = ThemeMode.dark;
      ObsidianMintColors.setDark(true);
    }
  }

  void toggleTheme() {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      ObsidianMintColors.setDark(false);
      _prefs.setString('theme_mode', 'light');
    } else {
      state = ThemeMode.dark;
      ObsidianMintColors.setDark(true);
      _prefs.setString('theme_mode', 'dark');
    }
  }
}

class ObsidianMintColors {
  static bool _isDark = true;
  
  static bool get isDark => _isDark;
  
  static void setDark(bool value) {
    _isDark = value;
  }

  static Color get background => _isDark ? const Color(0xFF111416) : const Color(0xFFF4F6F8);
  static Color get surface => _isDark ? const Color(0xFF1D2022) : const Color(0xFFFFFFFF);
  static Color get surfaceElevated => _isDark ? const Color(0xFF272A2C) : const Color(0xFFECEFF1);
  static Color get surfaceContainerLow => _isDark ? const Color(0xFF191C1E) : const Color(0xFFECEFF1);
  static Color get surfaceContainerLowest => _isDark ? const Color(0xFF0C0F11) : const Color(0xFFFFFFFF);
  
  static Color get primary => _isDark ? const Color(0xFF53DE9E) : const Color(0xFF00A36C); // Emerald Accent
  static Color get onPrimary => _isDark ? const Color(0xFF003822) : const Color(0xFFFFFFFF);
  static Color get primaryContainer => _isDark ? const Color(0xFF00B074) : const Color(0xFFD0F8E6);
  static Color get onPrimaryContainer => _isDark ? const Color(0xFF003A23) : const Color(0xFF000000);
  
  static Color get secondary => _isDark ? const Color(0xFFC2C7CC) : const Color(0xFF656F77);
  static Color get onSecondary => _isDark ? const Color(0xFF2C3135) : const Color(0xFFFFFFFF);
  
  static Color get textPrimary => _isDark ? const Color(0xFFE1E2E5) : const Color(0xFF1A1F23);
  static Color get textSecondary => _isDark ? const Color(0xFFBCCABF) : const Color(0xFF5A656E);
  
  static Color get outline => _isDark ? const Color(0xFF86948A) : const Color(0xFFB0BEC5);
  static Color get outlineVariant => _isDark ? const Color(0xFF3D4A41) : const Color(0xFFCFD8DC);
  
  static Color get error => _isDark ? const Color(0xFFEF4444) : const Color(0xFFD32F2F);
  static Color get onError => _isDark ? const Color(0xFF690005) : const Color(0xFFFFFFFF);
  
  // Custom glowing effect
  static BoxShadow get emeraldGlow => BoxShadow(
    color: primary.withValues(alpha: 0.2),
    blurRadius: 12,
    spreadRadius: 0,
    offset: const Offset(0, 4),
  );
}

class ObsidianMintTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF111416),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF53DE9E),
        onPrimary: Color(0xFF003822),
        secondary: Color(0xFFC2C7CC),
        onSecondary: Color(0xFF2C3135),
        surface: Color(0xFF1D2022),
        onSurface: Color(0xFFE1E2E5),
        error: Color(0xFFEF4444),
        onError: Color(0xFF690005),
      ),
      textTheme: GoogleFonts.figtreeTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.02,
            color: Color(0xFFE1E2E5),
          ),
          headlineMedium: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
            color: Color(0xFFE1E2E5),
          ),
          titleSmall: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE1E2E5),
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: Color(0xFFE1E2E5),
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Color(0xFFBCCABF),
          ),
          labelLarge: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
            color: Color(0xFFE1E2E5),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFFE1E2E5),
        ),
        iconTheme: IconThemeData(color: Color(0xFFE1E2E5)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1D2022),
        labelStyle: const TextStyle(color: Color(0xFFBCCABF)),
        hintStyle: const TextStyle(color: Color(0xFFBCCABF)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3D4A41), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF53DE9E), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF53DE9E),
          foregroundColor: const Color(0xFF003822),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF53DE9E),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1D2022),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3D4A41), width: 0.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111416),
        selectedItemColor: Color(0xFF53DE9E),
        unselectedItemColor: Color(0xFFBCCABF),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F6F8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF00A36C),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF656F77),
        onSecondary: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1A1F23),
        error: Color(0xFFD32F2F),
        onError: Color(0xFFFFFFFF),
      ),
      textTheme: GoogleFonts.figtreeTextTheme(
        ThemeData.light().textTheme.copyWith(
          displayLarge: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.02,
            color: Color(0xFF1A1F23),
          ),
          headlineMedium: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
            color: Color(0xFF1A1F23),
          ),
          titleSmall: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1F23),
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1F23),
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Color(0xFF5A656E),
          ),
          labelLarge: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
            color: Color(0xFF1A1F23),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A1F23),
        ),
        iconTheme: IconThemeData(color: Color(0xFF1A1F23)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        labelStyle: const TextStyle(color: Color(0xFF5A656E)),
        hintStyle: const TextStyle(color: Color(0xFF5A656E)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCFD8DC), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00A36C), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00A36C),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF00A36C),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFCFD8DC), width: 0.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: Color(0xFF00A36C),
        unselectedItemColor: Color(0xFF5A656E),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
