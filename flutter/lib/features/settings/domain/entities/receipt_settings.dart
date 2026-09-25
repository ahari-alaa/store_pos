import 'package:pdf/pdf.dart';

/// Paper width the receipt PDF is laid out for.
enum ReceiptPaperSize { mm58, mm80, a4 }

extension ReceiptPaperSizeX on ReceiptPaperSize {
  String get label {
    switch (this) {
      case ReceiptPaperSize.mm58:
        return '58mm (thermal)';
      case ReceiptPaperSize.mm80:
        return '80mm (thermal)';
      case ReceiptPaperSize.a4:
        return 'A4 / Letter';
    }
  }

  /// The [PdfPageFormat] used to build the receipt PDF for this size.
  PdfPageFormat get pdfPageFormat {
    switch (this) {
      case ReceiptPaperSize.mm58:
        return PdfPageFormat(
          58 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 6 * PdfPageFormat.mm,
        );
      case ReceiptPaperSize.mm80:
        return PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 10 * PdfPageFormat.mm,
        );
      case ReceiptPaperSize.a4:
        return PdfPageFormat.a4;
    }
  }

  static ReceiptPaperSize fromName(String? name) {
    return ReceiptPaperSize.values.firstWhere(
      (v) => v.name == name,
      orElse: () => ReceiptPaperSize.mm80,
    );
  }
}

enum ReceiptPrinterConnectionType { system, network, bluetooth, usb }

extension ReceiptPrinterConnectionTypeX on ReceiptPrinterConnectionType {
  String get label {
    switch (this) {
      case ReceiptPrinterConnectionType.system:
        return 'System printer';
      case ReceiptPrinterConnectionType.network:
        return 'Network printer';
      case ReceiptPrinterConnectionType.bluetooth:
        return 'Bluetooth printer';
      case ReceiptPrinterConnectionType.usb:
        return 'USB printer';
    }
  }

  String get identifierLabel {
    switch (this) {
      case ReceiptPrinterConnectionType.system:
        return 'Printer identifier';
      case ReceiptPrinterConnectionType.network:
        return 'Printer address';
      case ReceiptPrinterConnectionType.bluetooth:
        return 'Bluetooth address';
      case ReceiptPrinterConnectionType.usb:
        return 'USB identifier';
    }
  }

  String get identifierHint {
    switch (this) {
      case ReceiptPrinterConnectionType.system:
        return 'Optional queue id / URL from your OS';
      case ReceiptPrinterConnectionType.network:
        return 'Example: 192.168.1.25 or ipp://printer.local';
      case ReceiptPrinterConnectionType.bluetooth:
        return 'Example: AA:BB:CC:DD:EE:FF';
      case ReceiptPrinterConnectionType.usb:
        return 'Example: VendorId:ProductId';
    }
  }

  static ReceiptPrinterConnectionType fromName(String? name) {
    return ReceiptPrinterConnectionType.values.firstWhere(
      (v) => v.name == name,
      orElse: () => ReceiptPrinterConnectionType.system,
    );
  }
}

/// Persisted receipt/printer configuration, edited from the Settings screen
/// (Receipt & Printer section) and consumed wherever a receipt PDF is built
/// (receipt_pdf.dart) so the POS screen itself never needs printer setup.
class ReceiptSettings {
  /// Friendly name shown in settings for the configured receipt printer.
  final String printerName;
  final ReceiptPrinterConnectionType connectionType;
  final String printerIdentifier;
  final int receiptCopies;
  final bool autoPrintEnabled;
  final ReceiptPaperSize paperSize;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String receiptHeader;
  final String footerMessage;
  final bool showLogo;
  final bool showCashier;
  final bool showDateTime;
  final bool showReceiptNumber;

  const ReceiptSettings({
    this.printerName = '',
    this.connectionType = ReceiptPrinterConnectionType.system,
    this.printerIdentifier = '',
    this.receiptCopies = 1,
    this.autoPrintEnabled = false,
    this.paperSize = ReceiptPaperSize.mm80,
    this.storeName = 'Store POS',
    this.storeAddress = '',
    this.storePhone = '',
    this.receiptHeader = '',
    this.footerMessage = 'Thank you for your purchase!',
    this.showLogo = false,
    this.showCashier = true,
    this.showDateTime = true,
    this.showReceiptNumber = true,
  });

  static const defaults = ReceiptSettings();

  ReceiptSettings copyWith({
    String? printerName,
    ReceiptPrinterConnectionType? connectionType,
    String? printerIdentifier,
    int? receiptCopies,
    bool? autoPrintEnabled,
    ReceiptPaperSize? paperSize,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? receiptHeader,
    String? footerMessage,
    bool? showLogo,
    bool? showCashier,
    bool? showDateTime,
    bool? showReceiptNumber,
  }) {
    return ReceiptSettings(
      printerName: printerName ?? this.printerName,
      connectionType: connectionType ?? this.connectionType,
      printerIdentifier: printerIdentifier ?? this.printerIdentifier,
      receiptCopies: receiptCopies ?? this.receiptCopies,
      autoPrintEnabled: autoPrintEnabled ?? this.autoPrintEnabled,
      paperSize: paperSize ?? this.paperSize,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhone: storePhone ?? this.storePhone,
      receiptHeader: receiptHeader ?? this.receiptHeader,
      footerMessage: footerMessage ?? this.footerMessage,
      showLogo: showLogo ?? this.showLogo,
      showCashier: showCashier ?? this.showCashier,
      showDateTime: showDateTime ?? this.showDateTime,
      showReceiptNumber: showReceiptNumber ?? this.showReceiptNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'printer_name': printerName,
        'printer_connection_type': connectionType.name,
        'printer_identifier': printerIdentifier,
        'receipt_copies': receiptCopies,
        'auto_print_enabled': autoPrintEnabled,
        'paper_size': paperSize.name,
        'store_name': storeName,
        'store_address': storeAddress,
        'store_phone': storePhone,
        'receipt_header': receiptHeader,
        'footer_message': footerMessage,
        'show_logo': showLogo,
        'show_cashier': showCashier,
        'show_date_time': showDateTime,
        'show_receipt_number': showReceiptNumber,
      };

  /// Tolerant of missing/extra keys so older persisted settings (from a
  /// previous version of this screen) still load instead of crashing.
  factory ReceiptSettings.fromJson(Map<String, dynamic> json) {
    const d = ReceiptSettings.defaults;
    return ReceiptSettings(
      printerName: json['printer_name'] as String? ?? d.printerName,
      connectionType: ReceiptPrinterConnectionTypeX.fromName(
        json['printer_connection_type'] as String?,
      ),
      printerIdentifier: json['printer_identifier'] as String? ?? d.printerIdentifier,
      receiptCopies: (json['receipt_copies'] is int)
          ? (json['receipt_copies'] as int).clamp(1, 10).toInt()
          : d.receiptCopies,
      autoPrintEnabled: json['auto_print_enabled'] as bool? ?? d.autoPrintEnabled,
      paperSize: ReceiptPaperSizeX.fromName(json['paper_size'] as String?),
      storeName: json['store_name'] as String? ?? d.storeName,
      storeAddress: json['store_address'] as String? ?? d.storeAddress,
      storePhone: json['store_phone'] as String? ?? d.storePhone,
      receiptHeader: json['receipt_header'] as String? ?? d.receiptHeader,
      footerMessage: json['footer_message'] as String? ?? d.footerMessage,
      showLogo: json['show_logo'] as bool? ?? d.showLogo,
      showCashier: json['show_cashier'] as bool? ?? d.showCashier,
      showDateTime: json['show_date_time'] as bool? ?? d.showDateTime,
      showReceiptNumber: json['show_receipt_number'] as bool? ?? d.showReceiptNumber,
    );
  }
}
