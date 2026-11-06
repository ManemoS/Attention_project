import 'package:flutter/material.dart';

/// The app's look: deep ink at night, warm paper by day.
///
/// Colours carry meaning across every screen, so they come straight from the colour scheme:
/// primary (amber) is focus and locked time, secondary (mint) is free time, tertiary (violet)
/// is lecture notes, and error (coral) is running over or recording.
class AppTheme {
  static const display = 'Space Grotesk';
  static const body = 'Manrope';

  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFB547),
    onPrimary: Color(0xFF2E1A00),
    primaryContainer: Color(0xFF4A3105),
    onPrimaryContainer: Color(0xFFFFDDA6),
    secondary: Color(0xFF62D6B2),
    onSecondary: Color(0xFF00281D),
    secondaryContainer: Color(0xFF0E3D30),
    onSecondaryContainer: Color(0xFFA9F2DA),
    tertiary: Color(0xFFADA8FF),
    onTertiary: Color(0xFF1D1A5C),
    tertiaryContainer: Color(0xFF2F2C72),
    onTertiaryContainer: Color(0xFFE2E0FF),
    error: Color(0xFFFF8070),
    onError: Color(0xFF3D0803),
    errorContainer: Color(0xFF55170F),
    onErrorContainer: Color(0xFFFFD5CE),
    surface: Color(0xFF0E1015),
    onSurface: Color(0xFFEDEEF2),
    onSurfaceVariant: Color(0xFFA2A8B5),
    surfaceDim: Color(0xFF0B0D11),
    surfaceBright: Color(0xFF2A2F3A),
    surfaceContainerLowest: Color(0xFF090A0E),
    surfaceContainerLow: Color(0xFF14171D),
    surfaceContainer: Color(0xFF191C24),
    surfaceContainerHigh: Color(0xFF21252E),
    surfaceContainerHighest: Color(0xFF2A2F3A),
    outline: Color(0xFF4A5160),
    outlineVariant: Color(0xFF262B35),
    inverseSurface: Color(0xFFEDEEF2),
    onInverseSurface: Color(0xFF16181D),
    inversePrimary: Color(0xFF8A5200),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF9A5800),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDFB0),
    onPrimaryContainer: Color(0xFF311C00),
    secondary: Color(0xFF00785C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFC4F0E0),
    onSecondaryContainer: Color(0xFF00281D),
    tertiary: Color(0xFF5450C8),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE4E2FF),
    onTertiaryContainer: Color(0xFF16124F),
    error: Color(0xFFC2362A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD4),
    onErrorContainer: Color(0xFF410100),
    surface: Color(0xFFF8F6F1),
    onSurface: Color(0xFF1A1C21),
    onSurfaceVariant: Color(0xFF5B606B),
    surfaceDim: Color(0xFFE4E0D7),
    surfaceBright: Color(0xFFFFFDF9),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F0E9),
    surfaceContainer: Color(0xFFEEEAE1),
    surfaceContainerHigh: Color(0xFFE8E4DA),
    surfaceContainerHighest: Color(0xFFE1DCD1),
    outline: Color(0xFFB9B3A6),
    outlineVariant: Color(0xFFE2DDD2),
    inverseSurface: Color(0xFF2B2D33),
    onInverseSurface: Color(0xFFF2F1EE),
    inversePrimary: Color(0xFFFFB547),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static ThemeData get dark => _build(_dark);
  static ThemeData get light => _build(_light);

  static ThemeData _build(ColorScheme c) {
    final dark = c.brightness == Brightness.dark;
    final base = (dark ? Typography.material2021().white : Typography.material2021().black)
        .apply(fontFamily: body, bodyColor: c.onSurface, displayColor: c.onSurface);

    TextStyle? heading(TextStyle? s, double size, {double spacing = -0.5, FontWeight w = FontWeight.w600}) =>
        s?.copyWith(fontFamily: display, fontSize: size, fontWeight: w, letterSpacing: spacing, height: 1.1);

    final text = base.copyWith(
      displayLarge: heading(base.displayLarge, 64, spacing: -2.5),
      displayMedium: heading(base.displayMedium, 48, spacing: -1.8),
      displaySmall: heading(base.displaySmall, 36, spacing: -1.2),
      headlineLarge: heading(base.headlineLarge, 32, spacing: -1),
      headlineMedium: heading(base.headlineMedium, 28, spacing: -0.8),
      headlineSmall: heading(base.headlineSmall, 24, spacing: -0.5),
      titleLarge: heading(base.titleLarge, 21, spacing: -0.3),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: c.onSurfaceVariant, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.1),
    );

    final cardColor = dark ? c.surfaceContainerLow : c.surfaceContainerLowest;
    // Underline-style borders keep the floating label inside the filled field, not on its edge.
    final field = UnderlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    final buttonText = text.labelLarge?.copyWith(fontSize: 16);

    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      textTheme: text,
      fontFamily: body,
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: buttonShape,
          textStyle: buttonText,
          disabledBackgroundColor: c.onSurface.withValues(alpha: 0.08),
          disabledForegroundColor: c.onSurface.withValues(alpha: 0.38),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: c.outline),
          foregroundColor: c.onSurface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.onSurfaceVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        extendedTextStyle: buttonText,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? c.surfaceContainerHigh : c.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: field,
        enabledBorder: field,
        disabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: c.primary, width: 2)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: c.error, width: 1.5)),
        focusedErrorBorder: field.copyWith(borderSide: BorderSide(color: c.error, width: 2)),
        labelStyle: text.bodyLarge?.copyWith(color: c.onSurfaceVariant),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => text.bodyMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: states.contains(WidgetState.error)
                  ? c.error
                  : states.contains(WidgetState.focused)
                      ? c.primary
                      : c.onSurfaceVariant,
            )),
        hintStyle: text.bodyLarge?.copyWith(color: c.onSurfaceVariant.withValues(alpha: 0.7)),
        prefixIconColor: c.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: text.labelLarge,
          side: BorderSide(color: c.outlineVariant),
          selectedBackgroundColor: c.primaryContainer,
          selectedForegroundColor: c.onPrimaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 10,
        activeTrackColor: c.primary,
        inactiveTrackColor: c.surfaceContainerHighest,
        thumbColor: c.primary,
        overlayColor: c.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 0, pressedElevation: 0),
        trackShape: const RoundedRectSliderTrackShape(),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        valueIndicatorColor: c.inverseSurface,
        valueIndicatorTextStyle: text.labelLarge?.copyWith(color: c.onInverseSurface),
        showValueIndicator: ShowValueIndicator.always,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : c.outline,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        minVerticalPadding: 12,
        iconColor: c.onSurfaceVariant,
        titleTextStyle: text.titleMedium?.copyWith(fontSize: 16),
        subtitleTextStyle: text.bodySmall?.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceContainerHigh,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge?.copyWith(color: c.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: dark ? c.surfaceContainerLow : c.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelMedium?.copyWith(
              color: states.contains(WidgetState.selected) ? c.onSurface : c.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? c.onPrimaryContainer : c.onSurfaceVariant,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverseSurface, fontWeight: FontWeight.w600),
        actionTextColor: c.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: c.outline,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.inverseSurface, borderRadius: BorderRadius.circular(10)),
        textStyle: text.bodySmall?.copyWith(color: c.onInverseSurface, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: c.onSurfaceVariant,
        collapsedIconColor: c.onSurfaceVariant,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelLarge?.copyWith(color: c.onSurfaceVariant),
        dataTextStyle: tabular(text.bodyMedium),
      ),
    );
  }
}

/// Digits all the same width, so a ticking countdown doesn't wobble.
TextStyle? tabular(TextStyle? style) =>
    style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
