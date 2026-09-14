import 'package:flutter/material.dart';

/// Paleta institucional UniNorte
class UniNorteColors {
  UniNorteColors._();

  static const Color azulMarino = Color(0xFF0A192F);
  static const Color azulMarinoClaro = Color(0xFF112240);
  static const Color dorado = Color(0xFFE6A100);
  static const Color doradoClaro = Color(0xFFF2C14E);

  static const Color fondoClaro = Color(0xFFF5F5F7);
  static const Color superficie = Color(0xFFFFFFFF);

  static const Color textoPrimario = Color(0xFF0A192F);
  static const Color textoSecundario = Color(0xFF5A6B87);

  static const Color exito = Color(0xFF2E7D32);
  static const Color error = Color(0xFFB3261E);
  static const Color advertencia = Color(0xFFE6A100);
}

class UniNorteTheme {
  UniNorteTheme._();

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: UniNorteColors.azulMarino,
      primary: UniNorteColors.azulMarino,
      secondary: UniNorteColors.dorado,
      surface: UniNorteColors.superficie,
      error: UniNorteColors.error,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: UniNorteColors.fondoClaro,
      fontFamily: 'Roboto',

      appBarTheme: const AppBarTheme(
        backgroundColor: UniNorteColors.azulMarino,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: UniNorteColors.textoPrimario,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
        headlineMedium: TextStyle(
          color: UniNorteColors.textoPrimario,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        titleLarge: TextStyle(
          color: UniNorteColors.textoPrimario,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        bodyLarge: TextStyle(
          color: UniNorteColors.textoPrimario,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: UniNorteColors.textoSecundario,
          fontSize: 14,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: UniNorteColors.dorado,
          foregroundColor: UniNorteColors.azulMarino,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: UniNorteColors.azulMarino,
          side: const BorderSide(color: UniNorteColors.azulMarino, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: UniNorteColors.dorado,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: UniNorteColors.superficie,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: UniNorteColors.dorado, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: UniNorteColors.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: UniNorteColors.textoSecundario),
      ),

      cardTheme: CardThemeData(
        color: UniNorteColors.superficie,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: UniNorteColors.azulMarino.withValues(alpha: 0.08),
        labelStyle: const TextStyle(
          color: UniNorteColors.azulMarino,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
      ),
    );
  }
}