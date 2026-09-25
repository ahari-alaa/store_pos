import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_palette.dart';
import 'theme_storage.dart';

/// Holds the app's current color palette (Settings -> Apparence),
/// loaded once from on-device storage at startup, mirroring
/// `ReceiptSettingsNotifier`'s pattern.
class ThemeNotifier extends StateNotifier<AppPalette> {
  ThemeNotifier() : super(AppPalettes.defaultPalette) {
    _load();
  }

  Future<void> _load() async {
    final saved = await ThemeStorage.instance.read();
    if (saved != null) state = saved;
  }

  Future<void> selectPreset(AppPalette preset) async {
    state = preset;
    await ThemeStorage.instance.write(preset);
  }

  /// Used by the individual color swatches in Settings -> Apparence —
  /// picking a custom color always keeps the palette's current name so
  /// the UI can show "Personnalisé" instead of falsely claiming the
  /// customized result is still e.g. "Bleu".
  Future<void> updateColor(AppPalette Function(AppPalette current) updater) async {
    final next = updater(state).copyWith(name: 'theme.custom');
    state = next;
    await ThemeStorage.instance.write(next);
  }

  Future<void> resetToDefault() async {
    state = AppPalettes.defaultPalette;
    await ThemeStorage.instance.write(AppPalettes.defaultPalette);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppPalette>((ref) {
  return ThemeNotifier();
});
