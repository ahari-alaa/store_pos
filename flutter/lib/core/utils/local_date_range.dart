/// Formats calendar-day/month boundaries as naive local datetime strings
/// in ISO 8601 shape but WITHOUT a 'Z'/offset suffix — e.g.
/// '2026-09-13T00:00:00'. This deliberately matches two constraints at
/// once:
///
/// 1. It's the same shape `occurred_at` is stored and read back as
///    everywhere else in this app (see Sale.occurredAt's doc comment and
///    saleService.createSale on the backend: nothing in this app converts
///    sale timestamps to/from UTC). A bare offset-less 'T' datetime, when
///    parsed by `Date.parse`/`new Date(...)` in Node or `DateTime.parse`
///    in Dart, is read back as LOCAL time on both sides — so a boundary
///    built here lines up with the exact same calendar day a human
///    looking at the Sales/Cashier screens would expect (spec §15).
/// 2. It still satisfies `Joi.string().isoDate()` on the existing
///    GET /sales endpoint (saleValidators.listSales), which the Cashier
///    report's Day view and its per-day drill-down call directly with
///    `from`/`to` (see sales_provider.dart#cashierDaySalesProvider) — a
///    plain space-separated 'YYYY-MM-DD HH:mm:ss' would fail that
///    validator. MySQL itself accepts either separator for a DATETIME
///    string literal, so using 'T' doesn't affect the SQL side at all.
class LocalDateRange {
  LocalDateRange._();

  static String dayStart(DateTime day) {
    return _format(DateTime(day.year, day.month, day.day, 0, 0, 0));
  }

  static String dayEnd(DateTime day) {
    return _format(DateTime(day.year, day.month, day.day, 23, 59, 59));
  }

  static String monthStart(DateTime month) {
    return _format(DateTime(month.year, month.month, 1, 0, 0, 0));
  }

  static String monthEnd(DateTime month) {
    final firstOfNextMonth = DateTime(month.year, month.month + 1, 1);
    final lastDay = firstOfNextMonth.subtract(const Duration(days: 1));
    return _format(DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59));
  }

  /// Formats an arbitrary local DateTime (not just a day/month boundary)
  /// in the same naive 'YYYY-MM-DDTHH:mm:ss' shape — e.g. for a
  /// user-picked date+time on a form field (see expense_form_dialog.dart's
  /// `occurred_at`).
  static String iso(DateTime dt) => _format(dt);

  static String _format(DateTime dt) {
    String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${pad(dt.year, 4)}-${pad(dt.month)}-${pad(dt.day)}'
        'T${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }
}
