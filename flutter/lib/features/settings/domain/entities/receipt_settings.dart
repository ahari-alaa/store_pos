import 'package:pdf/pdf.dart';

/// Paper width the receipt PDF is laid out for.
///
/// The app doesn't own real printer hardware/driver integration (see
/// receipt_pdf.dart) — printing always goes through the OS print dialog via
/// the `printing` package, which works with any printer the OS already
/// knows about, thermal or regular. This setting only controls how wide the
/// generated PDF page is, so a receipt printed on a narrow thermal roll
/// doesn't waste paper and one printed on a regular printer isn't a tiny
/// sliver on an A4 sheet.
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

/// Persisted receipt/printer configuration, edited from the Settings screen
/// (Receipt & Printer section) and consumed wherever a receipt PDF is built
/// (receipt_pdf.dart) so the POS screen itself never needs printer setup.
class ReceiptSettings {
  /// Informational label for the printer the store uses (e.g. "Front
  /// counter printer"). The actual OS print dialog still lets the cashier
  /// pick any available printer — this project has no printer-discovery/
  /// binding system, so this is intentionally just a label rather than a
  /// device handle.
  final String printerName;
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
