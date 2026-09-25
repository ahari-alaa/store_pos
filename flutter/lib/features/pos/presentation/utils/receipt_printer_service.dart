import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../settings/domain/entities/receipt_settings.dart';

class ReceiptPrintException implements Exception {
  final String message;
  const ReceiptPrintException(this.message);

  @override
  String toString() => message;
}

abstract class ReceiptPrintingAdapter {
  Future<PrintingInfo> info();
  Future<List<Printer>> listPrinters();
  Future<bool> directPrintPdf({
    required Printer printer,
    required Uint8List bytes,
    required String jobName,
  });
}

class PrintingReceiptAdapter implements ReceiptPrintingAdapter {
  const PrintingReceiptAdapter();

  @override
  Future<PrintingInfo> info() => Printing.info();

  @override
  Future<List<Printer>> listPrinters() => Printing.listPrinters();

  @override
  Future<bool> directPrintPdf({
    required Printer printer,
    required Uint8List bytes,
    required String jobName,
  }) {
    return Future.value(
      Printing.directPrintPdf(
        printer: printer,
        name: jobName,
        onLayout: (_) async => bytes,
      ),
    );
  }
}

class ReceiptPrinterService {
  final ReceiptPrintingAdapter _adapter;
  final bool _isWeb;

  const ReceiptPrinterService({
    required ReceiptPrintingAdapter adapter,
    bool isWeb = kIsWeb,
  })  : _adapter = adapter,
        _isWeb = isWeb;

  bool get supportsSilentDirectPrint => !_isWeb;

  Future<void> printReceiptPdf({
    required Uint8List bytes,
    required ReceiptSettings settings,
    required String jobName,
  }) async {
    if (settings.printerName.trim().isEmpty &&
        settings.printerIdentifier.trim().isEmpty) {
      throw const ReceiptPrintException('No receipt printer configured.');
    }

    if (settings.connectionType != ReceiptPrinterConnectionType.system) {
      throw const ReceiptPrintException(
        'This printer type is not supported on this platform.',
      );
    }

    if (_isWeb) {
      throw const ReceiptPrintException(
        'Direct receipt printing is not supported in web browsers.',
      );
    }

    final info = await _adapter.info();
    if (!info.directPrint) {
      throw const ReceiptPrintException(
        'Direct receipt printing is not supported on this device.',
      );
    }

    final printer = await _resolvePrinter(settings, info);
    if (printer == null) {
      throw const ReceiptPrintException('Configured receipt printer was not found.');
    }

    for (var i = 0; i < settings.receiptCopies; i++) {
      final ok = await _adapter.directPrintPdf(
        printer: printer,
        bytes: bytes,
        jobName: settings.receiptCopies > 1 ? '$jobName (${i + 1}/${settings.receiptCopies})' : jobName,
      );
      if (!ok) {
        throw const ReceiptPrintException(
          'Receipt printer is unavailable. Please check the connection.',
        );
      }
    }
  }

  Future<Printer?> _resolvePrinter(
    ReceiptSettings settings,
    PrintingInfo info,
  ) async {
    if (info.canListPrinters) {
      final printers = await _adapter.listPrinters();
      if (printers.isEmpty) return null;
      final byIdentifier = _findByIdentifier(
        printers: printers,
        identifier: settings.printerIdentifier,
      );
      if (byIdentifier != null) return byIdentifier;
      final byName = _findByName(printers: printers, name: settings.printerName);
      if (byName != null) return byName;
      final defaultPrinter = printers.where((p) => p.isDefault).toList();
      if (defaultPrinter.isNotEmpty) return defaultPrinter.first;
      return null;
    }

    final identifier = settings.printerIdentifier.trim();
    if (identifier.isEmpty) {
      throw const ReceiptPrintException(
        'This platform cannot list printers. Set a printer identifier in Settings.',
      );
    }
    return Printer(url: identifier, name: settings.printerName.trim().isEmpty ? null : settings.printerName.trim());
  }

  Printer? _findByIdentifier({
    required List<Printer> printers,
    required String identifier,
  }) {
    final needle = identifier.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final printer in printers) {
      if (printer.url.trim().toLowerCase() == needle ||
          printer.name.trim().toLowerCase() == needle) {
        return printer;
      }
    }
    return null;
  }

  Printer? _findByName({
    required List<Printer> printers,
    required String name,
  }) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final printer in printers) {
      if (printer.name.trim().toLowerCase() == needle) {
        return printer;
      }
    }
    return null;
  }
}

final receiptPrinterServiceProvider = Provider<ReceiptPrinterService>((ref) {
  return const ReceiptPrinterService(adapter: PrintingReceiptAdapter());
});
