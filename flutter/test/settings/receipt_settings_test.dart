import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/settings/domain/entities/receipt_settings.dart';

void main() {
  group('ReceiptSettings', () {
    test('serializes and deserializes new printer configuration fields', () {
      const settings = ReceiptSettings(
        printerName: 'Front Printer',
        connectionType: ReceiptPrinterConnectionType.system,
        printerIdentifier: 'ipp://front-printer',
        receiptCopies: 3,
        autoPrintEnabled: true,
      );

      final restored = ReceiptSettings.fromJson(settings.toJson());
      expect(restored.printerName, settings.printerName);
      expect(restored.connectionType, settings.connectionType);
      expect(restored.printerIdentifier, settings.printerIdentifier);
      expect(restored.receiptCopies, 3);
      expect(restored.autoPrintEnabled, isTrue);
    });

    test('falls back to defaults for missing new fields', () {
      final restored = ReceiptSettings.fromJson({
        'printer_name': 'Legacy printer',
        'paper_size': 'mm80',
      });

      expect(restored.printerName, 'Legacy printer');
      expect(restored.connectionType, ReceiptPrinterConnectionType.system);
      expect(restored.printerIdentifier, isEmpty);
      expect(restored.receiptCopies, 1);
      expect(restored.autoPrintEnabled, isFalse);
    });

    test('clamps receipt copies to valid range', () {
      final restored = ReceiptSettings.fromJson({
        'receipt_copies': 999,
      });
      expect(restored.receiptCopies, 10);
    });
  });
}
