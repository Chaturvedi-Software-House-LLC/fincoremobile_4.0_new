import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get navItems;

  /// No description provided for @navParties.
  ///
  /// In en, this message translates to:
  /// **'Parties'**
  String get navParties;

  /// No description provided for @navTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get navTransactions;

  /// No description provided for @navEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get navEntries;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More...'**
  String get navMore;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'App Preferences'**
  String get settingsHeaderTitle;

  /// No description provided for @settingsHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage defaults for reports, values, and item criteria.'**
  String get settingsHeaderSubtitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsSectionDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get settingsSectionDefaults;

  /// No description provided for @settingsSectionConfigurations.
  ///
  /// In en, this message translates to:
  /// **'Configurations'**
  String get settingsSectionConfigurations;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose system, light, or dark mode'**
  String get settingsThemeSubtitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose app language'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get settingsLanguageArabic;

  /// No description provided for @settingsBiometricLogin.
  ///
  /// In en, this message translates to:
  /// **'{label} login'**
  String settingsBiometricLogin(String label);

  /// No description provided for @settingsBiometricLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in using {label} instead of your password'**
  String settingsBiometricLoginSubtitle(String label);

  /// No description provided for @biometricRememberMeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please log in once with \"Remember me\" checked before enabling {label} login.'**
  String biometricRememberMeRequired(String label);

  /// No description provided for @biometricConfirmToEnable.
  ///
  /// In en, this message translates to:
  /// **'Confirm {label} to enable it for sign in'**
  String biometricConfirmToEnable(String label);

  /// No description provided for @settingsCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// No description provided for @settingsCurrencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select currency for the app'**
  String get settingsCurrencySubtitle;

  /// No description provided for @settingsDecimals.
  ///
  /// In en, this message translates to:
  /// **'Amount in Decimals'**
  String get settingsDecimals;

  /// No description provided for @settingsDecimalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize number of decimal points'**
  String get settingsDecimalsSubtitle;

  /// No description provided for @settingsVat.
  ///
  /// In en, this message translates to:
  /// **'VAT Percentage'**
  String get settingsVat;

  /// No description provided for @settingsVatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set VAT percentage for the app'**
  String get settingsVatSubtitle;

  /// No description provided for @settingsInactiveDays.
  ///
  /// In en, this message translates to:
  /// **'Inactive Parties Days'**
  String get settingsInactiveDays;

  /// No description provided for @settingsInactiveDaysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set no. of inactive party days'**
  String get settingsInactiveDaysSubtitle;

  /// No description provided for @settingsSortType.
  ///
  /// In en, this message translates to:
  /// **'Sort Type'**
  String get settingsSortType;

  /// No description provided for @settingsSortTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default sorting selection for the app'**
  String get settingsSortTypeSubtitle;

  /// No description provided for @settingsDefaultDateRange.
  ///
  /// In en, this message translates to:
  /// **'Default Date Range'**
  String get settingsDefaultDateRange;

  /// No description provided for @settingsDefaultDateRangeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select default report period'**
  String get settingsDefaultDateRangeSubtitle;

  /// No description provided for @settingsAgeingConfig.
  ///
  /// In en, this message translates to:
  /// **'Ageing Configuration'**
  String get settingsAgeingConfig;

  /// No description provided for @settingsAgeingConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize ageing range'**
  String get settingsAgeingConfigSubtitle;

  /// No description provided for @settingsItemCriteria.
  ///
  /// In en, this message translates to:
  /// **'Fast/Slow/Inactive Items'**
  String get settingsItemCriteria;

  /// No description provided for @settingsItemCriteriaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize Fast/Slow/Inactive Items Criteria'**
  String get settingsItemCriteriaSubtitle;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonNoRecordsFound.
  ///
  /// In en, this message translates to:
  /// **'No records found'**
  String get commonNoRecordsFound;

  /// No description provided for @dialogCurrentTheme.
  ///
  /// In en, this message translates to:
  /// **'Current theme: {value}'**
  String dialogCurrentTheme(String value);

  /// No description provided for @dialogCurrentLanguage.
  ///
  /// In en, this message translates to:
  /// **'Current language: {value}'**
  String dialogCurrentLanguage(String value);

  /// No description provided for @dialogCurrentValuePercent.
  ///
  /// In en, this message translates to:
  /// **'Current value: {value}%'**
  String dialogCurrentValuePercent(String value);

  /// No description provided for @dialogCurrentValueDays.
  ///
  /// In en, this message translates to:
  /// **'Current value: {value} days'**
  String dialogCurrentValueDays(String value);

  /// No description provided for @dialogSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {value}'**
  String dialogSelected(String value);

  /// No description provided for @themeSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystemDefault;

  /// No description provided for @themeLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get themeLightMode;

  /// No description provided for @themeDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get themeDarkMode;

  /// No description provided for @vatFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'VAT (%)'**
  String get vatFieldLabel;

  /// No description provided for @vatFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Enter VAT (%)'**
  String get vatFieldHint;

  /// No description provided for @vatValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter VAT (%)'**
  String get vatValidation;

  /// No description provided for @inactiveDaysFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Day(s)'**
  String get inactiveDaysFieldLabel;

  /// No description provided for @inactiveDaysFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Enter number of day(s)'**
  String get inactiveDaysFieldHint;

  /// No description provided for @inactiveDaysValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter day(s)'**
  String get inactiveDaysValidation;

  /// No description provided for @dateRangeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get dateRangeDialogTitle;

  /// No description provided for @dateRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateRangeToday;

  /// No description provided for @dateRangeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateRangeYesterday;

  /// No description provided for @dateRangeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get dateRangeThisMonth;

  /// No description provided for @dateRangeLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get dateRangeLastMonth;

  /// No description provided for @dateRangeThisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get dateRangeThisYear;

  /// No description provided for @dateRangeLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last Year'**
  String get dateRangeLastYear;

  /// No description provided for @dateRangeYearToDate.
  ///
  /// In en, this message translates to:
  /// **'Year To Date'**
  String get dateRangeYearToDate;

  /// No description provided for @decimalOption.
  ///
  /// In en, this message translates to:
  /// **'{value} {value, plural, one{Decimal} other{Decimals}}'**
  String decimalOption(int value);

  /// No description provided for @sortDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort Options'**
  String get sortDialogTitle;

  /// No description provided for @sortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get sortDefault;

  /// No description provided for @sortNewestToOldest.
  ///
  /// In en, this message translates to:
  /// **'Newest to Oldest'**
  String get sortNewestToOldest;

  /// No description provided for @sortOldestToNewest.
  ///
  /// In en, this message translates to:
  /// **'Oldest to Newest'**
  String get sortOldestToNewest;

  /// No description provided for @sortAToZ.
  ///
  /// In en, this message translates to:
  /// **'A->Z'**
  String get sortAToZ;

  /// No description provided for @sortZToA.
  ///
  /// In en, this message translates to:
  /// **'Z->A'**
  String get sortZToA;

  /// No description provided for @sortAmountHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Amount High to Low'**
  String get sortAmountHighToLow;

  /// No description provided for @sortAmountLowToHigh.
  ///
  /// In en, this message translates to:
  /// **'Amount Low to High'**
  String get sortAmountLowToHigh;

  /// No description provided for @currencyUSD.
  ///
  /// In en, this message translates to:
  /// **'US Dollar'**
  String get currencyUSD;

  /// No description provided for @currencyAED.
  ///
  /// In en, this message translates to:
  /// **'UAE Dirhams'**
  String get currencyAED;

  /// No description provided for @currencyINR.
  ///
  /// In en, this message translates to:
  /// **'Indian Rupees'**
  String get currencyINR;

  /// No description provided for @currencyPKR.
  ///
  /// In en, this message translates to:
  /// **'Pakistani Rupees'**
  String get currencyPKR;

  /// No description provided for @currencyEUR.
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyEUR;

  /// No description provided for @currencyLKR.
  ///
  /// In en, this message translates to:
  /// **'SriLankan Rupees'**
  String get currencyLKR;

  /// No description provided for @currencySAR.
  ///
  /// In en, this message translates to:
  /// **'Saudi Riyal'**
  String get currencySAR;

  /// No description provided for @currencyOMR.
  ///
  /// In en, this message translates to:
  /// **'Omani Riyal'**
  String get currencyOMR;

  /// No description provided for @currencyBHD.
  ///
  /// In en, this message translates to:
  /// **'Bahraini Dinar'**
  String get currencyBHD;

  /// No description provided for @currencyQAR.
  ///
  /// In en, this message translates to:
  /// **'Qatari Riyal'**
  String get currencyQAR;

  /// No description provided for @currencyKWD.
  ///
  /// In en, this message translates to:
  /// **'Kuwaiti Dinar'**
  String get currencyKWD;

  /// No description provided for @currencySLE.
  ///
  /// In en, this message translates to:
  /// **'Sierra Leonean Leone'**
  String get currencySLE;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @dateRangeCustomDate.
  ///
  /// In en, this message translates to:
  /// **'Custom Date'**
  String get dateRangeCustomDate;

  /// No description provided for @dashEntryTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Entry Type'**
  String get dashEntryTypeTitle;

  /// No description provided for @dashEntryTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the transaction entry you want to continue.'**
  String get dashEntryTypeSubtitle;

  /// No description provided for @dashEntrySales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get dashEntrySales;

  /// No description provided for @dashEntryReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get dashEntryReceipts;

  /// No description provided for @dashEntrySalesOrder.
  ///
  /// In en, this message translates to:
  /// **'Sales Order'**
  String get dashEntrySalesOrder;

  /// No description provided for @dashEntryDeliveryNote.
  ///
  /// In en, this message translates to:
  /// **'Delivery Note'**
  String get dashEntryDeliveryNote;

  /// No description provided for @dashExitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit Confirmation'**
  String get dashExitTitle;

  /// No description provided for @dashExitBody.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to Exit?'**
  String get dashExitBody;

  /// No description provided for @errorFetchingData.
  ///
  /// In en, this message translates to:
  /// **'Error in data fetching!!!'**
  String get errorFetchingData;

  /// No description provided for @errorSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong!!!'**
  String get errorSomethingWentWrong;

  /// No description provided for @infoSwipeDownToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Swipe Down to Refresh Data'**
  String get infoSwipeDownToRefresh;

  /// No description provided for @licenseExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'License Expired'**
  String get licenseExpiredTitle;

  /// No description provided for @licenseSerialNo.
  ///
  /// In en, this message translates to:
  /// **'Serial No:'**
  String get licenseSerialNo;

  /// No description provided for @licenseExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Expired on:'**
  String get licenseExpiredOn;

  /// No description provided for @licenseExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Your license has expired. To renew your access, please contact our support team below:'**
  String get licenseExpiredMessage;

  /// No description provided for @licenseDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{day} other{days}} left'**
  String licenseDaysLeft(int count);

  /// No description provided for @licenseExpiresTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'License Expires Today'**
  String get licenseExpiresTodayTitle;

  /// No description provided for @licenseExpiringSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'License Expiring Soon'**
  String get licenseExpiringSoonTitle;

  /// No description provided for @licenseExpiresLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires:'**
  String get licenseExpiresLabel;

  /// No description provided for @licenseExpiresOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires on:'**
  String get licenseExpiresOnLabel;

  /// No description provided for @licenseExpiresTodayMessage.
  ///
  /// In en, this message translates to:
  /// **'Your license expires today. To renew your access, please contact our support team below:'**
  String get licenseExpiresTodayMessage;

  /// No description provided for @licenseExpiringSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'Your license will expire soon. To renew your access, please contact our support team below:'**
  String get licenseExpiringSoonMessage;

  /// No description provided for @tileSalesCreditNote.
  ///
  /// In en, this message translates to:
  /// **'Sales - Credit Note'**
  String get tileSalesCreditNote;

  /// No description provided for @tilePurchaseDebitNote.
  ///
  /// In en, this message translates to:
  /// **'Purchase - Debit Note'**
  String get tilePurchaseDebitNote;

  /// No description provided for @tileReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get tileReceipt;

  /// No description provided for @tilePayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get tilePayment;

  /// No description provided for @tileOutstandingReceivable.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Receivable'**
  String get tileOutstandingReceivable;

  /// No description provided for @tileOutstandingPayable.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Payable'**
  String get tileOutstandingPayable;

  /// No description provided for @tileCashBankBalance.
  ///
  /// In en, this message translates to:
  /// **'Cash / Bank Balance'**
  String get tileCashBankBalance;

  /// No description provided for @dashAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get dashAnalyticsTitle;

  /// No description provided for @dashAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open chart insights and movement trends'**
  String get dashAnalyticsSubtitle;

  /// No description provided for @dashNoAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'No Access to Dashboard'**
  String get dashNoAccessTitle;

  /// No description provided for @dashNoAccessBody.
  ///
  /// In en, this message translates to:
  /// **'Please contact your administrator to enable dashboard access.'**
  String get dashNoAccessBody;

  /// No description provided for @numberScaleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Number scale'**
  String get numberScaleTooltip;

  /// No description provided for @numberScaleFull.
  ///
  /// In en, this message translates to:
  /// **'Full Value'**
  String get numberScaleFull;

  /// No description provided for @numberScaleThousands.
  ///
  /// In en, this message translates to:
  /// **'Thousands (K)'**
  String get numberScaleThousands;

  /// No description provided for @numberScaleMillions.
  ///
  /// In en, this message translates to:
  /// **'Millions (M)'**
  String get numberScaleMillions;

  /// No description provided for @numberScaleBillions.
  ///
  /// In en, this message translates to:
  /// **'Billions (B)'**
  String get numberScaleBillions;

  /// No description provided for @dashWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get dashWelcome;

  /// No description provided for @dashWelcomeName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String dashWelcomeName(String name);

  /// No description provided for @dashHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your business insights are ready for you'**
  String get dashHeaderSubtitle;

  /// No description provided for @dashReportPeriod.
  ///
  /// In en, this message translates to:
  /// **'Report Period'**
  String get dashReportPeriod;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
