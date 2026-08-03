// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get navDashboard => 'الرئيسية';

  @override
  String get navItems => 'الأصناف';

  @override
  String get navParties => 'الحسابات';

  @override
  String get navTransactions => 'المعاملات';

  @override
  String get navEntries => 'القيود';

  @override
  String get navMore => 'المزيد...';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsHeaderTitle => 'تفضيلات التطبيق';

  @override
  String get settingsHeaderSubtitle =>
      'إدارة الإعدادات الافتراضية للتقارير والقيم ومعايير الأصناف.';

  @override
  String get settingsSectionAppearance => 'المظهر العام';

  @override
  String get settingsSectionSecurity => 'الأمان';

  @override
  String get settingsSectionGeneral => 'عام';

  @override
  String get settingsSectionDefaults => 'الإعدادات الافتراضية';

  @override
  String get settingsSectionConfigurations => 'التخصيصات';

  @override
  String get settingsTheme => 'المظهر';

  @override
  String get settingsThemeSubtitle => 'اختر النظام أو الوضع الفاتح أو الداكن';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageSubtitle => 'اختر لغة التطبيق';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageArabic => 'العربية';

  @override
  String settingsBiometricLogin(String label) {
    return 'تسجيل الدخول بـ $label';
  }

  @override
  String settingsBiometricLoginSubtitle(String label) {
    return 'سجّل الدخول باستخدام $label بدلاً من كلمة المرور';
  }

  @override
  String biometricRememberMeRequired(String label) {
    return 'الرجاء تسجيل الدخول مرة واحدة مع تفعيل \"تذكرني\" قبل تفعيل تسجيل الدخول بـ $label.';
  }

  @override
  String biometricConfirmToEnable(String label) {
    return 'أكّد $label لتفعيله لتسجيل الدخول';
  }

  @override
  String get settingsCurrency => 'العملة';

  @override
  String get settingsCurrencySubtitle => 'اختر عملة التطبيق';

  @override
  String get settingsDecimals => 'الخانات العشرية للمبالغ';

  @override
  String get settingsDecimalsSubtitle => 'خصص عدد الخانات العشرية';

  @override
  String get settingsVat => 'نسبة ضريبة القيمة المضافة';

  @override
  String get settingsVatSubtitle => 'حدد نسبة ضريبة القيمة المضافة للتطبيق';

  @override
  String get settingsInactiveDays => 'أيام الحسابات غير النشطة';

  @override
  String get settingsInactiveDaysSubtitle => 'حدد عدد أيام الحساب غير النشط';

  @override
  String get settingsSortType => 'نوع الترتيب';

  @override
  String get settingsSortTypeSubtitle => 'اختيار الترتيب الافتراضي للتطبيق';

  @override
  String get settingsDefaultDateRange => 'المدة الزمنية الافتراضية';

  @override
  String get settingsDefaultDateRangeSubtitle =>
      'اختر الفترة الافتراضية للتقارير';

  @override
  String get settingsAgeingConfig => 'إعدادات تقادم المستحقات';

  @override
  String get settingsAgeingConfigSubtitle => 'خصص فترات تقادم المستحقات';

  @override
  String get settingsItemCriteria => 'الأصناف السريعة/البطيئة/غير النشطة';

  @override
  String get settingsItemCriteriaSubtitle =>
      'خصص معايير الأصناف السريعة والبطيئة وغير النشطة';

  @override
  String get commonSearch => 'بحث';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonOk => 'موافق';

  @override
  String get commonNoRecordsFound => 'لا توجد سجلات';

  @override
  String dialogCurrentTheme(String value) {
    return 'المظهر الحالي: $value';
  }

  @override
  String dialogCurrentLanguage(String value) {
    return 'اللغة الحالية: $value';
  }

  @override
  String dialogCurrentValuePercent(String value) {
    return 'القيمة الحالية: $value%';
  }

  @override
  String dialogCurrentValueDays(String value) {
    return 'القيمة الحالية: $value يوم';
  }

  @override
  String dialogSelected(String value) {
    return 'المحدد: $value';
  }

  @override
  String get themeSystemDefault => 'افتراضي النظام';

  @override
  String get themeLightMode => 'الوضع الفاتح';

  @override
  String get themeDarkMode => 'الوضع الداكن';

  @override
  String get vatFieldLabel => 'ضريبة القيمة المضافة (%)';

  @override
  String get vatFieldHint => 'أدخل نسبة ضريبة القيمة المضافة';

  @override
  String get vatValidation => 'الرجاء إدخال نسبة ضريبة القيمة المضافة';

  @override
  String get inactiveDaysFieldLabel => 'عدد الأيام';

  @override
  String get inactiveDaysFieldHint => 'أدخل عدد الأيام';

  @override
  String get inactiveDaysValidation => 'الرجاء إدخال عدد الأيام';

  @override
  String get dateRangeDialogTitle => 'اختر المدة الزمنية';

  @override
  String get dateRangeToday => 'اليوم';

  @override
  String get dateRangeYesterday => 'أمس';

  @override
  String get dateRangeThisMonth => 'هذا الشهر';

  @override
  String get dateRangeLastMonth => 'الشهر الماضي';

  @override
  String get dateRangeThisYear => 'هذا العام';

  @override
  String get dateRangeLastYear => 'العام الماضي';

  @override
  String get dateRangeYearToDate => 'منذ بداية العام';

  @override
  String decimalOption(int value) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'خانات عشرية',
      one: 'خانة عشرية',
    );
    return '$value $_temp0';
  }

  @override
  String get sortDialogTitle => 'خيارات الترتيب';

  @override
  String get sortDefault => 'الافتراضي';

  @override
  String get sortNewestToOldest => 'الأحدث إلى الأقدم';

  @override
  String get sortOldestToNewest => 'الأقدم إلى الأحدث';

  @override
  String get sortAToZ => 'أ->ي';

  @override
  String get sortZToA => 'ي->أ';

  @override
  String get sortAmountHighToLow => 'المبلغ من الأعلى إلى الأقل';

  @override
  String get sortAmountLowToHigh => 'المبلغ من الأقل إلى الأعلى';

  @override
  String get currencyUSD => 'دولار أمريكي';

  @override
  String get currencyAED => 'درهم إماراتي';

  @override
  String get currencyINR => 'روبية هندية';

  @override
  String get currencyPKR => 'روبية باكستانية';

  @override
  String get currencyEUR => 'يورو';

  @override
  String get currencyLKR => 'روبية سريلانكية';

  @override
  String get currencySAR => 'ريال سعودي';

  @override
  String get currencyOMR => 'ريال عماني';

  @override
  String get currencyBHD => 'دينار بحريني';

  @override
  String get currencyQAR => 'ريال قطري';

  @override
  String get currencyKWD => 'دينار كويتي';

  @override
  String get currencySLE => 'ليون سيراليوني';

  @override
  String get commonNo => 'لا';

  @override
  String get commonYes => 'نعم';

  @override
  String get commonUnknown => 'غير معروف';

  @override
  String get commonGotIt => 'فهمت';

  @override
  String get dateRangeCustomDate => 'تاريخ مخصص';

  @override
  String get dashEntryTypeTitle => 'نوع القيد';

  @override
  String get dashEntryTypeSubtitle =>
      'اختر نوع المعاملة التي تريد المتابعة بها.';

  @override
  String get dashEntrySales => 'المبيعات';

  @override
  String get dashEntryReceipts => 'المقبوضات';

  @override
  String get dashEntrySalesOrder => 'أمر بيع';

  @override
  String get dashEntryDeliveryNote => 'إشعار تسليم';

  @override
  String get dashExitTitle => 'تأكيد الخروج';

  @override
  String get dashExitBody => 'هل تريد الخروج فعلاً؟';

  @override
  String get errorFetchingData => 'حدث خطأ أثناء جلب البيانات!!!';

  @override
  String get errorSomethingWentWrong => 'حدث خطأ ما!!!';

  @override
  String get infoSwipeDownToRefresh => 'اسحب للأسفل لتحديث البيانات';

  @override
  String get licenseExpiredTitle => 'انتهت صلاحية الترخيص';

  @override
  String get licenseSerialNo => 'الرقم التسلسلي:';

  @override
  String get licenseExpiredOn => 'انتهت في:';

  @override
  String get licenseExpiredMessage =>
      'لقد انتهت صلاحية ترخيصك. لتجديد وصولك، يرجى التواصل مع فريق الدعم أدناه:';

  @override
  String licenseDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أيام',
      one: 'يوم',
    );
    return 'متبقي $count $_temp0';
  }

  @override
  String get licenseExpiresTodayTitle => 'ينتهي الترخيص اليوم';

  @override
  String get licenseExpiringSoonTitle => 'الترخيص على وشك الانتهاء';

  @override
  String get licenseExpiresLabel => 'ينتهي:';

  @override
  String get licenseExpiresOnLabel => 'ينتهي في:';

  @override
  String get licenseExpiresTodayMessage =>
      'ينتهي ترخيصك اليوم. لتجديد وصولك، يرجى التواصل مع فريق الدعم أدناه:';

  @override
  String get licenseExpiringSoonMessage =>
      'سينتهي ترخيصك قريباً. لتجديد وصولك، يرجى التواصل مع فريق الدعم أدناه:';

  @override
  String get tileSalesCreditNote => 'المبيعات - إشعار دائن';

  @override
  String get tilePurchaseDebitNote => 'المشتريات - إشعار مدين';

  @override
  String get tileReceipt => 'سند قبض';

  @override
  String get tilePayment => 'سند صرف';

  @override
  String get tileOutstandingReceivable => 'المستحقات المدينة';

  @override
  String get tileOutstandingPayable => 'المستحقات الدائنة';

  @override
  String get tileCashBankBalance => 'رصيد النقد / البنك';

  @override
  String get dashAnalyticsTitle => 'التحليلات';

  @override
  String get dashAnalyticsSubtitle =>
      'افتح رؤى الرسوم البيانية واتجاهات الحركة';

  @override
  String get dashNoAccessTitle => 'لا يوجد وصول إلى لوحة التحكم';

  @override
  String get dashNoAccessBody =>
      'يرجى التواصل مع المسؤول لتفعيل الوصول إلى لوحة التحكم.';

  @override
  String get numberScaleTooltip => 'مقياس الأرقام';

  @override
  String get numberScaleFull => 'القيمة الكاملة';

  @override
  String get numberScaleThousands => 'بالآلاف';

  @override
  String get numberScaleMillions => 'بالملايين';

  @override
  String get numberScaleBillions => 'بالمليارات';

  @override
  String get dashWelcome => 'مرحباً';

  @override
  String dashWelcomeName(String name) {
    return 'مرحباً، $name';
  }

  @override
  String get dashHeaderSubtitle => 'رؤى أعمالك جاهزة الآن';

  @override
  String get dashReportPeriod => 'فترة التقرير';
}
