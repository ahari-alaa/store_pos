import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_locale.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../domain/entities/receipt_settings.dart';
import '../providers/receipt_settings_provider.dart';

/// App Settings screen: Langue, Apparence, then the existing
/// "Application" (Receipt & Printer) settings — matching the section
/// order from the spec. Other settings categories (Users, Store,
/// Database, Sync, ...) aren't implemented anywhere in this project yet,
/// so this screen still doesn't invent UI for features that don't exist.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LanguageCard(),
                SizedBox(height: 20),
                _AppearanceCard(),
                SizedBox(height: 20),
                _ApplicationSectionLabel(),
                SizedBox(height: 12),
                _ReceiptPrinterSettingsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptPrinterSettingsCard extends ConsumerStatefulWidget {
  const _ReceiptPrinterSettingsCard();

  @override
  ConsumerState<_ReceiptPrinterSettingsCard> createState() => _ReceiptPrinterSettingsCardState();
}

class _ReceiptPrinterSettingsCardState extends ConsumerState<_ReceiptPrinterSettingsCard> {
  late final TextEditingController _printerName;
  late final TextEditingController _storeName;
  late final TextEditingController _storeAddress;
  late final TextEditingController _storePhone;
  late final TextEditingController _receiptHeader;
  late final TextEditingController _footerMessage;

  // Settings load asynchronously from secure storage (see
  // ReceiptSettingsNotifier._load). If that finishes after this widget's
  // initState already seeded the controllers with the temporary defaults,
  // this listener pushes the real persisted values in exactly once — it
  // never overwrites text the cashier is actively editing afterwards.
  bool _syncedFromStorage = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(receiptSettingsProvider);
    _printerName = TextEditingController(text: settings.printerName);
    _storeName = TextEditingController(text: settings.storeName);
    _storeAddress = TextEditingController(text: settings.storeAddress);
    _storePhone = TextEditingController(text: settings.storePhone);
    _receiptHeader = TextEditingController(text: settings.receiptHeader);
    _footerMessage = TextEditingController(text: settings.footerMessage);
  }

  @override
  void dispose() {
    _printerName.dispose();
    _storeName.dispose();
    _storeAddress.dispose();
    _storePhone.dispose();
    _receiptHeader.dispose();
    _footerMessage.dispose();
    super.dispose();
  }

  void _updateSettings(ReceiptSettings Function(ReceiptSettings current) updater) {
    ref.read(receiptSettingsProvider.notifier).update(updater);
  }

  Future<void> _saveAndConfirm() async {
    // Field-level onChanged handlers already persist as the cashier types
    // (see below), so this button is mainly a clear, explicit confirmation
    // for the "did my changes actually save?" moment — it re-flushes the
    // current text-field values into settings just in case, then confirms.
    _updateSettings((s) => s.copyWith(
          printerName: _printerName.text.trim(),
          storeName: _storeName.text.trim().isEmpty ? s.storeName : _storeName.text.trim(),
          storeAddress: _storeAddress.text.trim(),
          storePhone: _storePhone.text.trim(),
          receiptHeader: _receiptHeader.text.trim(),
          footerMessage: _footerMessage.text.trim(),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt & printer settings saved.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    await ref.read(receiptSettingsProvider.notifier).resetToDefaults();
    final defaults = ReceiptSettings.defaults;
    setState(() {
      _printerName.text = defaults.printerName;
      _storeName.text = defaults.storeName;
      _storeAddress.text = defaults.storeAddress;
      _storePhone.text = defaults.storePhone;
      _receiptHeader.text = defaults.receiptHeader;
      _footerMessage.text = defaults.footerMessage;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receipt & printer settings reset to defaults.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(receiptSettingsProvider);

    ref.listen<ReceiptSettings>(receiptSettingsProvider, (previous, next) {
      if (_syncedFromStorage) return;
      final notifier = ref.read(receiptSettingsProvider.notifier);
      if (!notifier.isLoaded) return;
      _syncedFromStorage = true;
      _printerName.text = next.printerName;
      _storeName.text = next.storeName;
      _storeAddress.text = next.storeAddress;
      _storePhone.text = next.storePhone;
      _receiptHeader.text = next.receiptHeader;
      _footerMessage.text = next.footerMessage;
    });

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Receipt & Printer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Controls what appears on every printed/shared receipt. The POS '
            'screen only uses these values — cashiers never configure this '
            'mid-sale.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 24),

          const _SectionLabel('Printer'),
          const SizedBox(height: 8),
          _LabeledField(
            controller: _printerName,
            label: 'Printer',
            hint: 'e.g. Front counter printer',
            onChanged: (v) => _updateSettings((s) => s.copyWith(printerName: v)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Informational label only — when printing, the OS print dialog '
            'still lets you pick any printer connected to this device.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 18),

          const _SectionLabel('Paper size'),
          const SizedBox(height: 8),
          SegmentedButton<ReceiptPaperSize>(
            segments: ReceiptPaperSize.values
                .map((size) => ButtonSegment(value: size, label: Text(size.label)))
                .toList(),
            selected: {settings.paperSize},
            onSelectionChanged: (selection) {
              _updateSettings((s) => s.copyWith(paperSize: selection.first));
            },
          ),
          const SizedBox(height: 22),

          const _SectionLabel('Store information'),
          const SizedBox(height: 8),
          _LabeledField(
            controller: _storeName,
            label: 'Store name',
            onChanged: (v) => _updateSettings((s) => s.copyWith(storeName: v)),
          ),
          const SizedBox(height: 10),
          _LabeledField(
            controller: _storeAddress,
            label: 'Store address',
            onChanged: (v) => _updateSettings((s) => s.copyWith(storeAddress: v)),
          ),
          const SizedBox(height: 10),
          _LabeledField(
            controller: _storePhone,
            label: 'Phone',
            onChanged: (v) => _updateSettings((s) => s.copyWith(storePhone: v)),
          ),
          const SizedBox(height: 22),

          const _SectionLabel('Receipt text'),
          const SizedBox(height: 8),
          _LabeledField(
            controller: _receiptHeader,
            label: 'Receipt header',
            hint: 'Optional line shown under the store name',
            onChanged: (v) => _updateSettings((s) => s.copyWith(receiptHeader: v)),
          ),
          const SizedBox(height: 10),
          _LabeledField(
            controller: _footerMessage,
            label: 'Footer message',
            onChanged: (v) => _updateSettings((s) => s.copyWith(footerMessage: v)),
          ),
          const SizedBox(height: 22),

          const _SectionLabel('Receipt content'),
          const SizedBox(height: 4),
          _SettingSwitch(
            label: 'Show logo',
            value: settings.showLogo,
            onChanged: (v) => _updateSettings((s) => s.copyWith(showLogo: v)),
          ),
          _SettingSwitch(
            label: 'Show cashier',
            value: settings.showCashier,
            onChanged: (v) => _updateSettings((s) => s.copyWith(showCashier: v)),
          ),
          _SettingSwitch(
            label: 'Show date/time',
            value: settings.showDateTime,
            onChanged: (v) => _updateSettings((s) => s.copyWith(showDateTime: v)),
          ),
          _SettingSwitch(
            label: 'Show barcode/receipt number',
            value: settings.showReceiptNumber,
            onChanged: (v) => _updateSettings((s) => s.copyWith(showReceiptNumber: v)),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveAndConfirm,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _resetToDefaults,
                child: const Text('Reset to defaults'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String> onChanged;

  const _LabeledField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: onChanged,
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
        ],
      ),
    );
  }
}

/// "Langue" section — Français / العربية (spec §1/§3/§4). Switching here
/// updates [localeProvider], which flips the whole app's locale and RTL
/// layout immediately (see main.dart's MaterialApp.router).
class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return _SettingsSectionCard(
      icon: Icons.language_rounded,
      title: tr(ref, 'settings.language'),
      description: tr(ref, 'settings.language_desc'),
      child: Row(
        children: AppLocale.values.map((locale) {
          final selected = locale == current;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: OutlinedButton(
                onPressed: () => ref.read(localeProvider.notifier).setLocale(locale),
                style: OutlinedButton.styleFrom(
                  backgroundColor: selected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.10)
                      : null,
                  side: BorderSide(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerTheme.color ?? AppColors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  locale.nativeName,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// "Apparence" section — predefined themes + individual color pickers for
/// primary/secondary/accent/background/card/text (spec §3). Selecting a
/// preset or a custom color updates [themeProvider], which rebuilds the
/// whole app's ThemeData live (see AppTheme.build / main.dart).
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeProvider);

    return _SettingsSectionCard(
      icon: Icons.palette_outlined,
      title: tr(ref, 'settings.appearance'),
      description: tr(ref, 'settings.appearance_desc'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(ref, 'settings.theme_presets'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppPalettes.presets.map((preset) {
              final selected = preset.name == palette.name;
              return _ThemePresetSwatch(
                preset: preset,
                selected: selected,
                label: tr(ref, preset.name),
                onTap: () => ref.read(themeProvider.notifier).selectPreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          _ColorRow(
            label: tr(ref, 'settings.primary_color'),
            color: palette.primary,
            onChanged: (c) => ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(primary: c)),
          ),
          _ColorRow(
            label: tr(ref, 'settings.secondary_color'),
            color: palette.secondary,
            onChanged: (c) =>
                ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(secondary: c)),
          ),
          _ColorRow(
            label: tr(ref, 'settings.accent_color'),
            color: palette.accent,
            onChanged: (c) => ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(accent: c)),
          ),
          _ColorRow(
            label: tr(ref, 'settings.background_color'),
            color: palette.background,
            onChanged: (c) =>
                ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(background: c)),
          ),
          _ColorRow(
            label: tr(ref, 'settings.card_color'),
            color: palette.card,
            onChanged: (c) => ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(card: c)),
          ),
          _ColorRow(
            label: tr(ref, 'settings.text_color'),
            color: palette.text,
            onChanged: (c) => ref.read(themeProvider.notifier).updateColor((p) => p.copyWith(text: c)),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.read(themeProvider.notifier).resetToDefault(),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(tr(ref, 'settings.reset_theme')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePresetSwatch extends StatelessWidget {
  final AppPalette preset;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _ThemePresetSwatch({
    required this.preset,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? preset.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          color: preset.background,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dot(preset.primary),
                const SizedBox(width: 4),
                _dot(preset.secondary),
                const SizedBox(width: 4),
                _dot(preset.accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: preset.text),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  const _ColorRow({required this.label, required this.color, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(initial: color),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
          ),
          InkWell(
            onTap: () => _pick(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple curated-swatch color picker — no third-party color-picker
/// dependency needed. Good enough for "pick a brand color" without
/// pulling in a new package this project doesn't already use.
class _ColorPickerDialog extends StatelessWidget {
  final Color initial;

  const _ColorPickerDialog({required this.initial});

  static const List<Color> _swatches = [
    Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0EA5E9), Color(0xFF06B6D4),
    Color(0xFF16A34A), Color(0xFF22C55E), Color(0xFF84CC16), Color(0xFF0D9488),
    Color(0xFFF59E0B), Color(0xFFEA580C), Color(0xFFDC2626), Color(0xFFEF4444),
    Color(0xFF7C3AED), Color(0xFFA855F7), Color(0xFFEC4899), Color(0xFFDB2777),
    Color(0xFF64748B), Color(0xFF334155), Color(0xFF0F172A), Color(0xFF1A1D1F),
    Color(0xFFFFFFFF), Color(0xFFF8FAFC), Color(0xFFF3F4F6), Color(0xFF111827),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Couleur / اللون'),
      content: SizedBox(
        width: 280,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _swatches.map((c) {
            final selected = c.value == initial.value;
            return InkWell(
              onTap: () => Navigator.of(context).pop(c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler / إلغاء'),
        ),
      ],
    );
  }
}

class _ApplicationSectionLabel extends ConsumerWidget {
  const _ApplicationSectionLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text(
      tr(ref, 'settings.application'),
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
    );
  }
}

/// Shared card chrome for the Langue/Apparence sections, matching the
/// existing Receipt & Printer card's look (icon + title + description).
class _SettingsSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
