import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import 'cashier_sales_page.dart';
import 'sales_page.dart';

/// `/sales` for every role. A cashier gets [CashierSalesPage] (their own
/// orders + serving state); admin and manager keep the existing store-wide
/// [SalesPage] untouched.
class SalesEntryPage extends ConsumerWidget {
  const SalesEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCashier = ref.watch(authProvider.select((s) => s.user?.isCashier ?? false));
    return isCashier ? const CashierSalesPage() : const SalesPage();
  }
}
