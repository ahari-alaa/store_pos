import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:store_pos/features/pos/presentation/utils/receipt_printer_service.dart';
import 'package:store_pos/features/settings/domain/entities/receipt_settings.dart';

class _FakePrinterAdapter implements ReceiptPrintingAdapter {
  _FakePrinterAdapter({
    required this.infoValue,
    this.printers = const [],
    this.directPrintResult = true,
  });

  final PrintingInfo infoValue;
  final List<Printer> printers;
  final bool directPrintResult;
  int directPrintCalls = 0;
  Printer? lastPrinter;

  @override
  Future<PrintingInfo> info() async => infoValue;

  @override
  Future<List<Printer>> listPrinters() async => printers;

  @override
  Future<bool> directPrintPdf({
    required Printer printer,
    required Uint8List bytes,
    required String jobName,
  }) async {
    directPrintCalls += 1;
    lastPrinter = printer;
    return directPrintResult;
  }
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('throws when no printer is configured', () async {
    const service = ReceiptPrinterService(adapter: _NoopAdapter(), isWeb: false);

    await expectLater(
      () => service.printReceiptPdf(
        bytes: bytes,
        settings: const ReceiptSettings(),
        jobName: 'job',
      ),
      throwsA(isA<ReceiptPrintException>()),
    );
  });

  test('prints selected printer and repeats for configured copy count', () async {
    final adapter = _FakePrinterAdapter(
      infoValue: const PrintingInfo(directPrint: true, canListPrinters: true),
      printers: const [
        Printer(url: 'printer://back', name: 'Back'),
        Printer(url: 'printer://front', name: 'Front Printer'),
      ],
    );
    final service = ReceiptPrinterService(adapter: adapter, isWeb: false);

    await service.printReceiptPdf(
      bytes: bytes,
      settings: const ReceiptSettings(
        printerName: 'Front Printer',
        receiptCopies: 2,
      ),
      jobName: 'receipt-1',
    );

    expect(adapter.directPrintCalls, 2);
    expect(adapter.lastPrinter?.url, 'printer://front');
  });

  test('throws on web because silent direct printing is unsupported', () async {
    final adapter = _FakePrinterAdapter(
      infoValue: const PrintingInfo(directPrint: true, canListPrinters: true),
      printers: const [Printer(url: 'printer://1', name: 'Front Printer')],
    );
    final service = ReceiptPrinterService(adapter: adapter, isWeb: true);

    await expectLater(
      () => service.printReceiptPdf(
        bytes: bytes,
        settings: const ReceiptSettings(printerName: 'Front Printer'),
        jobName: 'job',
      ),
      throwsA(isA<ReceiptPrintException>()),
    );
  });

  test('throws when printer reports failure', () async {
    final adapter = _FakePrinterAdapter(
      infoValue: const PrintingInfo(directPrint: true, canListPrinters: true),
      printers: const [Printer(url: 'printer://1', name: 'Front Printer')],
      directPrintResult: false,
    );
    final service = ReceiptPrinterService(adapter: adapter, isWeb: false);

    await expectLater(
      () => service.printReceiptPdf(
        bytes: bytes,
        settings: const ReceiptSettings(printerName: 'Front Printer'),
        jobName: 'job',
      ),
      throwsA(isA<ReceiptPrintException>()),
    );
  });
}

class _NoopAdapter implements ReceiptPrintingAdapter {
  const _NoopAdapter();

  @override
  Future<bool> directPrintPdf({
    required Printer printer,
    required Uint8List bytes,
    required String jobName,
  }) async {
    return true;
  }

  @override
  Future<PrintingInfo> info() async => const PrintingInfo();

  @override
  Future<List<Printer>> listPrinters() async => const [];
}
