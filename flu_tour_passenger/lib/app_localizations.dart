// lib/app_localizations.dart — Manual localization (no code generation needed)
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
  ];

  bool get isArabic => locale.languageCode == 'ar';

  String _t(String en, String ar) => isArabic ? ar : en;

  // ── Common ───────────────────────────────────────────────────────────────
  String get appName           => _t('FluTour', 'فلوتور');
  String get all               => _t('All', 'الكل');
  String get ok                => _t('OK', 'موافق');
  String get cancel            => _t('Cancel', 'إلغاء');
  String get retry             => _t('Retry', 'إعادة المحاولة');
  String get save              => _t('Save', 'حفظ');
  String get loading           => _t('Loading...', 'جاري التحميل...');
  String get error             => _t('Error', 'خطأ');
  String get back              => _t('Back', 'رجوع');
  String get egp               => _t('EGP', 'ج.م');
  String get from              => _t('From', 'من');
  String get to                => _t('To', 'إلى');
  String get language          => _t('Language', 'اللغة');
  String get english           => _t('English', 'الإنجليزية');
  String get arabic            => _t('Arabic', 'العربية');

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get signIn            => _t('Sign In', 'تسجيل الدخول');
  String get signOut           => _t('Sign Out', 'تسجيل الخروج');
  String get createAccount     => _t('Create Account', 'إنشاء حساب');
  String get phoneNumber       => _t('Phone Number', 'رقم الهاتف');
  String get password          => _t('Password', 'كلمة المرور');
  String get confirmPassword   => _t('Confirm Password', 'تأكيد كلمة المرور');
  String get forgotPassword    => _t('Forgot Password?', 'نسيت كلمة المرور؟');
  String get welcomeBack       => _t('Welcome Back!', 'مرحباً بعودتك!');
  String get joinFluTour       => _t('Join FluTour', 'انضم إلى فلوتور');
  String get name              => _t('Name', 'الاسم');

  // ── Tabs ─────────────────────────────────────────────────────────────────
  String get tabHome           => _t('Home', 'الرئيسية');
  String get tabBook           => _t('Book', 'حجز');
  String get tabTrips          => _t('My Trips', 'رحلاتي');
  String get tabWallet         => _t('Wallet', 'المحفظة');
  String get tabProfile        => _t('Profile', 'الملف الشخصي');

  // ── Book Ride ─────────────────────────────────────────────────────────────
  String get bookARide         => _t('Book a Ride', 'احجز رحلة');
  String get planYourRide      => _t('Plan Your Ride', 'خطط رحلتك');
  String get pickupPoint       => _t('Pickup point', 'نقطة الانطلاق');
  String get dropoffPoint      => _t('Drop off point', 'نقطة الوصول');
  String get pickupTime        => _t('Pickup Time', 'وقت الانطلاق');
  String get date              => _t('Date', 'التاريخ');
  String get findRides         => _t('Find Rides', 'ابحث عن سيارات');
  String get myLocation        => _t('My Location', 'موقعي');
  String get findingRoute          => _t('Finding route...', 'جاري البحث عن المسار...');
  String get searchPickupLocation  => _t('Search pickup location', 'ابحث عن نقطة الانطلاق');
  String get searchDropoffLocation => _t('Search drop-off location', 'ابحث عن نقطة الوصول');
  String get typeToSearch          => _t('Type to search places in Egypt...', 'اكتب للبحث في مصر...');
  String get noResultsFound        => _t('No results found', 'لا توجد نتائج');
  String get searchingPlaces       => _t('Searching...', 'جاري البحث...');
  String get enterPickupDropoff    => _t('Please enter pickup and drop-off locations', 'يرجى إدخال نقطة الانطلاق ونقطة الوصول');

  // ── Vehicle & Booking ─────────────────────────────────────────────────────
  String get selectVehicle     => _t('Select Vehicle', 'اختر المركبة');
  String get felucca           => _t('Felucca', 'فلوكة');
  String get horseCarriage     => _t('Horse Carriage', 'عربة خيول');
  String get bookNow           => _t('Book Now', 'احجز الآن');
  String get availableDrivers  => _t('Available Drivers', 'السائقون المتاحون');
  String get noDrivers         => _t('No drivers available', 'لا يوجد سائقون متاحون');

  // ── Payment ───────────────────────────────────────────────────────────────
  String get paymentMethod     => _t('Payment Method', 'طريقة الدفع');
  String get cash              => _t('Cash', 'نقدي');
  String get creditCard        => _t('Credit Card', 'بطاقة ائتمان');
  String get mobileWallet      => _t('Mobile Wallet', 'محفظة إلكترونية');
  String get pay               => _t('Pay', 'ادفع');
  String get payAtEndOfRide    => _t('Pay at end of ride', 'الدفع عند نهاية الرحلة');

  // ── Searching / Confirmed ─────────────────────────────────────────────────
  String get searchingForDriver => _t('Searching for driver...', 'جاري البحث عن سائق...');
  String get bookingConfirmed  => _t('Booking Confirmed!', 'تم تأكيد الحجز!');
  String get yourDriver        => _t('Your Driver', 'سائقك');
  String get cancelSearch      => _t('Cancel Search', 'إلغاء البحث');
  String get rideStatus        => _t('Ride Status', 'حالة الرحلة');
  String get driverOnTheWay    => _t('Driver On the Way', 'السائق في الطريق');
  String get driverArrived     => _t('Driver Arrived', 'وصل السائق');
  String get rideInProgress    => _t('Ride in Progress', 'الرحلة جارية');
  String get backToHome        => _t('Back to Home', 'العودة للرئيسية');
  String get call              => _t('Call', 'اتصال');
  String get tripComplete      => _t('Trip Complete!', 'اكتملت الرحلة!');
  String get rateYourDriver    => _t('Rate your driver', 'قيّم سائقك');
  String get submitRating      => _t('Submit Rating', 'إرسال التقييم');
  String get skip              => _t('Skip', 'تخطي');

  // ── Trips ─────────────────────────────────────────────────────────────────
  String get tripHistory       => _t('Trip History', 'تاريخ الرحلات');
  String get noTripsYet        => _t('No trips yet', 'لا توجد رحلات بعد');
  String get rateYourTrip      => _t('Rate your trip', 'قيّم رحلتك');
  String get completed         => _t('Completed', 'مكتملة');
  String get cancelled         => _t('Cancelled', 'ملغاة');
  String get inProgress        => _t('In Progress', 'جارية');

  // ── Profile ───────────────────────────────────────────────────────────────
  String get profile           => _t('Profile', 'الملف الشخصي');
  String get editProfile       => _t('Edit Profile', 'تعديل الملف الشخصي');
  String get totalRides        => _t('Total Rides', 'إجمالي الرحلات');
  String get saveChanges       => _t('Save Changes', 'حفظ التغييرات');

  // ── Wallet ────────────────────────────────────────────────────────────────
  String get wallet            => _t('Wallet', 'المحفظة');
  String get balance           => _t('Balance', 'الرصيد');
  String get topUp             => _t('Top Up', 'إضافة رصيد');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
