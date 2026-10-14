// ignore: unnecessary_import -- needed on Flutter versions where material does not re-export CupertinoPageTransitionsBuilder.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme-aware palette — fixes light-mode text/box contrast.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.card,
    required this.cardElevated,
    required this.stroke,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.fab,
    required this.fabBorder,
    required this.neon,
    required this.danger,
    required this.success,
  });

  final Color bg;
  final Color card;
  final Color cardElevated;
  final Color stroke;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color fab;
  final Color fabBorder;
  final Color neon;
  final Color danger;
  final Color success;

  static const dark = AppPalette(
    bg: Color(0xFF001830),
    card: Color(0xFF000000),
    cardElevated: Color(0xFF050B14),
    stroke: Color(0xFF2A3F55),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B8C2),
    textMuted: Color(0xFF7A8794),
    fab: Color(0xFF003362),
    fabBorder: Color(0xFF4A7FA8),
    neon: Color(0xFF30E050),
    danger: Color(0xFFFF2D2D),
    success: Color(0xFF30E050),
  );

  static const light = AppPalette(
    bg: Color(0xFFF3F5F8),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFEEF2F6),
    stroke: Color(0xFFD5DCE5),
    textPrimary: Color(0xFF0B1A28),
    textSecondary: Color(0xFF5A6B7D),
    textMuted: Color(0xFF8A97A6),
    fab: Color(0xFF003362),
    fabBorder: Color(0xFF2F6F9F),
    neon: Color(0xFF1FA800),
    danger: Color(0xFFD32F2F),
    success: Color(0xFF1FA800),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  AppPalette copyWith({
    Color? bg,
    Color? card,
    Color? cardElevated,
    Color? stroke,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? fab,
    Color? fabBorder,
    Color? neon,
    Color? danger,
    Color? success,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      stroke: stroke ?? this.stroke,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      fab: fab ?? this.fab,
      fabBorder: fabBorder ?? this.fabBorder,
      neon: neon ?? this.neon,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      fab: Color.lerp(fab, other.fab, t)!,
      fabBorder: Color.lerp(fabBorder, other.fabBorder, t)!,
      neon: Color.lerp(neon, other.neon, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

/// Dark-default static aliases for places not yet migrated.
class AppColors {
  AppColors._();
  static const background = Color(0xFF001830);
  static const card = Color(0xFF000000);
  static const cardElevated = Color(0xFF050B14);
  static const stroke = Color(0xFF2A3F55);
  static const fab = Color(0xFF003362);
  static const fabBorder = Color(0xFF4A7FA8);
  static const neon = Color(0xFF30E050);
  static const danger = Color(0xFFFF2D2D);
  static const success = Color(0xFF30E050);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0B8C2);
  static const textMuted = Color(0xFF7A8794);
  static const surface = card;
  static const surfaceElevated = cardElevated;
  static const border = stroke;
  static const borderSoft = stroke;
  static const primary = fabBorder;
  static const primarySoft = Color(0x330088FF);
  static const gold = neon;
  static const goldSoft = Color(0x334BE000);
  static const accent = neon;
  static const accentSoft = Color(0x334BE000);
  static const successSoft = Color(0x334BE000);
  static const dangerSoft = Color(0x33FF2D2D);
  static const neonDim = Color(0xFF2F8F00);
  static const strokeStrong = Color(0xFF3D5A73);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? AppPalette.dark : AppPalette.light;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.fabBorder,
        onPrimary: Colors.white,
        secondary: p.neon,
        onSecondary: dark ? Colors.black : Colors.white,
        surface: p.card,
        onSurface: p.textPrimary,
        error: p.danger,
        onError: Colors.white,
      ),
      extensions: [p],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      textTheme: text,
      iconTheme: IconThemeData(color: p.textSecondary),
      primaryIconTheme: IconThemeData(color: p.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Client (Oct 10): sub-page titles are centered. Main pages
        // (tab headers, main Sell) opt out explicitly.
        centerTitle: true,
        iconTheme: IconThemeData(color: p.textSecondary),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
          fontSize: 17,
        ),
      ),
      cardColor: p.card,
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.cardElevated,
        hintStyle: TextStyle(color: p.textMuted),
        labelStyle: TextStyle(color: p.textSecondary),
        suffixIconColor: p.textSecondary,
        prefixIconColor: p.textSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.fabBorder, width: 1.4),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.cardElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.stroke),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: p.cardElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.stroke),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.stroke),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.cardElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.stroke),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.fab,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: p.stroke, thickness: 0.7, space: 0.7),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.cardElevated,
        contentTextStyle: TextStyle(color: p.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        barrierColor: const Color(0xB3000000),
        backgroundColor: p.cardElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        titleTextStyle: text.titleMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.stroke),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.cardElevated,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: const Color(0xB3000000),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return p.fabBorder;
          return p.stroke;
        }),
      ),
    );
  }
}
