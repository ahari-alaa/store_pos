/// Units a supply's quantity can be entered in (spec §2). Mirrors the
/// backend `expenses.unit` ENUM.
enum ExpenseUnit {
  kg,
  g,
  l,
  ml,
  unit,
  pack,
  box,
  bottle,
  piece;

  String get apiValue {
    switch (this) {
      case ExpenseUnit.kg:
        return 'kg';
      case ExpenseUnit.g:
        return 'g';
      case ExpenseUnit.l:
        return 'l';
      case ExpenseUnit.ml:
        return 'ml';
      case ExpenseUnit.unit:
        return 'unit';
      case ExpenseUnit.pack:
        return 'pack';
      case ExpenseUnit.box:
        return 'box';
      case ExpenseUnit.bottle:
        return 'bottle';
      case ExpenseUnit.piece:
        return 'piece';
    }
  }

  /// Short label shown next to a quantity, e.g. "15 kg".
  String get label {
    switch (this) {
      case ExpenseUnit.kg:
        return 'kg';
      case ExpenseUnit.g:
        return 'g';
      case ExpenseUnit.l:
        return 'L';
      case ExpenseUnit.ml:
        return 'ml';
      case ExpenseUnit.unit:
        return 'unité';
      case ExpenseUnit.pack:
        return 'pack';
      case ExpenseUnit.box:
        return 'boîte';
      case ExpenseUnit.bottle:
        return 'bouteille';
      case ExpenseUnit.piece:
        return 'pièce';
    }
  }

  static ExpenseUnit? fromApiValue(String? value) {
    if (value == null) return null;
    for (final u in ExpenseUnit.values) {
      if (u.apiValue == value) return u;
    }
    return null;
  }
}
