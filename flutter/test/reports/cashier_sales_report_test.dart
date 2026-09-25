import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/core/utils/local_date_range.dart';
import 'package:store_pos/features/reports/domain/entities/cashier_sales_report.dart';

void main() {
  group('LocalDateRange', () {
    test('dayStart/dayEnd bracket the given calendar day, naive local, no Z', () {
      final day = DateTime(2026, 9, 13);
      expect(LocalDateRange.dayStart(day), '2026-09-13T00:00:00');
      expect(LocalDateRange.dayEnd(day), '2026-09-13T23:59:59');
    });

    test('pads single-digit month/day/hour correctly', () {
      final day = DateTime(2026, 1, 5);
      expect(LocalDateRange.dayStart(day), '2026-01-05T00:00:00');
    });

    test('monthStart/monthEnd bracket the whole month regardless of day-of-month passed in', () {
      // Passing the 13th of September should still yield the 1st.._30th
      // boundaries — callers pass "the currently selected month", not
      // necessarily the 1st (spec §4: "September 2026" selector).
      final anyDayInMonth = DateTime(2026, 9, 13);
      expect(LocalDateRange.monthStart(anyDayInMonth), '2026-09-01T00:00:00');
      expect(LocalDateRange.monthEnd(anyDayInMonth), '2026-09-30T23:59:59');
    });

    test('monthEnd handles a 31-day month', () {
      expect(LocalDateRange.monthEnd(DateTime(2026, 10, 1)), '2026-10-31T23:59:59');
    });

    test('monthEnd handles February in a leap year', () {
      expect(LocalDateRange.monthEnd(DateTime(2028, 2, 1)), '2028-02-29T23:59:59');
    });

    test('monthEnd handles December by rolling into next year internally', () {
      // DateTime(year, 13, 1) is what monthEnd computes internally for
      // December — Dart normalizes that to January of next year, which is
      // exactly the "first of next month" this method needs.
      expect(LocalDateRange.monthEnd(DateTime(2026, 12, 5)), '2026-12-31T23:59:59');
    });
  });

  group('CashierReportSummary.fromJson', () {
    test('parses every field from the backend summary shape', () {
      final summary = CashierReportSummary.fromJson({
        'orders': 5,
        'total_sales': '470.00',
        'paid_orders': 3,
        'not_paid_orders': 1,
        'partially_paid_orders': 1,
      });

      expect(summary.orders, 5);
      expect(summary.totalSales, 470.0);
      expect(summary.paidOrders, 3);
      expect(summary.notPaidOrders, 1);
      expect(summary.partiallyPaidOrders, 1);
    });

    test('defaults every field to zero for an empty/missing payload', () {
      final summary = CashierReportSummary.fromJson(const {});
      expect(summary.orders, 0);
      expect(summary.totalSales, 0);
      expect(summary.paidOrders, 0);
      expect(summary.notPaidOrders, 0);
      expect(summary.partiallyPaidOrders, 0);
    });
  });

  group('CashierSalesReport.fromJson', () {
    test('parses the Day report shape (no days array)', () {
      final report = CashierSalesReport.fromJson({
        'cashier': {'id': 'c1', 'name': 'Alaa', 'email': 'a@x.com', 'role': 'cashier', 'is_active': true},
        'period': {'from': '2026-09-13T00:00:00', 'to': '2026-09-13T23:59:59'},
        'summary': {
          'orders': 5,
          'total_sales': '470.00',
          'paid_orders': 3,
          'not_paid_orders': 1,
          'partially_paid_orders': 1,
        },
      });

      expect(report.summary.orders, 5);
      expect(report.days, isEmpty);
    });

    test('parses the Month report shape, including the daily breakdown', () {
      final report = CashierSalesReport.fromJson({
        'summary': {
          'orders': 70,
          'total_sales': '8500.00',
          'paid_orders': 65,
          'not_paid_orders': 5,
          'partially_paid_orders': 0,
        },
        'days': [
          {
            'date': '2026-09-01',
            'orders': 32,
            'total_sales': '3850.00',
            'paid_orders': 31,
            'not_paid_orders': 1,
            'partially_paid_orders': 0,
          },
          {
            'date': '2026-09-02',
            'orders': 38,
            'total_sales': '4650.00',
            'paid_orders': 34,
            'not_paid_orders': 4,
            'partially_paid_orders': 0,
          },
        ],
      });

      expect(report.summary.orders, 70);
      expect(report.days, hasLength(2));
      expect(report.days.first.date, DateTime(2026, 9, 1));
      expect(report.days.first.summary.orders, 32);
      expect(report.days.first.summary.totalSales, 3850.0);
      // Daily figures must sum to the same summary total — a regression
      // here would mean the backend's two queries (summary vs. daily
      // breakdown) disagree.
      final summedOrders = report.days.fold<int>(0, (sum, d) => sum + d.summary.orders);
      expect(summedOrders, 70);
    });
  });
}
