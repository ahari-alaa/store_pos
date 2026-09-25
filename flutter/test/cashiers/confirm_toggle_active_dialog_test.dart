import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/cashiers/presentation/widgets/confirm_toggle_active_dialog.dart';

/// Regression tests for the Navigator `_debugLocked` / black-screen bug on
/// the Cashiers screen.
///
/// The harness deliberately mirrors the real route topology: a root
/// Navigator (MaterialApp's) with a SECOND, nested Navigator below it —
/// the same shape go_router produces for the `ShellRoute` that wraps
/// every page including `/cashiers`. That nesting is the entire point:
/// the old code popped the nested (shell) navigator instead of the root
/// one the dialog actually lives on, which tore the page out from under
/// the dialog. A single-navigator test would pass against the buggy code
/// and prove nothing.
void main() {
  /// Text rendered by the stand-in for the `/cashiers` page. If the
  /// dialog ever pops the wrong navigator, this disappears — which is
  /// exactly the black screen users were seeing.
  const pageMarker = 'CASHIERS PAGE';

  Widget harness({required void Function(bool) onResult}) {
    return MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => _HostPage(onResult: onResult),
        ),
      ),
    );
  }

  testWidgets('Cancel closes the dialog and leaves the page mounted', (tester) async {
    bool? result;
    await tester.pumpWidget(harness(onResult: (value) => result = value));

    expect(find.text(pageMarker), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-button')));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate account?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The dialog is gone...
    expect(find.text('Deactivate account?'), findsNothing);
    // ...the page underneath is untouched (this is the black-screen guard)...
    expect(find.text(pageMarker), findsOneWidget);
    // ...the caller was told "not confirmed"...
    expect(result, isFalse);
    // ...and no Navigator assertion (`!_debugLocked`) was thrown.
    expect(tester.takeException(), isNull);
  });

  testWidgets('Confirm closes the dialog, leaves the page mounted, returns true',
      (tester) async {
    bool? result;
    await tester.pumpWidget(harness(onResult: (value) => result = value));

    await tester.tap(find.byKey(const Key('toggle-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate account?'), findsNothing);
    expect(find.text(pageMarker), findsOneWidget);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the barrier does not dismiss or resolve the dialog',
      (tester) async {
    bool? result;
    await tester.pumpWidget(harness(onResult: (value) => result = value));

    await tester.tap(find.byKey(const Key('toggle-button')));
    await tester.pumpAndSettle();

    // Top-left corner is barrier, well clear of the AlertDialog itself.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate account?'), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reactivate wording is used when the account is inactive',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => _HostPage(onResult: (_) {}, deactivating: false),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toggle-button')));
    await tester.pumpAndSettle();

    expect(find.text('Reactivate account?'), findsOneWidget);
    expect(find.text('Reactivate'), findsOneWidget);

    await tester.tap(find.text('Reactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Reactivate account?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Stand-in for `CashiersPage`: lives on the NESTED navigator, and opens
/// the confirmation dialog from its own context — exactly as the real
/// page does.
class _HostPage extends StatelessWidget {
  final void Function(bool) onResult;
  final bool deactivating;

  const _HostPage({required this.onResult, this.deactivating = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CASHIERS PAGE'),
            TextButton(
              key: const Key('toggle-button'),
              onPressed: () async {
                final confirmed = await showConfirmToggleActiveDialog(
                  context: context,
                  userName: 'Sara',
                  deactivating: deactivating,
                );
                onResult(confirmed);
              },
              child: const Text('Toggle'),
            ),
          ],
        ),
      ),
    );
  }
}
