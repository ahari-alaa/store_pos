import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_locale.dart';
import 'core/l10n/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/keyboard_auto_show.dart';

void main() {
  runApp(const ProviderScope(child: StorePosApp()));
}

class StorePosApp extends ConsumerWidget {
  const StorePosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final palette = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    // Keying (palette, locale) forces every already-built screen to rebuild
    // from scratch when either changes, instead of only the widgets that
    // happen to watch these providers directly. That's what makes a
    // Settings -> Apparence color change (or a language switch) reach
    // screens built before this feature existed — they still read colors
    // from Theme.of(context)/static AppColors and text from hard-coded
    // French, but at least repaint with the fresh theme and re-mount with
    // the fresh locale instead of going stale.
    //
    // IMPORTANT: the key must sit *inside* MaterialApp.router, around only
    // the routed page content (the `child` the `builder` receives) — never
    // around MaterialApp.router itself. Keying the whole MaterialApp.router
    // tears down and recreates the Navigator/Overlay/WidgetsApp element tree
    // on every theme or locale change (including the very first one, since
    // both providers load their real value asynchronously right after the
    // first frame). If that swap happens while the mouse is hovering the
    // window, Flutter's MouseTracker ends up mid-update on render objects
    // that just got disposed underneath it, which throws
    // '!_debugDuringDeviceUpdate' / "Cannot hit test a render box with no
    // size" on every subsequent mouse move. Keying only the inner content
    // keeps the Navigator/Overlay (and MouseTracker's owner) stable across
    // theme/locale changes while still forcing legacy screens to rebuild.
    return MaterialApp.router(
      title: 'Store POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(palette),
      locale: locale.locale,
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => KeyboardAutoShow(
        child: KeyedSubtree(
          key: ValueKey('${palette.hashCode}-${locale.name}'),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
