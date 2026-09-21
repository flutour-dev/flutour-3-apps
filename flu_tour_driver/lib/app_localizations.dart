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
  String get findingRoute      => _t('Finding route...', 'جاري البحث عن المسار...');

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

  // ── Driver Dashboard ──────────────────────────────────────────────────────
  String get driverDashboard   => _t('Driver Dashboard', 'لوحة تحكم السائق');
  String get goOnline          => _t('Go Online', 'تفعيل الخدمة');
  String get goOffline         => _t('Go Offline', 'إيقاف الخدمة');
  String get youAreOnline      => _t('You are Online', 'أنت متاح');
  String get youAreOffline     => _t('You are Offline', 'أنت غير متاح');
  String get tripRequests      => _t('Trip Requests', 'طلبات الرحلات');
  String get earnings          => _t('Earnings', 'الأرباح');
  String get today             => _t('Today', 'اليوم');
  String get thisWeek          => _t('This Week', 'هذا الأسبوع');
  String get noRequests        => _t('No trip requests right now', 'لا توجد طلبات رحلات الآن');
  String get newTripRequest    => _t('New Trip Request', 'طلب رحلة جديد');
  String get accept            => _t('Accept', 'قبول');
  String get decline           => _t('Decline', 'رفض');

  // ── Active Trip ───────────────────────────────────────────────────────────
  String get activeRide        => _t('Active Ride', 'رحلة نشطة');
  String get headingToPickup   => _t('Heading to Pickup', 'في الطريق لنقطة الانطلاق');
  String get arrivedAtPickup   => _t('Arrived at Pickup', 'وصلت لنقطة الانطلاق');
  String get tripInProgress    => _t('Trip in Progress', 'الرحلة جارية');
  String get tripCompletedLabel => _t('Trip Completed', 'تمت الرحلة');
  String get nextStep          => _t('Next Step', 'الخطوة التالية');
  String get tripComplete      => _t('Trip Complete!', 'اكتملت الرحلة!');
  String get earningsForTrip   => _t('Earnings for this trip:', 'أرباح هذه الرحلة:');
  String get yourShare         => _t('Your share (85%):', 'حصتك (85%):');
  String get backToDashboard   => _t('Back to Dashboard', 'العودة للوحة التحكم');
  String get eta               => _t('ETA', 'وقت الوصول');

  // ── Driver Profile ─────────────────────────────────────────────────────────
  String get myVehicle         => _t('My Vehicle', 'مركبتي');
  String get approvalStatus    => _t('Approval Status', 'حالة الموافقة');
  String get approved          => _t('Approved', 'تم الموافقة');
  String get pendingApproval   => _t('Pending Approval', 'في انتظار الموافقة');
  String get registerAsDriver  => _t('Register as Driver', 'تسجيل كسائق');
  String get vehicleType       => _t('Vehicle Type', 'نوع المركبة');

  // ── Driver Login / Register ───────────────────────────────────────────────
  String get driverLogin        => _t('Driver Login', 'تسجيل دخول السائق');
  String get signInToStart      => _t('Sign in to start accepting rides', 'سجّل دخولك لبدء قبول الرحلات');
  String get login              => _t('Login', 'تسجيل الدخول');
  String get newDriverRegister  => _t('New driver? Register here', 'سائق جديد؟ سجّل هنا');
  String get vehicleId          => _t('Vehicle ID', 'رقم المركبة');
  String get vehicleIdHint      => _t('e.g. F072 or H062', 'مثال: F072 أو H062');
  String get getStarted         => _t('Get Started', 'ابدأ الآن');
  String get yourRideEarnings   => _t('Your ride, your earnings', 'رحلتك، أرباحك');
  String get enterPhonePassword => _t('Please enter phone number and password', 'يرجى إدخال رقم الهاتف وكلمة المرور');
  String get passwordMin6       => _t('Password must be at least 6 characters', 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
  String get fillAllFields      => _t('Please fill all fields', 'يرجى ملء جميع الحقول');
  String get phoneAlreadyReg    => _t('Phone number already registered', 'رقم الهاتف مسجّل بالفعل');
  String get pendingApprovalMsg => _t('Your account is pending admin approval', 'حسابك في انتظار موافقة الإدارة');
  String get instapayNumber     => _t('InstaPay Number', 'رقم إنستاباي');
  String get instapayNumberSaved => _t('InstaPay number saved', 'تم حفظ رقم إنستاباي');
  String get callPassenger      => _t('Call Passenger', 'الاتصال بالراكب');
  String get call               => _t('Call', 'اتصال');
  String get online             => _t('Online', 'متصل');
  String get offline            => _t('Offline', 'غير متصل');
  String get tripAccepted       => _t('Trip Accepted!', 'تم قبول الرحلة!');
  String get tripDeclined       => _t('Trip Declined', 'تم رفض الرحلة');
  String get profileTitle       => _t('My Profile', 'ملفي الشخصي');
  String get withdrawBalance    => _t('Withdraw Balance', 'سحب الرصيد');
  String get egpBalance         => _t('Balance', 'الرصيد');

  // ── Active Trip (hardcoded strings to localize) ───────────────────────────
  String get navigateToPassenger => _t('Navigate to Passenger', 'الانتقال إلى الراكب');
  String get navigateToDestination => _t('Navigate to Destination', 'الانتقال إلى الوجهة');
  String get arrivedAtPassenger => _t('Arrived at Pickup', 'وصلت لنقطة الانطلاق');
  String get startTrip         => _t('Start Trip', 'بدء الرحلة');
  String get endTrip           => _t('End Trip', 'إنهاء الرحلة');
  String get cancelTrip        => _t('Cancel Trip', 'إلغاء الرحلة');
  String get cancelTripTitle   => _t('Cancel Trip?', 'إلغاء الرحلة؟');
  String get keepTrip          => _t('Keep Trip', 'متابعة الرحلة');
  String get ratePassenger     => _t('Rate Passenger', 'تقييم الراكب');
  String get howWasPassenger   => _t('How was your passenger?', 'كيف كان الراكب؟');
  String get submitRating      => _t('Submit Rating', 'إرسال التقييم');
  String get rideRequests      => _t('Ride Requests', 'طلبات الرحلات');
  String get thisMonth         => _t('This Month', 'هذا الشهر');
  String get thisPeriod        => _t('This Period', 'هذه الفترة');
  String get last7Days         => _t('Last 7 Days', 'آخر 7 أيام');
  String get withdrawEarnings  => _t('Withdraw Earnings', 'سحب الأرباح');
  String get contactSupport    => _t('Contact Support', 'التواصل مع الدعم');
  String get emailSupport      => _t('Email support', 'دعم البريد الإلكتروني');
  String get close             => _t('Close', 'إغلاق');
  String get fare              => _t('Fare', 'الأجرة');
  String get newRideRequest    => _t('New Ride Request!', 'طلب رحلة جديد!');
  String get yourLocation      => _t('Your Location', 'موقعك');
  String get sendMessage       => _t('Send', 'إرسال');
  String get typeMessage       => _t('Type a message...', 'اكتب رسالة...');
  String get chat              => _t('Chat', 'محادثة');
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
