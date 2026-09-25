import 'app_locale.dart';

/// Centralized bilingual (FR/AR) string table.
///
/// This is deliberately a plain Dart map rather than Flutter's
/// `flutter gen-l10n` / `.arb` codegen pipeline: that toolchain needs a
/// `flutter pub get` + code-generation pass to run, which isn't available
/// in the environment these changes were authored in. The trade-off is
/// explicit here so it's easy to migrate later if desired — every lookup
/// goes through the single [Translations.t] entry point below, so
/// swapping the implementation for generated `AppLocalizations` later
/// would only touch this file plus the small `t(context, key)` helper in
/// `app_localizations.dart`, not call sites.
///
/// Every screen that has been migrated to this system pulls its strings
/// from here (see the sidebar, top bar, dashboard and settings screens).
/// Screens not yet migrated keep their original hard-coded French text —
/// see the final delivery notes for the full list.
class Translations {
  Translations._();

  static const Map<String, Map<AppLocale, String>> _strings = {
    // --- Navigation / sidebar ---
    'nav.dashboard': {AppLocale.fr: 'Accueil', AppLocale.ar: 'الرئيسية'},
    'nav.pos': {AppLocale.fr: 'Caisse', AppLocale.ar: 'نقطة البيع'},
    'nav.products': {AppLocale.fr: 'Produits', AppLocale.ar: 'المنتجات'},
    'nav.sales': {AppLocale.fr: 'Ventes', AppLocale.ar: 'المبيعات'},
    'nav.clients': {AppLocale.fr: 'Clients', AppLocale.ar: 'العملاء'},
    'nav.expenses': {AppLocale.fr: 'Stocks & Dépenses', AppLocale.ar: 'المخزون والمصاريف'},
    'nav.cashiers': {AppLocale.fr: 'Utilisateurs', AppLocale.ar: 'أمناء الصندوق'},
    'nav.reports': {AppLocale.fr: 'Rapports', AppLocale.ar: 'التقارير'},
    'nav.settings': {AppLocale.fr: 'Paramètres', AppLocale.ar: 'الإعدادات'},
    'nav.stocks': {AppLocale.fr: 'Ingrédients', AppLocale.ar: 'المكونات'},
    // Cashier-only destination (personal report). Singular on purpose: it is
    // ONE cashier's own report, not the admin "Rapports" module.
    'nav.my_report': {AppLocale.fr: 'Rapport', AppLocale.ar: 'تقريري'},
    'app.name': {AppLocale.fr: 'Store POS', AppLocale.ar: 'Store POS'},
    'topbar.overview_subtitle': {
      AppLocale.fr: "Vue d'ensemble de votre magasin",
      AppLocale.ar: 'نظرة عامة على متجرك',
    },
    'common.back': {AppLocale.fr: 'Retour', AppLocale.ar: 'رجوع'},

    // --- Periods ---
    'period.today': {AppLocale.fr: "Aujourd'hui", AppLocale.ar: 'اليوم'},
    'period.week': {AppLocale.fr: 'Cette semaine', AppLocale.ar: 'هذا الأسبوع'},
    'period.month': {AppLocale.fr: 'Ce mois', AppLocale.ar: 'هذا الشهر'},
    'period.day_short': {AppLocale.fr: 'Jour', AppLocale.ar: 'يوم'},
    'period.week_short': {AppLocale.fr: 'Semaine', AppLocale.ar: 'أسبوع'},
    'period.month_short': {AppLocale.fr: 'Mois', AppLocale.ar: 'شهر'},

    // --- Dashboard ---
    'dashboard.revenue_today': {AppLocale.fr: "Revenue aujourd'hui", AppLocale.ar: 'الإيرادات اليوم'},
    'dashboard.sales': {AppLocale.fr: 'Ventes', AppLocale.ar: 'المبيعات'},
    'dashboard.products_sold': {AppLocale.fr: 'Produits vendus', AppLocale.ar: 'المنتجات المباعة'},
    'dashboard.average_basket': {AppLocale.fr: 'Panier moyen', AppLocale.ar: 'متوسط السلة'},
    'dashboard.revenue_chart_title': {
      AppLocale.fr: 'Chiffre d\'affaires',
      AppLocale.ar: 'رقم المعاملات',
    },
    'dashboard.best_cashier': {AppLocale.fr: 'Meilleur caissier', AppLocale.ar: 'أفضل أمين صندوق'},
    'dashboard.sales_status': {AppLocale.fr: 'Statut des ventes', AppLocale.ar: 'حالة المبيعات'},
    'dashboard.recent_sales': {AppLocale.fr: 'Ventes récentes', AppLocale.ar: 'المبيعات الأخيرة'},
    'dashboard.see_all': {AppLocale.fr: 'Voir tout', AppLocale.ar: 'عرض الكل'},
    'dashboard.no_cashiers': {
      AppLocale.fr: 'Aucun caissier avec des ventes sur cette période',
      AppLocale.ar: 'لا يوجد أمين صندوق له مبيعات في هذه الفترة',
    },
    'dashboard.no_sales_period': {
      AppLocale.fr: 'Aucune vente sur cette période',
      AppLocale.ar: 'لا توجد مبيعات في هذه الفترة',
    },
    'dashboard.no_recent_sales': {
      AppLocale.fr: 'Aucune vente récente',
      AppLocale.ar: 'لا توجد مبيعات حديثة',
    },
    'dashboard.load_error': {
      AppLocale.fr: 'Impossible de charger le tableau de bord',
      AppLocale.ar: 'تعذر تحميل لوحة التحكم',
    },
    // Diagnostic error states — these replace the single generic
    // 'dashboard.load_error' sentence that every section used to show for
    // every possible failure (see dashboard_error_view.dart).
    'dashboard.error_unreachable': {
      AppLocale.fr: 'Serveur injoignable',
      AppLocale.ar: 'تعذر الوصول إلى الخادم',
    },
    'dashboard.error_tried': {
      AppLocale.fr: 'Adresse contactée',
      AppLocale.ar: 'العنوان الذي تمت محاولة الاتصال به',
    },
    'dashboard.error_session': {
      AppLocale.fr: 'Session expirée. Reconnectez-vous.',
      AppLocale.ar: 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
    },
    'dashboard.error_forbidden': {
      AppLocale.fr: "Vous n'avez pas la permission de voir ces données.",
      AppLocale.ar: 'ليس لديك إذن لعرض هذه البيانات.',
    },
    'dashboard.error_unexpected': {
      AppLocale.fr: 'Une erreur inattendue est survenue.',
      AppLocale.ar: 'حدث خطأ غير متوقع.',
    },
    'dashboard.retry': {AppLocale.fr: 'Réessayer', AppLocale.ar: 'إعادة المحاولة'},
    'dashboard.sale_count_suffix': {AppLocale.fr: 'ventes', AppLocale.ar: 'مبيعات'},
    'dashboard.articles_sold': {
      AppLocale.fr: "Articles vendus aujourd'hui",
      AppLocale.ar: 'المنتجات المباعة اليوم',
    },
    'dashboard.see_more': {AppLocale.fr: 'Voir plus', AppLocale.ar: 'عرض المزيد'},
    'dashboard.items_sold_suffix': {AppLocale.fr: 'articles', AppLocale.ar: 'منتجات'},
    'dashboard.restricted': {
      AppLocale.fr: "Seuls les administrateurs et gérants peuvent consulter le tableau de bord.",
      AppLocale.ar: 'يمكن فقط للمسؤولين والمديرين الاطلاع على لوحة التحكم.',
    },

    // --- Sale statuses ---
    'status.completed': {AppLocale.fr: 'Terminées', AppLocale.ar: 'مكتملة'},
    'status.cancelled': {AppLocale.fr: 'Annulées', AppLocale.ar: 'ملغاة'},
    'status.refunded': {AppLocale.fr: 'Remboursées', AppLocale.ar: 'مسترجعة'},
    'status.pending': {AppLocale.fr: 'En attente', AppLocale.ar: 'قيد الانتظار'},

    // --- Settings ---
    'settings.title': {AppLocale.fr: 'Paramètres', AppLocale.ar: 'الإعدادات'},
    'settings.language': {AppLocale.fr: 'Langue', AppLocale.ar: 'اللغة'},
    'settings.language_desc': {
      AppLocale.fr: "Choisissez la langue de l'application.",
      AppLocale.ar: 'اختر لغة التطبيق.',
    },
    'settings.appearance': {AppLocale.fr: 'Apparence', AppLocale.ar: 'المظهر'},
    'settings.appearance_desc': {
      AppLocale.fr: "Personnalisez les couleurs de l'application.",
      AppLocale.ar: 'خصص ألوان التطبيق.',
    },
    'settings.theme_presets': {AppLocale.fr: 'Thèmes prédéfinis', AppLocale.ar: 'سمات جاهزة'},
    'settings.primary_color': {AppLocale.fr: 'Couleur principale', AppLocale.ar: 'اللون الأساسي'},
    'settings.secondary_color': {AppLocale.fr: 'Couleur secondaire', AppLocale.ar: 'اللون الثانوي'},
    'settings.accent_color': {AppLocale.fr: "Couleur d'accent", AppLocale.ar: 'لون التمييز'},
    'settings.background_color': {AppLocale.fr: 'Couleur de fond', AppLocale.ar: 'لون الخلفية'},
    'settings.card_color': {AppLocale.fr: 'Couleur des cartes', AppLocale.ar: 'لون البطاقات'},
    'settings.text_color': {AppLocale.fr: 'Couleur du texte', AppLocale.ar: 'لون النص'},
    'settings.reset_theme': {
      AppLocale.fr: 'Réinitialiser le thème',
      AppLocale.ar: 'إعادة تعيين السمة',
    },
    'settings.application': {AppLocale.fr: 'Application', AppLocale.ar: 'التطبيق'},

    // --- Theme preset names ---
    'theme.default': {AppLocale.fr: 'Défaut', AppLocale.ar: 'افتراضي'},
    'theme.blue': {AppLocale.fr: 'Bleu', AppLocale.ar: 'أزرق'},
    'theme.green': {AppLocale.fr: 'Vert', AppLocale.ar: 'أخضر'},
    'theme.purple': {AppLocale.fr: 'Violet', AppLocale.ar: 'بنفسجي'},
    'theme.orange': {AppLocale.fr: 'Orange', AppLocale.ar: 'برتقالي'},
    'theme.dark': {AppLocale.fr: 'Sombre', AppLocale.ar: 'داكن'},
    'theme.light': {AppLocale.fr: 'Clair', AppLocale.ar: 'فاتح'},
    'theme.custom': {AppLocale.fr: 'Personnalisé', AppLocale.ar: 'مخصص'},

    // --- Generic empty / error states ---
    'common.error_generic': {
      AppLocale.fr: "Une erreur s'est produite",
      AppLocale.ar: 'حدث خطأ ما',
    },
    'common.no_connection': {
      AppLocale.fr: 'Connexion au serveur impossible',
      AppLocale.ar: 'تعذر الاتصال بالخادم',
    },
    'common.loading': {AppLocale.fr: 'Chargement…', AppLocale.ar: 'جارٍ التحميل…'},

    // --- Sidebar section headings ---
    // The nine destinations are grouped so the rail reads as an
    // organised product rather than one long undifferentiated list.
    'nav.section_main': {AppLocale.fr: 'PILOTAGE', AppLocale.ar: 'القيادة'},
    'nav.section_catalog': {AppLocale.fr: 'CATALOGUE', AppLocale.ar: 'الكتالوج'},
    'nav.section_admin': {AppLocale.fr: 'ADMINISTRATION', AppLocale.ar: 'الإدارة'},
    'nav.collapse': {AppLocale.fr: 'Réduire le menu', AppLocale.ar: 'طيّ القائمة'},
    'nav.expand': {AppLocale.fr: 'Agrandir le menu', AppLocale.ar: 'توسيع القائمة'},

    // --- Connection status chip (top bar) ---
    // Wording is deliberately about *reachability of the server*, not
    // about a sync queue: this client has no offline write queue, so
    // claiming "synchronisé" would be a lie. See connection_status.dart.
    'connection.online': {AppLocale.fr: 'En ligne', AppLocale.ar: 'متصل'},
    'connection.offline': {AppLocale.fr: 'Hors ligne', AppLocale.ar: 'غير متصل'},
    'connection.checking': {AppLocale.fr: 'Vérification…', AppLocale.ar: 'جارٍ التحقق…'},
    'connection.online_detail': {
      AppLocale.fr: 'Le serveur répond. Les données affichées sont à jour.',
      AppLocale.ar: 'الخادم يستجيب. البيانات المعروضة محدّثة.',
    },
    'connection.offline_detail': {
      AppLocale.fr:
          'Le serveur est injoignable. Les nouvelles ventes ne peuvent pas être enregistrées tant que la connexion n\'est pas rétablie.',
      AppLocale.ar:
          'تعذر الوصول إلى الخادم. لا يمكن تسجيل مبيعات جديدة حتى يُستعاد الاتصال.',
    },
    'connection.checking_detail': {
      AppLocale.fr: 'Aucune requête n\'a encore abouti depuis le démarrage.',
      AppLocale.ar: 'لم يكتمل أي طلب منذ بدء التشغيل.',
    },
    'connection.last_contact': {
      AppLocale.fr: 'Dernier contact',
      AppLocale.ar: 'آخر اتصال',
    },

    // --- User menu (top bar) ---
    'user.menu': {AppLocale.fr: 'Compte utilisateur', AppLocale.ar: 'حساب المستخدم'},
    'user.settings': {AppLocale.fr: 'Paramètres', AppLocale.ar: 'الإعدادات'},
    'user.logout': {AppLocale.fr: 'Se déconnecter', AppLocale.ar: 'تسجيل الخروج'},
    'user.logout_confirm_title': {
      AppLocale.fr: 'Se déconnecter ?',
      AppLocale.ar: 'تسجيل الخروج؟',
    },
    'user.logout_confirm_body': {
      AppLocale.fr:
          'Votre session sera fermée et vous reviendrez à l\'écran de saisie du code PIN. Les ventes déjà enregistrées ne sont pas affectées.',
      AppLocale.ar:
          'سيتم إنهاء جلستك والعودة إلى شاشة إدخال الرمز السري. المبيعات المسجلة مسبقًا لن تتأثر.',
    },
    'role.admin': {AppLocale.fr: 'Administrateur', AppLocale.ar: 'مدير النظام'},
    'role.manager': {AppLocale.fr: 'Responsable', AppLocale.ar: 'مسؤول'},
    'role.cashier': {AppLocale.fr: 'Caissier', AppLocale.ar: 'أمين الصندوق'},

    // --- Generic actions ---
    'common.cancel': {AppLocale.fr: 'Annuler', AppLocale.ar: 'إلغاء'},
    'common.confirm': {AppLocale.fr: 'Confirmer', AppLocale.ar: 'تأكيد'},
    'common.retry': {AppLocale.fr: 'Réessayer', AppLocale.ar: 'إعادة المحاولة'},

    // --- Login ---
    'login.tagline': {
      AppLocale.fr: 'Caisse, stock et ventes — en un seul endroit.',
      AppLocale.ar: 'الصندوق والمخزون والمبيعات — في مكان واحد.',
    },
    'login.title': {AppLocale.fr: 'Ouvrir la session', AppLocale.ar: 'فتح الجلسة'},
    'login.subtitle': {
      AppLocale.fr: 'Saisissez votre code PIN pour accéder à la caisse',
      AppLocale.ar: 'أدخل رمزك السري للوصول إلى الصندوق',
    },
    'login.enter': {AppLocale.fr: 'Valider', AppLocale.ar: 'تأكيد'},
    'login.backspace': {AppLocale.fr: 'Effacer un chiffre', AppLocale.ar: 'حذف رقم'},
    'login.pin_too_short': {
      AppLocale.fr: 'Le code PIN comporte au moins 4 chiffres',
      AppLocale.ar: 'يتكون الرمز السري من 4 أرقام على الأقل',
    },
    'login.signing_in': {AppLocale.fr: 'Connexion en cours…', AppLocale.ar: 'جارٍ الاتصال…'},
    'login.footer_help': {
      AppLocale.fr: 'PIN oublié ? Contactez votre responsable.',
      AppLocale.ar: 'نسيت الرمز؟ تواصل مع المسؤول.',
    },

    // --- POS / cart panel ---
    'pos.current_sale': {AppLocale.fr: 'Vente en cours', AppLocale.ar: 'البيع الحالي'},
    'pos.item_count_zero': {AppLocale.fr: 'Aucun article', AppLocale.ar: 'لا توجد أصناف'},
    'pos.item_count_one': {AppLocale.fr: 'article', AppLocale.ar: 'صنف'},
    'pos.item_count_many': {AppLocale.fr: 'articles', AppLocale.ar: 'أصناف'},
    'pos.clear_sale': {AppLocale.fr: 'Vider la vente', AppLocale.ar: 'إفراغ البيع'},
    'pos.clear_sale_confirm': {
      AppLocale.fr:
          'Tous les articles du panier seront retirés et le paiement saisi sera remis à zéro.',
      AppLocale.ar: 'ستتم إزالة جميع الأصناف من السلة وإعادة تعيين المبلغ المُدخل.',
    },
    'pos.empty_cart': {AppLocale.fr: 'Panier vide', AppLocale.ar: 'السلة فارغة'},
    'pos.empty_cart_hint': {
      AppLocale.fr: 'Sélectionnez un produit dans le catalogue pour l\'ajouter.',
      AppLocale.ar: 'اختر منتجًا من الكتالوج لإضافته.',
    },
    'pos.pay': {AppLocale.fr: 'Encaisser', AppLocale.ar: 'تحصيل'},
    'pos.paying': {AppLocale.fr: 'Enregistrement…', AppLocale.ar: 'جارٍ التسجيل…'},
    'pos.receipt_unpaid': {
      AppLocale.fr: 'Ticket sans paiement',
      AppLocale.ar: 'إيصال بدون دفع',
    },
    'pos.print': {AppLocale.fr: 'Imprimer', AppLocale.ar: 'طباعة'},
    'pos.share': {AppLocale.fr: 'Partager', AppLocale.ar: 'مشاركة'},
    'pos.cart_empty_toast': {
      AppLocale.fr: 'Le panier est vide.',
      AppLocale.ar: 'السلة فارغة.',
    },
    'pos.sale_failed': {
      AppLocale.fr: 'La vente n\'a pas pu être enregistrée. Veuillez réessayer.',
      AppLocale.ar: 'تعذر تسجيل عملية البيع. يرجى المحاولة مرة أخرى.',
    },
    'pos.receipt_failed': {
      AppLocale.fr: 'Le ticket n\'a pas pu être créé. Veuillez réessayer.',
      AppLocale.ar: 'تعذر إنشاء الإيصال. يرجى المحاولة مرة أخرى.',
    },
    'pos.printer_unavailable': {
      AppLocale.fr: 'Imprimante indisponible. Vérifiez l\'imprimante et réessayez.',
      AppLocale.ar: 'الطابعة غير متاحة. تحقق من الطابعة وحاول مرة أخرى.',
    },
    'pos.print_sent': {
      AppLocale.fr: 'Ticket envoyé à l\'imprimante.',
      AppLocale.ar: 'تم إرسال الإيصال إلى الطابعة.',
    },
    'pos.share_failed': {
      AppLocale.fr: 'Impossible de partager le ticket. Veuillez réessayer.',
      AppLocale.ar: 'تعذرت مشاركة الإيصال. يرجى المحاولة مرة أخرى.',
    },
    'keypad.title': {AppLocale.fr: 'Montant reçu', AppLocale.ar: 'المبلغ المستلم'},
    'keypad.total': {AppLocale.fr: 'Total à payer', AppLocale.ar: 'المبلغ الإجمالي'},
    'keypad.change': {AppLocale.fr: 'Rendu', AppLocale.ar: 'الباقي'},
    'keypad.remaining': {AppLocale.fr: 'Reste à payer', AppLocale.ar: 'المتبقي'},
    'keypad.clear': {AppLocale.fr: 'Effacer', AppLocale.ar: 'مسح'},
    'keypad.backspace': {AppLocale.fr: 'Corriger', AppLocale.ar: 'تصحيح'},
    'keypad.confirm': {AppLocale.fr: 'Valider', AppLocale.ar: 'تأكيد'},
    'keypad.exact': {AppLocale.fr: 'Appoint', AppLocale.ar: 'المبلغ بالضبط'},
    'keypad.quick_amounts': {
      AppLocale.fr: 'Montants rapides',
      AppLocale.ar: 'مبالغ سريعة',
    },

    'pos.unpaid_created': {
      AppLocale.fr: 'Ticket créé — NON PAYÉ',
      AppLocale.ar: 'تم إنشاء الإيصال — غير مدفوع',
    },

    // --- Rapports (spec: full store-activity report, distinct from
    // Accueil's quick snapshot) ---
    'reports.subtitle': {
      AppLocale.fr: "Analysez les performances de votre commerce",
      AppLocale.ar: 'تحليل نشاط المتجر',
    },
    'reports.restricted': {
      AppLocale.fr: "Vous n'avez pas accès aux rapports.",
      AppLocale.ar: 'ليس لديك صلاحية الوصول إلى التقارير.',
    },
    'reports.refresh': {AppLocale.fr: 'Actualiser', AppLocale.ar: 'تحديث'},
    'reports.export': {AppLocale.fr: 'Exporter', AppLocale.ar: 'تصدير'},
    'reports.export_pdf': {AppLocale.fr: 'Exporter en PDF', AppLocale.ar: 'تصدير كملف PDF'},
    'reports.export_csv': {AppLocale.fr: 'Exporter en CSV', AppLocale.ar: 'تصدير كملف CSV'},
    'reports.export_failed': {
      AppLocale.fr: "L'export a échoué. Veuillez réessayer.",
      AppLocale.ar: 'فشل التصدير. يرجى المحاولة مرة أخرى.',
    },
    'reports.pick_custom_range': {
      AppLocale.fr: 'Sélectionnez une date de début et une date de fin.',
      AppLocale.ar: 'اختر تاريخ البداية وتاريخ النهاية.',
    },
    'reports.kpi_revenue': {AppLocale.fr: "Chiffre d'affaires", AppLocale.ar: 'رقم الأعمال'},
    'reports.kpi_orders': {AppLocale.fr: 'Commandes', AppLocale.ar: 'الطلبات'},
    'reports.kpi_items_sold': {AppLocale.fr: 'Articles vendus', AppLocale.ar: 'المنتجات المباعة'},
    'reports.kpi_average_sale': {AppLocale.fr: 'Ticket moyen', AppLocale.ar: 'متوسط الفاتورة'},
    'reports.revenue_evolution': {
      AppLocale.fr: "Évolution du chiffre d'affaires",
      AppLocale.ar: 'تطور رقم الأعمال',
    },
    'reports.orders_suffix': {AppLocale.fr: 'commandes', AppLocale.ar: 'طلبات'},
    'reports.units_suffix': {AppLocale.fr: 'unités', AppLocale.ar: 'وحدات'},
    'reports.sales_summary': {AppLocale.fr: 'Résumé des ventes', AppLocale.ar: 'ملخص المبيعات'},
    'reports.status_total': {AppLocale.fr: 'Total', AppLocale.ar: 'الإجمالي'},
    'reports.status_completed': {AppLocale.fr: 'Terminées', AppLocale.ar: 'مكتملة'},
    'reports.status_paid': {AppLocale.fr: 'Payées', AppLocale.ar: 'مدفوعة'},
    'reports.status_not_paid': {AppLocale.fr: 'Non payées', AppLocale.ar: 'غير مدفوعة'},
    'reports.status_partially_paid': {
      AppLocale.fr: 'Partiellement payées',
      AppLocale.ar: 'مدفوعة جزئياً',
    },
    'reports.status_cancelled': {AppLocale.fr: 'Annulées', AppLocale.ar: 'ملغاة'},
    'reports.status_refunded': {AppLocale.fr: 'Remboursées', AppLocale.ar: 'مسترجعة'},
    'reports.payment_breakdown': {
      AppLocale.fr: 'Répartition des paiements',
      AppLocale.ar: 'توزيع طرق الدفع',
    },
    'reports.cashier_performance': {
      AppLocale.fr: 'Performance des caissiers',
      AppLocale.ar: 'أداء أمناء الصندوق',
    },
    'reports.cashier_detail': {AppLocale.fr: 'Détail du caissier', AppLocale.ar: 'تفاصيل أمين الصندوق'},
    'reports.sales_by_day': {AppLocale.fr: 'Ventes par jour', AppLocale.ar: 'المبيعات حسب اليوم'},
    'reports.top_products': {
      AppLocale.fr: 'Produits les plus vendus',
      AppLocale.ar: 'الأكثر مبيعاً من المنتجات',
    },
    'reports.expenses': {AppLocale.fr: 'Dépenses', AppLocale.ar: 'المصاريف'},
    'reports.stock': {AppLocale.fr: 'État du stock', AppLocale.ar: 'حالة المخزون'},
    'reports.stock_ok_title': {AppLocale.fr: 'Stock au vert', AppLocale.ar: 'المخزون جيد'},
    'reports.stock_ok_message': {
      AppLocale.fr: 'Aucun produit ni ingrédient en stock faible ou en rupture.',
      AppLocale.ar: 'لا توجد منتجات أو مكونات بمخزون منخفض أو نافد.',
    },
    'reports.recent_transactions': {
      AppLocale.fr: 'Transactions récentes',
      AppLocale.ar: 'المعاملات الأخيرة',
    },
    'reports.column_cashier': {AppLocale.fr: 'Caissier', AppLocale.ar: 'أمين الصندوق'},
    'reports.column_orders': {AppLocale.fr: 'Commandes', AppLocale.ar: 'الطلبات'},
    'reports.column_items': {AppLocale.fr: 'Articles', AppLocale.ar: 'المنتجات'},
    'reports.column_revenue': {AppLocale.fr: "CA", AppLocale.ar: 'رقم الأعمال'},
    'reports.column_average_ticket': {AppLocale.fr: 'Ticket moyen', AppLocale.ar: 'متوسط الفاتورة'},
    'reports.column_reference': {AppLocale.fr: 'Référence', AppLocale.ar: 'المرجع'},
    'reports.column_date': {AppLocale.fr: 'Date', AppLocale.ar: 'التاريخ'},
    'reports.column_total': {AppLocale.fr: 'Total', AppLocale.ar: 'الإجمالي'},
    'reports.column_payment_method': {
      AppLocale.fr: 'Mode de paiement',
      AppLocale.ar: 'طريقة الدفع',
    },
    'reports.column_status': {AppLocale.fr: 'Statut', AppLocale.ar: 'الحالة'},
    'reports.empty_title': {AppLocale.fr: 'Aucune donnée pour cette période', AppLocale.ar: 'لا توجد بيانات لهذه الفترة'},
    'reports.empty_message': {
      AppLocale.fr: 'Essayez de sélectionner une autre période.',
      AppLocale.ar: 'حاول اختيار فترة أخرى.',
    },
    'reports.error_title': {
      AppLocale.fr: 'Impossible de charger les rapports',
      AppLocale.ar: 'تعذر تحميل التقارير',
    },
    'reports.error_message': {
      AppLocale.fr: 'Une erreur est survenue. Veuillez réessayer.',
      AppLocale.ar: 'حدث خطأ. يرجى المحاولة مرة أخرى.',
    },

    // Redesigned Rapports screen (compact desktop layout).
    'reports.orders_by_hour': {
      AppLocale.fr: "Commandes par heure",
      AppLocale.ar: "الطلبات حسب الساعة",
    },
    'reports.orders_by_hour_cumulative': {
      AppLocale.fr: "Cumul sur la période",
      AppLocale.ar: "المجموع خلال الفترة",
    },
    'reports.col_hour': {
      AppLocale.fr: "Heure",
      AppLocale.ar: "الساعة",
    },
    'reports.col_orders': {
      AppLocale.fr: "Commandes",
      AppLocale.ar: "الطلبات",
    },
    'reports.col_revenue_dh': {
      AppLocale.fr: "CA (DH)",
      AppLocale.ar: "رقم الأعمال (درهم)",
    },
    'reports.total_row': {
      AppLocale.fr: "TOTAL",
      AppLocale.ar: "المجموع",
    },
    'reports.no_sales': {
      AppLocale.fr: "Aucune vente pour cette période.",
      AppLocale.ar: "لا توجد مبيعات لهذه الفترة.",
    },
    'reports.no_payments': {
      AppLocale.fr: "Aucun encaissement pour cette période.",
      AppLocale.ar: "لا توجد مدفوعات لهذه الفترة.",
    },
    'reports.no_expenses': {
      AppLocale.fr: "Aucune dépense pour cette période.",
      AppLocale.ar: "لا توجد مصاريف لهذه الفترة.",
    },
    'reports.amounts_in_dh': {
      AppLocale.fr: "Montants en DH",
      AppLocale.ar: "المبالغ بالدرهم",
    },
    'reports.payments_title': {
      AppLocale.fr: "Moyens de paiement",
      AppLocale.ar: "وسائل الدفع",
    },
    'reports.col_payment_method': {
      AppLocale.fr: "Moyen de paiement",
      AppLocale.ar: "وسيلة الدفع",
    },
    'reports.col_collected': {
      AppLocale.fr: "Encaissement",
      AppLocale.ar: "المقبوض",
    },
    'reports.col_count': {
      AppLocale.fr: "Nombre",
      AppLocale.ar: "العدد",
    },
    'reports.col_in_drawer': {
      AppLocale.fr: "Dans le tiroir",
      AppLocale.ar: "في الصندوق",
    },
    'reports.outstanding': {
      AppLocale.fr: "Reste à encaisser",
      AppLocale.ar: "المتبقي للتحصيل",
    },
    'reports.change_given': {
      AppLocale.fr: "Rendu monnaie (déjà déduit)",
      AppLocale.ar: "الباقي المُرجَع (مخصوم)",
    },
    'reports.col_product': {
      AppLocale.fr: "Produit",
      AppLocale.ar: "المنتج",
    },
    'reports.col_quantity': {
      AppLocale.fr: "Quantité",
      AppLocale.ar: "الكمية",
    },
    'reports.col_sales': {
      AppLocale.fr: "Ventes",
      AppLocale.ar: "المبيعات",
    },
    'reports.column_average_basket': {
      AppLocale.fr: "Panier moyen",
      AppLocale.ar: "متوسط السلة",
    },
    'reports.col_category': {
      AppLocale.fr: "Catégorie",
      AppLocale.ar: "الفئة",
    },
    'reports.col_amount': {
      AppLocale.fr: "Montant",
      AppLocale.ar: "المبلغ",
    },
    'reports.col_ticket': {
      AppLocale.fr: "Ticket",
      AppLocale.ar: "التذكرة",
    },
    'reports.col_time': {
      AppLocale.fr: "Heure",
      AppLocale.ar: "الوقت",
    },
    'reports.stock_alerts_title': {
      AppLocale.fr: "Stock & alertes",
      AppLocale.ar: "المخزون والتنبيهات",
    },
    'reports.alert_out_of_stock': {
      AppLocale.fr: "Ruptures de stock",
      AppLocale.ar: "نفاد المخزون",
    },
    'reports.alert_low_stock': {
      AppLocale.fr: "Stocks faibles",
      AppLocale.ar: "مخزون منخفض",
    },
    'reports.alert_unpaid': {
      AppLocale.fr: "Ventes non payées",
      AppLocale.ar: "مبيعات غير مدفوعة",
    },
    'reports.alert_partial': {
      AppLocale.fr: "Ventes partiellement payées",
      AppLocale.ar: "مبيعات مدفوعة جزئياً",
    },
    'reports.alert_cancelled': {
      AppLocale.fr: "Ventes annulées / remboursées",
      AppLocale.ar: "مبيعات ملغاة / مستردة",
    },
    'reports.alert_items': {
      AppLocale.fr: "Articles concernés",
      AppLocale.ar: "المنتجات المعنية",
    },
    'reports.remaining': {
      AppLocale.fr: "Reste",
      AppLocale.ar: "المتبقي",
    },
    'reports.stock_unavailable': {
      AppLocale.fr: "Stock indisponible pour le moment.",
      AppLocale.ar: "المخزون غير متاح حالياً.",
    },
    'reports.recent_sales': {
      AppLocale.fr: "Ventes récentes",
      AppLocale.ar: "آخر المبيعات",
    },
    'reports.see_all_sales': {
      AppLocale.fr: "Voir toutes les ventes",
      AppLocale.ar: "عرض كل المبيعات",
    },
    'reports.sale_paid': {
      AppLocale.fr: "Payé",
      AppLocale.ar: "مدفوع",
    },
    'reports.sale_partial': {
      AppLocale.fr: "Partiel",
      AppLocale.ar: "جزئي",
    },
    'reports.sale_unpaid': {
      AppLocale.fr: "Non payé",
      AppLocale.ar: "غير مدفوع",
    },
    'reports.sale_cancelled': {
      AppLocale.fr: "Annulée",
      AppLocale.ar: "ملغاة",
    },
    'reports.sale_refunded': {
      AppLocale.fr: "Remboursée",
      AppLocale.ar: "مستردة",
    },
    'reports.kpi_sales_count': {
      AppLocale.fr: "Nombre de ventes",
      AppLocale.ar: "عدد المبيعات",
    },
    'reports.kpi_expenses': {
      AppLocale.fr: "Dépenses",
      AppLocale.ar: "المصاريف",
    },
    'reports.kpi_result': {
      AppLocale.fr: "Résultat estimé",
      AppLocale.ar: "النتيجة التقديرية",
    },
    'reports.change_dates': {
      AppLocale.fr: "Modifier les dates",
      AppLocale.ar: "تعديل التواريخ",
    },
    'reports.print': {
      AppLocale.fr: "Imprimer",
      AppLocale.ar: "طباعة",
    },
    'reports.export_xlsx': {
      AppLocale.fr: "Excel (.xlsx)",
      AppLocale.ar: "Excel (.xlsx)",
    },
    'reports.export_dialog_title': {
      AppLocale.fr: "Enregistrer le rapport",
      AppLocale.ar: "حفظ التقرير",
    },
    'reports.export_saved': {
      AppLocale.fr: "Fichier enregistré :",
      AppLocale.ar: "تم حفظ الملف :",
    },
    'reports.integrity_warning': {
      AppLocale.fr: "Les totaux de certaines sections ne concordent pas. Actualisez le rapport ; si le message persiste, contactez le support.",
      AppLocale.ar: "مجاميع بعض الأقسام غير متطابقة. حدّث التقرير، وإذا استمرت الرسالة فاتصل بالدعم.",
    },
    'reports.retry': {
      AppLocale.fr: "Réessayer",
      AppLocale.ar: "إعادة المحاولة",
    },

    // Payment method labels shared across Rapports sections.
    'payment_method.cash': {AppLocale.fr: 'Espèces', AppLocale.ar: 'نقداً'},
    'payment_method.card': {AppLocale.fr: 'Carte', AppLocale.ar: 'بطاقة'},
    'payment_method.transfer': {AppLocale.fr: 'Virement', AppLocale.ar: 'تحويل'},
    'payment_method.mixed': {AppLocale.fr: 'Mixte', AppLocale.ar: 'مختلط'},

    // Stock severity labels (StatusBadge.stock) shared by Rapports and any
    // future stock screen.
    'stock.in_stock': {AppLocale.fr: 'En stock', AppLocale.ar: 'متوفر'},
    'stock.low_stock': {AppLocale.fr: 'Stock faible', AppLocale.ar: 'مخزون منخفض'},
    'stock.out_of_stock': {AppLocale.fr: 'Rupture', AppLocale.ar: 'نفد المخزون'},

    // --- Cashier: personal Rapport + Ventes (À servir / Servies) ---
    'mine.title': {AppLocale.fr: 'Rapport personnel', AppLocale.ar: 'تقريري الشخصي'},
    'mine.subtitle': {
      AppLocale.fr: 'Ce que vous avez vendu',
      AppLocale.ar: 'ما قمت ببيعه',
    },
    'mine.restricted': {
      AppLocale.fr: 'Cet écran est réservé aux caissiers.',
      AppLocale.ar: 'هذه الشاشة مخصصة لأمناء الصندوق.',
    },
    'mine.print_report': {AppLocale.fr: 'Imprimer le rapport', AppLocale.ar: 'طباعة التقرير'},
    'mine.period_custom': {AppLocale.fr: 'Période personnalisée', AppLocale.ar: 'فترة مخصصة'},
    'mine.kpi_sales': {AppLocale.fr: 'Ventes totales', AppLocale.ar: 'إجمالي المبيعات'},
    'mine.kpi_orders': {AppLocale.fr: 'Commandes', AppLocale.ar: 'الطلبات'},
    'mine.kpi_items': {AppLocale.fr: 'Produits vendus', AppLocale.ar: 'المنتجات المباعة'},
    'mine.kpi_average': {AppLocale.fr: 'Panier moyen', AppLocale.ar: 'متوسط الطلب'},
    'mine.unit_order_one': {AppLocale.fr: 'commande', AppLocale.ar: 'طلب'},
    'mine.unit_order_many': {AppLocale.fr: 'commandes', AppLocale.ar: 'طلبات'},
    'mine.unit_item_one': {AppLocale.fr: 'article', AppLocale.ar: 'قطعة'},
    'mine.unit_item_many': {AppLocale.fr: 'articles', AppLocale.ar: 'قطع'},
    'mine.products_title': {AppLocale.fr: 'Produits vendus', AppLocale.ar: 'المنتجات المباعة'},
    'mine.products_subtitle': {
      AppLocale.fr: 'Uniquement vos ventes sur la période',
      AppLocale.ar: 'مبيعاتك أنت فقط خلال الفترة',
    },
    'mine.col_product': {AppLocale.fr: 'Produit', AppLocale.ar: 'المنتج'},
    'mine.col_quantity': {AppLocale.fr: 'Quantité', AppLocale.ar: 'الكمية'},
    'mine.col_revenue': {AppLocale.fr: "Chiffre d'affaires", AppLocale.ar: 'رقم المعاملات'},
    'mine.products_empty': {
      AppLocale.fr: 'Aucun produit vendu sur cette période.',
      AppLocale.ar: 'لا توجد منتجات مباعة في هذه الفترة.',
    },
    'mine.to_serve_title': {AppLocale.fr: 'Commandes à servir', AppLocale.ar: 'طلبات بانتظار التقديم'},
    'mine.to_serve_subtitle': {
      AppLocale.fr: 'En attente, toutes dates confondues',
      AppLocale.ar: 'قيد الانتظار، بجميع التواريخ',
    },
    'mine.to_serve_empty': {
      AppLocale.fr: 'Aucune commande à servir.',
      AppLocale.ar: 'لا توجد طلبات بانتظار التقديم.',
    },
    'mine.served_title': {AppLocale.fr: 'Commandes servies', AppLocale.ar: 'الطلبات المقدَّمة'},
    'mine.served_subtitle': {
      AppLocale.fr: 'Sur la période sélectionnée',
      AppLocale.ar: 'خلال الفترة المحددة',
    },
    'mine.served_empty': {
      AppLocale.fr: 'Aucune commande servie sur cette période.',
      AppLocale.ar: 'لا توجد طلبات مقدَّمة في هذه الفترة.',
    },
    'mine.pending': {AppLocale.fr: 'en attente', AppLocale.ar: 'بالانتظار'},
    'mine.order': {AppLocale.fr: 'Commande', AppLocale.ar: 'طلب'},
    'mine.total': {AppLocale.fr: 'Total', AppLocale.ar: 'الإجمالي'},
    'mine.action_serve': {AppLocale.fr: 'IMPRIMER / SERVIR', AppLocale.ar: 'طباعة / تقديم'},
    'mine.action_reprint': {AppLocale.fr: 'Réimprimer', AppLocale.ar: 'إعادة الطباعة'},
    'mine.status_served': {AppLocale.fr: 'Servie', AppLocale.ar: 'مقدَّم'},
    'mine.status_to_serve': {AppLocale.fr: 'À servir', AppLocale.ar: 'بانتظار التقديم'},
    'mine.printed_times': {AppLocale.fr: 'Imprimé', AppLocale.ar: 'طُبع'},
    'mine.msg_served': {AppLocale.fr: 'Commande servie.', AppLocale.ar: 'تم تقديم الطلب.'},
    'mine.msg_reprinted': {AppLocale.fr: 'Reçu réimprimé.', AppLocale.ar: 'تمت إعادة طباعة الإيصال.'},
    'mine.msg_reprint_not_recorded': {
      AppLocale.fr: "Reçu réimprimé, mais le suivi n'a pas pu être enregistré.",
      AppLocale.ar: 'تمت إعادة الطباعة لكن تعذّر تسجيلها.',
    },
    'mine.msg_already_served': {
      AppLocale.fr: 'Cette commande a déjà été servie.',
      AppLocale.ar: 'تم تقديم هذا الطلب مسبقاً.',
    },
    'mine.msg_cancelled': {
      AppLocale.fr: 'Impression annulée — la commande reste à servir.',
      AppLocale.ar: 'أُلغيت الطباعة — يبقى الطلب بانتظار التقديم.',
    },
    'mine.msg_offline': {
      AppLocale.fr: "Hors ligne : une connexion est nécessaire pour servir une commande. Rien n'a été imprimé.",
      AppLocale.ar: 'لا يوجد اتصال: يلزم اتصال لتقديم الطلب. لم تتم أي طباعة.',
    },
    'mine.msg_print_failed': {
      AppLocale.fr: "Échec de l'impression — la commande n'a pas été marquée comme servie.",
      AppLocale.ar: 'فشلت الطباعة — لم يتم تسجيل الطلب كمقدَّم.',
    },
    'mine.msg_failed': {
      AppLocale.fr: 'Action impossible pour le moment. Veuillez réessayer.',
      AppLocale.ar: 'تعذّر تنفيذ الإجراء حالياً. حاول مرة أخرى.',
    },
    'mine.retry_title': {AppLocale.fr: 'Reçu imprimé', AppLocale.ar: 'تمت الطباعة'},
    'mine.retry_message': {
      AppLocale.fr: "Le reçu a été imprimé, mais la commande n'a pas pu être marquée comme servie.",
      AppLocale.ar: 'تمت طباعة الإيصال لكن تعذّر تسجيل الطلب كمقدَّم.',
    },
    'mine.retry_consequence': {
      AppLocale.fr: 'Réessayez : le reçu ne sera pas imprimé une seconde fois.',
      AppLocale.ar: 'أعد المحاولة: لن تتم طباعة الإيصال مرة ثانية.',
    },
    'mine.retry_confirm': {AppLocale.fr: 'Réessayer', AppLocale.ar: 'إعادة المحاولة'},
    'mine.retry_later': {AppLocale.fr: 'Plus tard', AppLocale.ar: 'لاحقاً'},
    'mine.report_failed': {
      AppLocale.fr: 'Impossible de générer le rapport. Veuillez réessayer.',
      AppLocale.ar: 'تعذّر إنشاء التقرير. حاول مرة أخرى.',
    },
    'mine.report_truncated': {
      AppLocale.fr: 'Le rapport imprimé est limité aux 2 000 premières commandes.',
      AppLocale.ar: 'التقرير المطبوع محدود بأول 2000 طلب.',
    },
    'mine.load_error': {
      AppLocale.fr: 'Impossible de charger vos données.',
      AppLocale.ar: 'تعذّر تحميل بياناتك.',
    },
    'mine.sales_subtitle': {
      AppLocale.fr: 'Vos commandes, avec le suivi de leur impression et de leur service.',
      AppLocale.ar: 'طلباتك مع متابعة الطباعة والتقديم.',
    },
    'mine.search_hint': {
      AppLocale.fr: 'Rechercher par numéro de reçu…',
      AppLocale.ar: 'ابحث برقم الإيصال…',
    },
    'mine.filter_all': {AppLocale.fr: 'Toutes', AppLocale.ar: 'الكل'},
    'mine.filter_to_serve': {AppLocale.fr: 'À servir', AppLocale.ar: 'بانتظار التقديم'},
    'mine.filter_served': {AppLocale.fr: 'Servies', AppLocale.ar: 'المقدَّمة'},
    'mine.filter_paid': {AppLocale.fr: 'Payées', AppLocale.ar: 'المدفوعة'},
    'mine.filter_unpaid': {AppLocale.fr: 'Non payées', AppLocale.ar: 'غير المدفوعة'},
    'mine.sales_empty': {AppLocale.fr: 'Aucune commande.', AppLocale.ar: 'لا توجد طلبات.'},
    'mine.load_more': {AppLocale.fr: 'Charger plus', AppLocale.ar: 'تحميل المزيد'},

    // --- Justificatif de travail (cashier settlements) — spec §1-§21,
    // embedded in the cashier's own Rapport screen (see SettlementSection).
    // NOT to be confused with 'mine.*' (customer payment / serving) above:
    // this is the cashier's own WORK payment.
    'settlements.kpi_available': {AppLocale.fr: 'Disponibles', AppLocale.ar: 'متاحة'},
    'settlements.kpi_justified': {AppLocale.fr: 'Déjà justifiées', AppLocale.ar: 'مبررة بالفعل'},
    'settlements.kpi_to_pay': {AppLocale.fr: 'À payer', AppLocale.ar: 'مستحق الدفع'},
    'settlements.kpi_already_paid': {AppLocale.fr: 'Déjà payé', AppLocale.ar: 'تم دفعه'},
    'settlements.eligible_title': {
      AppLocale.fr: 'Commandes à justifier',
      AppLocale.ar: 'طلبات بحاجة لتبرير',
    },
    'settlements.eligible_subtitle': {
      AppLocale.fr: 'commandes disponibles pour justificatif',
      AppLocale.ar: 'طلبات متاحة للتبرير',
    },
    'settlements.select_all': {AppLocale.fr: 'Tout sélectionner', AppLocale.ar: 'تحديد الكل'},
    'settlements.eligible_empty': {
      AppLocale.fr: 'Aucune commande disponible pour un justificatif.',
      AppLocale.ar: 'لا توجد طلبات متاحة للتبرير.',
    },
    'settlements.selected_count': {AppLocale.fr: 'commandes sélectionnées', AppLocale.ar: 'طلبات محددة'},
    'settlements.print_justificatif': {
      AppLocale.fr: 'Imprimer le justificatif',
      AppLocale.ar: 'طباعة المبرر',
    },
    'settlements.load_error': {
      AppLocale.fr: "Impossible de charger les justificatifs.",
      AppLocale.ar: 'تعذر تحميل المبررات.',
    },
    'settlements.msg_created': {
      AppLocale.fr: 'Justificatif {number} créé et imprimé.',
      AppLocale.ar: 'تم إنشاء وطباعة المبرر {number}.',
    },
    'settlements.msg_created_print_failed': {
      AppLocale.fr: 'Justificatif {number} créé, mais l\'impression a échoué. Utilisez "Voir" pour le réimprimer.',
      AppLocale.ar: 'تم إنشاء المبرر {number}، لكن الطباعة فشلت. استخدم "عرض" لإعادة الطباعة.',
    },
    'settlements.msg_no_selection': {
      AppLocale.fr: 'Sélectionnez au moins une commande.',
      AppLocale.ar: 'اختر طلباً واحداً على الأقل.',
    },
    'settlements.msg_rejected': {
      AppLocale.fr: 'Cette sélection ne peut pas être justifiée.',
      AppLocale.ar: 'لا يمكن تبرير هذا الاختيار.',
    },
    'settlements.msg_offline': {
      AppLocale.fr: 'Pas de connexion. Rien n\'a été créé.',
      AppLocale.ar: 'لا يوجد اتصال. لم يتم إنشاء أي شيء.',
    },
    'settlements.history_title': {
      AppLocale.fr: 'Commandes déjà justifiées',
      AppLocale.ar: 'طلبات مبررة بالفعل',
    },
    'settlements.history_subtitle': {AppLocale.fr: 'justificatifs', AppLocale.ar: 'مبررات'},
    'settlements.history_empty': {
      AppLocale.fr: 'Aucun justificatif pour le moment.',
      AppLocale.ar: 'لا توجد مبررات حتى الآن.',
    },
    'settlements.status_printed': {AppLocale.fr: 'À payer', AppLocale.ar: 'مستحق الدفع'},
    'settlements.status_paid': {AppLocale.fr: 'Payé', AppLocale.ar: 'مدفوع'},
    'settlements.status_cancelled': {AppLocale.fr: 'Annulé', AppLocale.ar: 'ملغى'},
    'settlements.view': {AppLocale.fr: 'Voir', AppLocale.ar: 'عرض'},

    // --- Paiements caissiers (admin/manager — spec §22-§23, §26, §33) ---
    'nav.cashier_settlements': {AppLocale.fr: 'Paiements caissiers', AppLocale.ar: 'مدفوعات أمناء الصندوق'},
    'admin_settlements.title': {AppLocale.fr: 'Paiements caissiers', AppLocale.ar: 'مدفوعات أمناء الصندوق'},
    'admin_settlements.subtitle': {
      AppLocale.fr: "Justificatifs de travail des caissiers et leur règlement.",
      AppLocale.ar: 'مبررات عمل أمناء الصندوق وتسويتها.',
    },
    'admin_settlements.filter_all': {AppLocale.fr: 'Tous', AppLocale.ar: 'الكل'},
    'admin_settlements.filter_printed': {AppLocale.fr: 'À payer', AppLocale.ar: 'مستحق الدفع'},
    'admin_settlements.filter_paid': {AppLocale.fr: 'Payés', AppLocale.ar: 'مدفوع'},
    'admin_settlements.filter_cancelled': {AppLocale.fr: 'Annulés', AppLocale.ar: 'ملغى'},
    'admin_settlements.col_settlement': {AppLocale.fr: 'Justificatif', AppLocale.ar: 'المبرر'},
    'admin_settlements.col_cashier': {AppLocale.fr: 'Caissier', AppLocale.ar: 'أمين الصندوق'},
    'admin_settlements.col_orders': {AppLocale.fr: 'Commandes', AppLocale.ar: 'الطلبات'},
    'admin_settlements.col_total': {AppLocale.fr: 'Total', AppLocale.ar: 'الإجمالي'},
    'admin_settlements.col_date': {AppLocale.fr: 'Date', AppLocale.ar: 'التاريخ'},
    'admin_settlements.col_status': {AppLocale.fr: 'État', AppLocale.ar: 'الحالة'},
    'admin_settlements.empty': {
      AppLocale.fr: 'Aucun justificatif pour le moment.',
      AppLocale.ar: 'لا توجد مبررات حتى الآن.',
    },
    'admin_settlements.load_error': {
      AppLocale.fr: 'Impossible de charger les paiements caissiers.',
      AppLocale.ar: 'تعذر تحميل مدفوعات أمناء الصندوق.',
    },
    'admin_settlements.detail_title': {AppLocale.fr: 'Justificatif', AppLocale.ar: 'المبرر'},
    'admin_settlements.orders_title': {AppLocale.fr: 'Commandes incluses', AppLocale.ar: 'الطلبات المشمولة'},
    'admin_settlements.close': {AppLocale.fr: 'Fermer', AppLocale.ar: 'إغلاق'},
    'admin_settlements.mark_paid': {AppLocale.fr: 'Marquer comme payé', AppLocale.ar: 'وضع علامة كمدفوع'},
    'admin_settlements.mark_paid_confirm_title': {
      AppLocale.fr: 'Marquer comme payé ?',
      AppLocale.ar: 'وضع علامة كمدفوع؟',
    },
    'admin_settlements.mark_paid_confirm_message': {
      AppLocale.fr: 'Ce justificatif sera marqué comme réglé au caissier. Cette action ne peut pas être annulée.',
      AppLocale.ar: 'سيتم وضع علامة على هذا المبرر كمسدد لأمين الصندوق. لا يمكن التراجع عن هذا الإجراء.',
    },
    'admin_settlements.mark_paid_success': {
      AppLocale.fr: 'Justificatif marqué comme payé.',
      AppLocale.ar: 'تم وضع علامة على المبرر كمدفوع.',
    },
    'admin_settlements.cancel': {AppLocale.fr: 'Annuler le justificatif', AppLocale.ar: 'إلغاء المبرر'},
    'admin_settlements.cancel_confirm_title': {AppLocale.fr: 'Annuler ce justificatif ?', AppLocale.ar: 'إلغاء هذا المبرر؟'},
    'admin_settlements.cancel_confirm_message': {
      AppLocale.fr:
          'Le justificatif restera visible dans l\'historique, mais ses commandes ne redeviendront pas disponibles automatiquement.',
      AppLocale.ar: 'سيبقى المبرر ظاهراً في السجل، لكن طلباته لن تصبح متاحة تلقائياً من جديد.',
    },
    'admin_settlements.cancel_reason_hint': {
      AppLocale.fr: 'Motif (optionnel)',
      AppLocale.ar: 'السبب (اختياري)',
    },
    'admin_settlements.cancel_success': {AppLocale.fr: 'Justificatif annulé.', AppLocale.ar: 'تم إلغاء المبرر.'},
    'admin_settlements.reprint': {AppLocale.fr: 'Réimprimer une copie', AppLocale.ar: 'إعادة طباعة نسخة'},
    'admin_settlements.reprint_confirm_title': {
      AppLocale.fr: 'Imprimer une copie ?',
      AppLocale.ar: 'طباعة نسخة؟',
    },
    'admin_settlements.reprint_confirm_message': {
      AppLocale.fr: 'Le document sera clairement marqué COPIE / DUPLICATA.',
      AppLocale.ar: 'سيتم وضع علامة واضحة على المستند بعبارة نسخة / مكررة.',
    },
    'admin_settlements.reprint_success': {AppLocale.fr: 'Copie imprimée.', AppLocale.ar: 'تمت طباعة النسخة.'},
  };

  static String t(AppLocale locale, String key) {
    final entry = _strings[key];
    if (entry == null) return key;
    return entry[locale] ?? entry[AppLocale.fr] ?? key;
  }
}
