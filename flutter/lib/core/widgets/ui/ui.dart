/// Store POS reusable UI component library.
///
/// One import for every shared presentation widget:
///
/// ```dart
/// import '../../../../core/widgets/ui/ui.dart';
/// ```
///
/// These components carry no business logic and hold no providers. They
/// take data in and emit callbacks out, so a screen's logic stays in its
/// provider/notifier and the widgets stay reusable across modules.
library;

export 'app_button.dart';
export 'app_card.dart';
export 'app_data_table.dart';
export 'app_dialog.dart';
export 'app_states.dart';
export 'app_text_field.dart';
export 'kpi_card.dart';
export 'status_badge.dart';
