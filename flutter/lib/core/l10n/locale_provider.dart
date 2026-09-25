import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_locale.dart';
import 'locale_storage.dart';
import 'translations.dart';

/// Holds the current app language for the whole app, loaded once from
/// on-device storage at startup (mirrors ReceiptSettingsNotifier's
/// pattern in settings/presentation/providers/receipt_settings_provider.dart).
class LocaleNotifier extends StateNotifier<AppLocale> {
  LocaleNotifier() : super(AppLocale.fr) {
    _load();
  }

  Future<void> _load() async {
    state = await LocaleStorage.instance.read();
  }

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    await LocaleStorage.instance.write(locale);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLocale>((ref) {
  return LocaleNotifier();
});

/// Shorthand used by every migrated widget: `tr(ref, 'nav.dashboard')`.
/// Kept as a free function (rather than a BuildContext extension) so it
/// works the same in both `ConsumerWidget.build` and
/// `ConsumerState.build`, the two places every screen in this app is
/// already written against.
String tr(WidgetRef ref, String key) => Translations.t(ref.watch(localeProvider), key);

/// Same lookup as [tr], but using `ref.read` instead of `ref.watch`.
///
/// [tr] subscribes the calling widget to [localeProvider], which is right
/// inside `build` and wrong anywhere else: Riverpod asserts if `watch` is
/// called from an event handler or an async callback, so `tr(ref, …)` in
/// an `onPressed` or in a `catch` block throws at runtime rather than
/// failing to compile. Use [trRead] for strings produced outside build —
/// toast messages, confirmation dialog copy, error text.
String trRead(WidgetRef ref, String key) =>
    Translations.t(ref.read(localeProvider), key);
