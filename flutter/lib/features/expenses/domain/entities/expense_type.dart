/// The three top-level expense types from the spec's tab structure
/// ([Toutes] [Approvisionnements] [Charges fixes] [Autres]). Mirrors the
/// backend `expenses.expense_type` ENUM (see
/// migrations/005_expenses_management.sql).
enum ExpenseType {
  approvisionnement,
  chargeFixe,
  autre;

  String get apiValue {
    switch (this) {
      case ExpenseType.approvisionnement:
        return 'APPROVISIONNEMENT';
      case ExpenseType.chargeFixe:
        return 'CHARGE_FIXE';
      case ExpenseType.autre:
        return 'AUTRE';
    }
  }

  /// Label used on tabs, badges, and the "Type" picker in the form.
  String get label {
    switch (this) {
      case ExpenseType.approvisionnement:
        return 'Approvisionnement';
      case ExpenseType.chargeFixe:
        return 'Charge fixe';
      case ExpenseType.autre:
        return 'Autre';
    }
  }

  /// Plural label used on the tab bar and the summary cards.
  String get pluralLabel {
    switch (this) {
      case ExpenseType.approvisionnement:
        return 'Approvisionnements';
      case ExpenseType.chargeFixe:
        return 'Charges fixes';
      case ExpenseType.autre:
        return 'Autres';
    }
  }

  static ExpenseType fromApiValue(String value) {
    switch (value) {
      case 'APPROVISIONNEMENT':
        return ExpenseType.approvisionnement;
      case 'CHARGE_FIXE':
        return ExpenseType.chargeFixe;
      default:
        return ExpenseType.autre;
    }
  }
}
