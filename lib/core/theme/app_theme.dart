import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand colors ────────────────────────────────────────────────────
  static const green        = Color(0xFF25D366);
  static const greenDark    = Color(0xFF1DAE57);
  static const greenSent    = Color(0xFF005C4B); // sent message bubble
  static const greenSentAlt = Color(0xFF00473B);

  // ── Dark theme surfaces (WhatsApp-style) ────────────────────────────
  static const bg           = Color(0xFF0A0E1A); // main background
  static const surface      = Color(0xFF121B22); // scaffold
  static const card         = Color(0xFF1F2C34); // cards
  static const input        = Color(0xFF1A2332); // input fields
  static const border       = Color(0xFF2A3942);
  static const appBar       = Color(0xFF1F2C34);

  // ── Text ────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF8696A0);

  // ── Light theme ─────────────────────────────────────────────────────
  static const lightBg      = Color(0xFFF0F2F5);
  static const lightCard    = Color(0xFFFFFFFF);
  static const lightInput   = Color(0xFFF7F8FA);
  static const lightBorder  = Color(0xFFE2E8F0);
  static const lightText    = Color(0xFF111B21);
  static const lightSubtext = Color(0xFF667781);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      colorScheme: const ColorScheme.light(
        primary: green,
        secondary: greenDark,
        surface: lightCard,
        onPrimary: Colors.white,
        onSurface: lightText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: lightText, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: green,
        unselectedItemColor: lightSubtext,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        elevation: 8,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: green,
        unselectedLabelColor: lightSubtext,
        indicatorColor: green,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: green, width: 2),
        ),
        hintStyle: const TextStyle(color: lightSubtext),
        prefixIconColor: lightSubtext,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: const CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.dark(
        primary: green,
        secondary: greenDark,
        surface: card,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: appBar,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: appBar,
        selectedItemColor: green,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        elevation: 8,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: green,
        unselectedLabelColor: textSecondary,
        indicatorColor: green,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: green, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
    );
  }

  // Legacy aliases for screens that reference the old names
  static const primaryTeal     = green;
  static const primaryTealDark = green;
  static const darkBackground  = surface;
  static const cardDark        = card;
  static const inputDark       = input;
  static const legacyLightText = textPrimary;
  static const greyTextDark    = textSecondary;
}
