// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navItems => 'Items';

  @override
  String get navParties => 'Parties';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navEntries => 'Entries';

  @override
  String get navMore => 'More...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsHeaderTitle => 'App Preferences';

  @override
  String get settingsHeaderSubtitle =>
      'Manage defaults for reports, values, and item criteria.';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionDefaults => 'Defaults';

  @override
  String get settingsSectionConfigurations => 'Configurations';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSubtitle => 'Choose system, light, or dark mode';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Choose app language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageArabic => 'العربية';

  @override
  String settingsBiometricLogin(String label) {
    return '$label login';
  }

  @override
  String settingsBiometricLoginSubtitle(String label) {
    return 'Sign in using $label instead of your password';
  }

  @override
  String biometricRememberMeRequired(String label) {
    return 'Please log in once with \"Remember me\" checked before enabling $label login.';
  }

  @override
  String biometricConfirmToEnable(String label) {
    return 'Confirm $label to enable it for sign in';
  }

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsCurrencySubtitle => 'Select currency for the app';

  @override
  String get settingsDecimals => 'Amount in Decimals';

  @override
  String get settingsDecimalsSubtitle => 'Customize number of decimal points';

  @override
  String get settingsVat => 'VAT Percentage';

  @override
  String get settingsVatSubtitle => 'Set VAT percentage for the app';

  @override
  String get settingsInactiveDays => 'Inactive Parties Days';

  @override
  String get settingsInactiveDaysSubtitle => 'Set no. of inactive party days';

  @override
  String get settingsSortType => 'Sort Type';

  @override
  String get settingsSortTypeSubtitle =>
      'Default sorting selection for the app';

  @override
  String get settingsDefaultDateRange => 'Default Date Range';

  @override
  String get settingsDefaultDateRangeSubtitle => 'Select default report period';

  @override
  String get settingsAgeingConfig => 'Ageing Configuration';

  @override
  String get settingsAgeingConfigSubtitle => 'Customize ageing range';

  @override
  String get settingsItemCriteria => 'Fast/Slow/Inactive Items';

  @override
  String get settingsItemCriteriaSubtitle =>
      'Customize Fast/Slow/Inactive Items Criteria';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonOk => 'OK';

  @override
  String get commonNoRecordsFound => 'No records found';

  @override
  String dialogCurrentTheme(String value) {
    return 'Current theme: $value';
  }

  @override
  String dialogCurrentLanguage(String value) {
    return 'Current language: $value';
  }

  @override
  String dialogCurrentValuePercent(String value) {
    return 'Current value: $value%';
  }

  @override
  String dialogCurrentValueDays(String value) {
    return 'Current value: $value days';
  }

  @override
  String dialogSelected(String value) {
    return 'Selected: $value';
  }

  @override
  String get themeSystemDefault => 'System default';

  @override
  String get themeLightMode => 'Light mode';

  @override
  String get themeDarkMode => 'Dark mode';

  @override
  String get vatFieldLabel => 'VAT (%)';

  @override
  String get vatFieldHint => 'Enter VAT (%)';

  @override
  String get vatValidation => 'Please enter VAT (%)';

  @override
  String get inactiveDaysFieldLabel => 'Day(s)';

  @override
  String get inactiveDaysFieldHint => 'Enter number of day(s)';

  @override
  String get inactiveDaysValidation => 'Please enter day(s)';

  @override
  String get dateRangeDialogTitle => 'Select Date Range';

  @override
  String get dateRangeToday => 'Today';

  @override
  String get dateRangeYesterday => 'Yesterday';

  @override
  String get dateRangeThisMonth => 'This Month';

  @override
  String get dateRangeLastMonth => 'Last Month';

  @override
  String get dateRangeThisYear => 'This Year';

  @override
  String get dateRangeLastYear => 'Last Year';

  @override
  String get dateRangeYearToDate => 'Year To Date';

  @override
  String decimalOption(int value) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'Decimals',
      one: 'Decimal',
    );
    return '$value $_temp0';
  }

  @override
  String get sortDialogTitle => 'Sort Options';

  @override
  String get sortDefault => 'Default';

  @override
  String get sortNewestToOldest => 'Newest to Oldest';

  @override
  String get sortOldestToNewest => 'Oldest to Newest';

  @override
  String get sortAToZ => 'A->Z';

  @override
  String get sortZToA => 'Z->A';

  @override
  String get sortAmountHighToLow => 'Amount High to Low';

  @override
  String get sortAmountLowToHigh => 'Amount Low to High';

  @override
  String get currencyUSD => 'US Dollar';

  @override
  String get currencyAED => 'UAE Dirhams';

  @override
  String get currencyINR => 'Indian Rupees';

  @override
  String get currencyPKR => 'Pakistani Rupees';

  @override
  String get currencyEUR => 'Euro';

  @override
  String get currencyLKR => 'SriLankan Rupees';

  @override
  String get currencySAR => 'Saudi Riyal';

  @override
  String get currencyOMR => 'Omani Riyal';

  @override
  String get currencyBHD => 'Bahraini Dinar';

  @override
  String get currencyQAR => 'Qatari Riyal';

  @override
  String get currencyKWD => 'Kuwaiti Dinar';

  @override
  String get currencySLE => 'Sierra Leonean Leone';

  @override
  String get commonNo => 'No';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get dateRangeCustomDate => 'Custom Date';

  @override
  String get dashEntryTypeTitle => 'Entry Type';

  @override
  String get dashEntryTypeSubtitle =>
      'Choose the transaction entry you want to continue.';

  @override
  String get dashEntrySales => 'Sales';

  @override
  String get dashEntryReceipts => 'Receipts';

  @override
  String get dashEntrySalesOrder => 'Sales Order';

  @override
  String get dashEntryDeliveryNote => 'Delivery Note';

  @override
  String get dashExitTitle => 'Exit Confirmation';

  @override
  String get dashExitBody => 'Do you really want to Exit?';

  @override
  String get errorFetchingData => 'Error in data fetching!!!';

  @override
  String get errorSomethingWentWrong => 'Something went wrong!!!';

  @override
  String get infoSwipeDownToRefresh => 'Swipe Down to Refresh Data';

  @override
  String get licenseExpiredTitle => 'License Expired';

  @override
  String get licenseSerialNo => 'Serial No:';

  @override
  String get licenseExpiredOn => 'Expired on:';

  @override
  String get licenseExpiredMessage =>
      'Your license has expired. To renew your access, please contact our support team below:';

  @override
  String licenseDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$count $_temp0 left';
  }

  @override
  String get licenseExpiresTodayTitle => 'License Expires Today';

  @override
  String get licenseExpiringSoonTitle => 'License Expiring Soon';

  @override
  String get licenseExpiresLabel => 'Expires:';

  @override
  String get licenseExpiresOnLabel => 'Expires on:';

  @override
  String get licenseExpiresTodayMessage =>
      'Your license expires today. To renew your access, please contact our support team below:';

  @override
  String get licenseExpiringSoonMessage =>
      'Your license will expire soon. To renew your access, please contact our support team below:';

  @override
  String get tileSalesCreditNote => 'Sales - Credit Note';

  @override
  String get tilePurchaseDebitNote => 'Purchase - Debit Note';

  @override
  String get tileReceipt => 'Receipt';

  @override
  String get tilePayment => 'Payment';

  @override
  String get tileOutstandingReceivable => 'Outstanding Receivable';

  @override
  String get tileOutstandingPayable => 'Outstanding Payable';

  @override
  String get tileCashBankBalance => 'Cash / Bank Balance';

  @override
  String get dashAnalyticsTitle => 'Analytics';

  @override
  String get dashAnalyticsSubtitle => 'Open chart insights and movement trends';

  @override
  String get dashNoAccessTitle => 'No Access to Dashboard';

  @override
  String get dashNoAccessBody =>
      'Please contact your administrator to enable dashboard access.';

  @override
  String get numberScaleTooltip => 'Number scale';

  @override
  String get numberScaleFull => 'Full Value';

  @override
  String get numberScaleThousands => 'Thousands (K)';

  @override
  String get numberScaleMillions => 'Millions (M)';

  @override
  String get numberScaleBillions => 'Billions (B)';

  @override
  String get dashWelcome => 'Welcome';

  @override
  String dashWelcomeName(String name) {
    return 'Welcome, $name';
  }

  @override
  String get dashHeaderSubtitle => 'Your business insights are ready for you';

  @override
  String get dashReportPeriod => 'Report Period';
}
