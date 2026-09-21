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

  // ── Splash ────────────────────────────────────────────────────────────────
  String get driverAppTitle    => _t('FluTour Driver', 'فلوتور - سائق');

  // ── Google Sign-In ────────────────────────────────────────────────────────
  String get continueWithGoogle => _t('Continue with Google', 'المتابعة بواسطة Google');
  String get signedInWithGoogle => _t('Signed in with Google', 'تم الدخول بواسطة Google');

  // ── Registration ──────────────────────────────────────────────────────────
  String get addProfilePhoto    => _t('Add profile photo', 'إضافة صورة الملف الشخصي');
  String get vehiclePhoto       => _t('Vehicle Photo', 'صورة المركبة');
  String get vehiclePhotoHint   => _t('Photo of your felucca or carriage (shown to passengers)', 'صورة فلوكتك أو عربتك (تُعرض للركاب)');
  String get tapToAddVehiclePhoto => _t('Tap to add vehicle photo', 'اضغط لإضافة صورة المركبة');
  String get optionalRecommended => _t('(optional but recommended)', '(اختياري لكن مُوصى به)');
  String get driverLicensePhoto => _t('Driver License Photo', 'صورة رخصة القيادة');
  String get licensePhotoHint   => _t('Required for admin approval — front side of license', 'مطلوب لموافقة الإدارة — الوجه الأمامي للرخصة');
  String get tapToAddLicensePhoto => _t('Tap to upload license photo', 'اضغط لتحميل صورة الرخصة');
  String get licensePhotoRequired => _t('(required — admin will review before approval)', '(مطلوب — الإدارة ستراجع قبل الموافقة)');
  String get createPasswordHint => _t('Create a password (min 6 characters)', 'أنشئ كلمة مرور (6 أحرف على الأقل)');
  String get reenterPasswordHint => _t('Re-enter your password', 'أعد إدخال كلمة المرور');
  String get passwordsDoNotMatch => _t('Passwords do not match', 'كلمات المرور غير متطابقة');
  String get photosUploadFailed => _t('Photos failed to upload — update them from your profile later.', 'فشل تحميل الصور — يمكنك تحديثها من ملفك الشخصي لاحقاً.');
  String get applicationSubmitted => _t('Application Submitted!', 'تم تقديم الطلب!');
  String pendingApprovalBody(String name) => isArabic
      ? 'مرحباً $name، طلبك قيد المراجعة.\n\nستتم الموافقة على حسابك خلال 1-2 أيام عمل. ستتلقى إشعاراً عند الموافقة.'
      : 'Hi $name, your registration is under review.\n\nAdmin will approve your account within 1–2 business days. You\'ll be notified once approved.';
  String get pendingDocsReady   => _t('Have your licence and insurance documents ready. Admin may contact you for verification.', 'احرص على توفر رخصتك ووثائق التأمين. قد تتصل بك الإدارة للتحقق.');
  String get backToLogin        => _t('Back to Login', 'العودة لتسجيل الدخول');

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  String get navRequests        => _t('Requests', 'الطلبات');

  // ── Dashboard ─────────────────────────────────────────────────────────────
  String get tapToGoOffline     => _t('Tap to go offline', 'اضغط للتوقف عن العمل');
  String get tapToStartAccepting => _t('Tap to start accepting rides', 'اضغط لبدء قبول الرحلات');
  String get todaySummary       => _t("Today's Summary", 'ملخص اليوم');
  String get tripsToday         => _t('Trips Today', 'رحلات اليوم');
  String get earnedToday        => _t('Earned Today', 'ربح اليوم');
  String get rating             => _t('Rating', 'التقييم');

  // ── Offers ────────────────────────────────────────────────────────────────
  String get makeOffer          => _t('Make Offer', 'تقديم عرض');
  String get sendFareOffer      => _t('Send Fare Offer', 'إرسال عرض السعر');
  String get passengerOffered   => _t('Passenger offered:', 'عرض الراكب:');
  String get yourFareOffer      => _t('Your fare offer (EGP):', 'عرضك للسعر (ج.م):');
  String get enterYourFare      => _t('Enter your fare', 'أدخل سعرك');
  String get passengerWillChoose => _t('Passenger will choose from driver offers', 'سيختار الراكب من عروض السائقين');
  String get sendOffer          => _t('Send Offer', 'إرسال العرض');
  String get offerSent          => _t('Offer sent! Waiting for passenger to accept.', 'تم إرسال العرض! في انتظار موافقة الراكب.');
  String get offerSentWaiting   => _t('Offer sent! Waiting for passenger to choose.', 'تم إرسال العرض! في انتظار اختيار الراكب.');
  String get failedToSendOffer  => _t('Failed to send offer', 'فشل إرسال العرض');

  // ── Error / Status ────────────────────────────────────────────────────────
  String get couldNotLoadRequests => _t('Could not load requests', 'تعذر تحميل الطلبات');
  String get couldNotLoadHistory  => _t('Could not load trip history', 'تعذر تحميل سجل الرحلات');
  String get couldNotLoadEarnings => _t('Could not load earnings', 'تعذر تحميل الأرباح');
  String get couldNotLoadProfile  => _t('Could not load profile', 'تعذر تحميل الملف الشخصي');
  String get updateFailed         => _t('Update failed', 'فشل التحديث');

  // ── Active Ride ───────────────────────────────────────────────────────────
  String get refuseTrip         => _t('Refuse Trip?', 'رفض الرحلة؟');
  String get refuseTripConfirm  => _t('Are you sure you want to refuse this trip? It will be cancelled and the passenger will be notified.', 'هل أنت متأكد من رفض هذه الرحلة؟ ستُلغى وسيتم إخطار الراكب.');
  String get no                 => _t('No', 'لا');
  String get yesRefuse          => _t('Yes, Refuse', 'نعم، رفض');
  String get selectReason       => _t('Select a reason:', 'اختر سبباً:');
  String get reasonPassengerNotFound => _t('Passenger not found', 'الراكب غير موجود');
  String get reasonVehicleIssue => _t('Vehicle issue', 'مشكلة في المركبة');
  String get reasonEmergency    => _t('Emergency', 'طارئ');
  String get reasonPassengerRequest => _t('Passenger request', 'طلب الراكب');
  String get reasonOther        => _t('Other', 'أخرى');
  String get completeTrip       => _t('Complete Trip', 'إنهاء الرحلة');
  String get paymentReceivedComplete => _t('Payment Received — Complete Trip', 'تم استلام الدفع — إنهاء الرحلة');
  String get doneBackToHome     => _t('Done — Back to Home', 'تم — العودة للرئيسية');
  String get leaveComment       => _t('Leave a comment (optional)', 'اترك تعليقاً (اختياري)');
  String get skip               => _t('Skip', 'تخطي');

  // ── Earnings ──────────────────────────────────────────────────────────────
  String get vehicle            => _t('Vehicle', 'المركبة');
  String get todayTripsLabel    => _t('Today\nTrips', 'رحلات\nاليوم');
  String get todayEarnedLabel   => _t('Today\nEarned', 'ربح\nاليوم');
  String get noEarningsToWithdraw => _t('No earnings to withdraw.', 'لا يوجد رصيد للسحب.');
  String get instapayMissing    => _t('InstaPay number missing', 'رقم إنستاباي مفقود');
  String get instapayMissingBody => _t('You have not set your InstaPay number yet.\n\nGo to your Profile tab and add your InstaPay number to enable withdrawals.', 'لم تقم بإعداد رقم إنستاباي بعد.\n\nاذهب إلى تبويب الملف الشخصي وأضف رقم إنستاباي لتفعيل السحب.');
  String get withdrawViaInstapay => _t('Withdraw via InstaPay', 'السحب عبر إنستاباي');
  String get amountLabel        => _t('Amount:', 'المبلغ:');
  String get willBeSentTo       => _t('Will be sent to:', 'سيُرسل إلى:');
  String get instapayTransferNote => _t('The admin will transfer your earnings to this InstaPay number within 24 hours.', 'ستحول الإدارة أرباحك إلى رقم إنستاباي هذا خلال 24 ساعة.');
  String get confirmWithdrawal  => _t('Confirm Withdrawal', 'تأكيد السحب');
  String get withdrawalSubmitted => _t('Withdrawal request submitted. You will be paid via InstaPay within 24 hours.', 'تم تقديم طلب السحب. ستحصل على أرباحك عبر إنستاباي خلال 24 ساعة.');
  String get failedToSubmitRequest => _t('Failed to submit request. Please try again.', 'فشل تقديم الطلب. يرجى المحاولة مرة أخرى.');
  String get cashCommission     => _t('Cash Trip Commission (15%)', 'عمولة الرحلات النقدية (15%)');
  String get cashCommissionNote => _t('For cash trips, please send 15% of each fare to admin via InstaPay:', 'للرحلات النقدية، يرجى إرسال 15% من كل أجرة إلى الإدارة عبر إنستاباي:');
  String get recentWithdrawals  => _t('Recent Withdrawal Requests', 'طلبات السحب الأخيرة');
  String get paid               => _t('Paid', 'مدفوع');
  String get pendingStatus      => _t('Pending', 'معلق');

  // ── Profile ───────────────────────────────────────────────────────────────
  String get photoUpdated       => _t('Photo updated!', 'تم تحديث الصورة!');
  String get failedToSave       => _t('Failed to save. Try again.', 'فشل الحفظ. حاول مرة أخرى.');
  String get instapayNote       => _t('Passengers will send payment to this number', 'سيرسل الركاب الدفع إلى هذا الرقم');
  String get account            => _t('Account', 'الحساب');
  String get changePassword     => _t('Change Password', 'تغيير كلمة المرور');
  String get fullName           => _t('Full Name', 'الاسم الكامل');
  String get currentPassword    => _t('Current Password', 'كلمة المرور الحالية');
  String get newPasswordLabel   => _t('New Password (min 6 chars)', 'كلمة المرور الجديدة (6 أحرف على الأقل)');
  String get updateBtn          => _t('Update', 'تحديث');
  String get passwordUpdated    => _t('Password updated!', 'تم تحديث كلمة المرور!');
  String get wrongCurrentPassword => _t('Current password is incorrect', 'كلمة المرور الحالية غير صحيحة');
  String get driverSupportTeam  => _t('Driver support team', 'فريق دعم السائقين');

  // ── Trip Request Notification ─────────────────────────────────────────────
  String get requestTimedOut    => _t('Request timed out — auto declined', 'انتهت مهلة الطلب — تم الرفض تلقائياً');
  String get failedToSubmitOffer => _t('Failed to submit offer. Please try again.', 'فشل تقديم العرض. يرجى المحاولة مرة أخرى.');
  String get requestDeclined    => _t('Request declined', 'تم رفض الطلب');
  String get suggestYourFare    => _t('Suggest Your Fare', 'اقترح سعرك');
  String get enterFareOffer     => _t('Enter your fare offer (EGP):', 'أدخل عرض سعرك (ج.م):');
  String get expiringSoon       => _t('Expiring soon!', 'تنتهي قريباً!');
  String get secondsRemaining   => _t('Seconds remaining', 'ثوانٍ متبقية');
  String get passengerOffer     => _t('Passenger Offer', 'عرض الراكب');
  String get counterOffer       => _t('Counter', 'عرض مضاد');
  String get egpFare            => _t('EGP (fare)', 'جنيه (الأجرة)');
  String get egpAfterCommission => _t('EGP (after 20% commission)', 'جنيه (بعد عمولة 20٪)');
  String get day6Ago            => _t('6d', '6أ');
  String get day5Ago            => _t('5d', '5أ');
  String get day4Ago            => _t('4d', '4أ');
  String get day3Ago            => _t('3d', '3أ');
  String get day2Ago            => _t('2d', '2أ');
  String get yesterday          => _t('Yest', 'أمس');
  String get today              => _t('Today', 'اليوم');
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
