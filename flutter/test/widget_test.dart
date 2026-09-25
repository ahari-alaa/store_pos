// The default `flutter create` counter smoke test used to live here. It
// referenced a `MyApp` widget that this project never had (the root
// widget is `StorePosApp`, see lib/main.dart), so the file did not
// compile — and because `flutter test` compiles the whole test directory
// as one unit, that single broken file made EVERY test in the suite fail
// to run, including the real ones under test/reports/ and test/cashiers/.
//
// It is replaced with a single structural check rather than deleted, so
// the suite has an obvious place to grow app-level smoke tests later.
// Booting `StorePosApp` itself in a widget test is not useful yet: it
// immediately reaches for flutter_secure_storage (TokenStorage) and the
// backend through ApiClient, both of which need their platform channels
// faked first.

import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/main.dart';

void main() {
  test('StorePosApp is const-constructible (root widget wiring sanity check)', () {
    const app = StorePosApp();
    expect(app, isA<StorePosApp>());
  });
}
