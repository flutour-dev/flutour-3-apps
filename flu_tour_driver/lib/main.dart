// lib/main.dart - FluTour Driver App
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'models.dart';
import 'database_service.dart';
import 'location_service.dart';
import 'route_service.dart';
import 'package:provider/provider.dart';
import 'app_localizations.dart';
import 'locale_provider.dart';
import 'sound_service.dart';

// Must be a top-level function — called when app is in background/terminated
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // System tray notification is shown automatically by the OS
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  await DriverAuthService.loadSession();
  final localeProvider = await LocaleProvider.load(defaultLocale: const Locale('ar'));
  runApp(
    ChangeNotifierProvider.value(
      value: localeProvider,
      child: FluTourDriverApp(),
    ),
  );
}

/// Shared declined-trip IDs — persists for the app's lifetime across all tabs and screens.
final Set<String> _driverDeclinedTripIds = {};

class FluTourDriverApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    return MaterialApp(
      title: 'FluTour Driver',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Color(0xFFF4F6F8),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      home: DriverSplashScreen(),
    );
  }
}

// ===== DRIVER AUTH SERVICE =====
class DriverAuthService {
  static String _currentDriverName = '';
  static String _currentDriverPhone = '';
  static String _currentVehicleType = '';
  static String _currentPhotoUrl = '';
  static String _tempVehicleId = '';
  static String _tempVehicleType = '';
  // Holds Google user info when they sign in without an existing driver doc
  static bool _pendingGoogleRegistration = false;
  static String _googleDisplayName = '';
  static String _googlePhotoUrl = '';

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
  static String get currentDriverId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  static String get currentDriverName => _currentDriverName;
  static String get currentDriverPhone => _currentDriverPhone;
  static String get currentVehicleType => _currentVehicleType;
  static String get currentPhotoUrl => _currentPhotoUrl;
  static bool get pendingGoogleRegistration => _pendingGoogleRegistration;
  static String get googleDisplayName => _googleDisplayName;
  static String get googlePhotoUrl => _googlePhotoUrl;

  // ── imgBB image hosting (free, no billing account needed) ────────────────
  // Get your free API key at https://api.imgbb.com — sign up takes 1 minute.
  static const _imgBBKey = 'aebd7e4dd66c443fcdb4da6cff88cf9d';

  static Future<String?> _uploadToImgBB(File file) async {
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    final resp = await http.post(
      Uri.parse('https://api.imgbb.com/1/upload'),
      body: {'key': _imgBBKey, 'image': b64},
    );
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['success'] == true) {
      return (json['data'] as Map<String, dynamic>)['url'] as String?;
    }
    return null;
  }

  static Future<String?> uploadProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked == null) return null;
      final uid = currentDriverId;
      if (uid.isEmpty) return 'Not logged in';
      final url = await _uploadToImgBB(File(picked.path));
      if (url == null) return 'Failed to upload photo';
      _currentPhotoUrl = url;
      await FirebaseFirestore.instance.collection('drivers').doc(uid).update({'photoUrl': url});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_photo', url);
      return null;
    } catch (e) {
      return 'Failed to upload photo: $e';
    }
  }

  static Future<String?> uploadVehiclePhoto(File photoFile, String uid) async {
    try {
      final url = await _uploadToImgBB(photoFile);
      if (url == null) return 'Failed to upload vehicle photo';
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .update({'vehiclePhotoUrl': url});
      return null;
    } catch (e) {
      return 'Failed to upload vehicle photo: $e';
    }
  }

  static Future<String?> uploadPersonalPhoto(File photoFile, String uid) async {
    try {
      final url = await _uploadToImgBB(photoFile);
      if (url == null) return 'Failed to upload personal photo';
      _currentPhotoUrl = url;
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .update({'photoUrl': url});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_photo', url);
      return null;
    } catch (e) {
      return 'Failed to upload personal photo: $e';
    }
  }

  static Future<String?> uploadLicensePhoto(File photoFile, String uid) async {
    try {
      final url = await _uploadToImgBB(photoFile);
      if (url == null) return 'Failed to upload license photo';
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .update({'licensePhotoUrl': url});
      return null;
    } catch (e) {
      return 'Failed to upload license: $e';
    }
  }

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDriverName = prefs.getString('driver_name') ?? '';
    _currentDriverPhone = prefs.getString('driver_phone') ?? '';
    _currentPhotoUrl = prefs.getString('driver_photo') ?? '';
    final rawType = prefs.getString('driver_vehicle_type') ?? '';
    // Always normalize — old registrations stored 'Felucca'/'Horse Carriage', new ones store 'felucca'/'horse_carriage'
    _currentVehicleType = rawType.isEmpty ? '' : VehicleTypeX.fromString(rawType).value;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('drivers').doc(user.uid).get();
        if (doc.exists) {
          _currentDriverName = doc.data()?['name'] ?? _currentDriverName;
          _currentDriverPhone = doc.data()?['phone'] ?? _currentDriverPhone;
          _currentPhotoUrl = doc.data()?['photoUrl'] ?? user.photoURL ?? _currentPhotoUrl;
          _currentVehicleType = VehicleTypeX.fromString(doc.data()?['vehicleType'] ?? _currentVehicleType).value;
          await prefs.setString('driver_name', _currentDriverName);
          await prefs.setString('driver_phone', _currentDriverPhone);
          await prefs.setString('driver_photo', _currentPhotoUrl);
          await prefs.setString('driver_vehicle_type', _currentVehicleType);
        }
      } catch (_) {}
    }
    // Load live surge multipliers from Firestore
    await FareEstimator.loadSurge();
  }

  static String _phoneToEmail(String phone) =>
      'driver.${phone.replaceAll(RegExp(r'[^0-9]'), '')}@flutour.app';

  static Future<String?> signIn(String phone, String password) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _phoneToEmail(phone), password: password);
      final doc = await FirebaseFirestore.instance
          .collection('drivers').doc(cred.user!.uid).get();
      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        return 'Driver account not found';
      }
      final status = doc.data()?['status'] ?? 'pending';
      if (status == 'pending') {
        await FirebaseAuth.instance.signOut();
        return 'Your account is pending admin approval';
      }
      if (status == 'rejected' || status == 'suspended') {
        await FirebaseAuth.instance.signOut();
        return 'Your account has been $status';
      }
      _currentDriverPhone = phone.trim();
      _currentDriverName = doc.data()?['name'] ?? 'Driver';
      _currentVehicleType = VehicleTypeX.fromString(doc.data()?['vehicleType'] ?? '').value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_name', _currentDriverName);
      await prefs.setString('driver_phone', _currentDriverPhone);
      await prefs.setString('driver_vehicle_type', _currentVehicleType);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'No account found for this phone number';
      if (e.code == 'wrong-password') return 'Incorrect password';
      return e.message ?? 'Sign in failed';
    } catch (_) {
      return 'Service unavailable. Please check your connection.';
    }
  }

  static Future<String?> register(String name, String phone, String vehicleId, String vehicleType) async {
    if (name.isEmpty || phone.isEmpty || vehicleId.isEmpty) return 'Please fill all fields';
    _currentDriverName = name;
    _currentDriverPhone = phone;
    _tempVehicleId = vehicleId;
    _tempVehicleType = vehicleType;
    return null;
  }

  static Future<String?> completeRegistration(String password) async {
    if (password.length < 6) return 'Password must be at least 6 characters';
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _phoneToEmail(_currentDriverPhone), password: password);
      await FirebaseFirestore.instance
          .collection('drivers').doc(cred.user!.uid).set({
        'name': _currentDriverName,
        'phone': _currentDriverPhone,
        'vehicleId': _tempVehicleId,
        'vehicleType': VehicleTypeX.fromString(_tempVehicleType).value,
        'status': 'pending',
        'rating': 0.0,
        'totalTrips': 0,
        'balance': 0.0,
        'photoUrl': '',
        'vehiclePhotoUrl': '',
        'licensePhotoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_name', _currentDriverName);
      await prefs.setString('driver_phone', _currentDriverPhone);
      await prefs.setString('driver_vehicle_type', _tempVehicleType);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return 'Phone number already registered';
      return e.message ?? 'Registration failed';
    } catch (e) {
      return 'Registration failed. Please check your connection and try again.';
    }
  }

  static void updateCachedProfile({String? name, String? phone}) async {
    if (name != null && name.isNotEmpty) _currentDriverName = name;
    if (phone != null && phone.isNotEmpty) _currentDriverPhone = phone;
    final prefs = await SharedPreferences.getInstance();
    if (name != null && name.isNotEmpty) await prefs.setString('driver_name', name);
    if (phone != null && phone.isNotEmpty) await prefs.setString('driver_phone', phone);
  }

  static Future<void> signOut() async {
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    _currentDriverName = '';
    _currentDriverPhone = '';
    _currentVehicleType = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('driver_name');
    await prefs.remove('driver_phone');
    await prefs.remove('driver_vehicle_type');
  }

  static Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn(
        serverClientId: '258397191065-u3e7drp1o8eft55ekjhlquf033p5qica.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = cred.user!.uid;
      final doc = await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
      if (!doc.exists) {
        // New Google user — keep them authenticated and redirect to driver registration
        _pendingGoogleRegistration = true;
        _googleDisplayName = cred.user?.displayName ?? googleUser.displayName ?? '';
        _googlePhotoUrl = cred.user?.photoURL ?? googleUser.photoUrl ?? '';
        return '__register__';
      }
      _pendingGoogleRegistration = false;
      final status = doc.data()?['status'] ?? 'pending';
      if (status == 'pending') {
        await FirebaseAuth.instance.signOut();
        return 'Your account is pending admin approval';
      }
      if (status == 'rejected' || status == 'suspended') {
        await FirebaseAuth.instance.signOut();
        return 'Your account has been $status';
      }
      _currentDriverName = doc.data()?['name'] ?? cred.user?.displayName ?? 'Driver';
      _currentDriverPhone = doc.data()?['phone'] ?? '';
      _currentVehicleType = VehicleTypeX.fromString(doc.data()?['vehicleType'] ?? '').value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_name', _currentDriverName);
      await prefs.setString('driver_phone', _currentDriverPhone);
      await prefs.setString('driver_vehicle_type', _currentVehicleType);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Google sign-in failed';
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  /// Called after a Google-signed-in user completes the driver registration form.
  static Future<String?> completeGoogleRegistration(
      String vehicleId, String vehicleType, String phone) async {
    try {
      final uid = currentDriverId;
      if (uid.isEmpty) return 'Not authenticated. Please try signing in again.';
      final name = _googleDisplayName.isNotEmpty
          ? _googleDisplayName
          : (FirebaseAuth.instance.currentUser?.displayName ?? 'Driver');
      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'name': name,
        'phone': phone,
        'vehicleId': vehicleId,
        'vehicleType': VehicleTypeX.fromString(vehicleType).value,
        'status': 'pending',
        'rating': 0.0,
        'totalTrips': 0,
        'balance': 0.0,
        'photoUrl': _googlePhotoUrl,
        'vehiclePhotoUrl': '',
        'licensePhotoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _currentDriverName = name;
      _currentDriverPhone = phone;
      _currentVehicleType = vehicleType;
      _currentPhotoUrl = _googlePhotoUrl;
      _pendingGoogleRegistration = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_name', _currentDriverName);
      await prefs.setString('driver_phone', _currentDriverPhone);
      await prefs.setString('driver_vehicle_type', _currentVehicleType);
      if (_googlePhotoUrl.isNotEmpty) {
        await prefs.setString('driver_photo', _googlePhotoUrl);
      }
      return null;
    } catch (e) {
      return 'Registration failed: $e';
    }
  }
}


// ===== 1. SPLASH SCREEN =====
class DriverSplashScreen extends StatefulWidget {
  @override
  _DriverSplashScreenState createState() => _DriverSplashScreenState();
}

class _DriverSplashScreenState extends State<DriverSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();

    // Firebase.initializeApp() in main() has already restored the persisted
    // credential — currentUser is synchronously available here.
    Future.delayed(Duration(seconds: 3), () {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => DriverHomeScreen()));
      } else {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => DriverLoginScreen()));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF00796B), Color(0xFF26A69A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white30, width: 2),
                            ),
                            child: Icon(Icons.sailing,
                                size: 70, color: Colors.white),
                          ),
                          SizedBox(height: 28),
                          Builder(builder: (context) {
                            final l = AppLocalizations.of(context);
                            return Column(
                              children: [
                                Text(
                                  l.driverAppTitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  l.yourRideEarnings,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(32),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => DriverLoginScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Builder(builder: (context) => Text(
                      AppLocalizations.of(context).getStarted,
                      style: TextStyle(
                        color: Color(0xFF004D40),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 2. LOGIN SCREEN =====
class DriverLoginScreen extends StatefulWidget {
  @override
  _DriverLoginScreenState createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).enterPhonePassword)),
      );
      return;
    }
    setState(() => _isLoading = true);
    final error = await DriverAuthService.signIn(
        _phoneController.text.trim(), _passwordController.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)));
    } else {
      // Save FCM token so Cloud Functions can send trip-request notifications
      try {
        await FirebaseMessaging.instance.requestPermission();
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && DriverAuthService.currentDriverId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(DriverAuthService.currentDriverId)
              .update({'fcmToken': token});
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => DriverHomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 30),
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child:
                          Icon(Icons.drive_eta, size: 50, color: Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(l.driverLogin,
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text(l.signInToStart,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 14)),
                  ],
                ),
              ),
              SizedBox(height: 40),
              Text(l.phoneNumber,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '01XXXXXXXXX',
                  prefixIcon:
                      Icon(Icons.phone, color: Colors.teal.shade600),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.teal.shade600, width: 2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(l.password,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon:
                      Icon(Icons.lock, color: Colors.teal.shade600),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.teal.shade600, width: 2),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              SizedBox(height: 36),
              _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: Colors.teal.shade600))
                  : SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          l.login,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              SizedBox(height: 16),
              // ── Google Sign-In ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _googleLoading ? null : () async {
                    setState(() => _googleLoading = true);
                    final error = await DriverAuthService.signInWithGoogle();
                    if (!mounted) return;
                    setState(() => _googleLoading = false);
                    if (error == '__register__') {
                      // New Google user — complete driver registration
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => DriverGoogleRegisterScreen()));
                    } else if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error)));
                    } else {
                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => DriverHomeScreen()));
                    }
                  },
                  icon: _googleLoading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.g_mobiledata, size: 26, color: Colors.red.shade700),
                  label: Text(AppLocalizations.of(context).continueWithGoogle,
                      style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => DriverRegisterScreen())),
                  child: Text(
                    l.newDriverRegister,
                    style: TextStyle(color: Colors.teal.shade700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 3. GOOGLE REGISTRATION COMPLETION SCREEN =====
// Shown when a driver signs in with Google for the first time.
// Firebase Auth is already done; this screen collects vehicle info and photos.
class DriverGoogleRegisterScreen extends StatefulWidget {
  @override
  _DriverGoogleRegisterScreenState createState() =>
      _DriverGoogleRegisterScreenState();
}

class _DriverGoogleRegisterScreenState
    extends State<DriverGoogleRegisterScreen> {
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  String _selectedType = 'Felucca';
  File? _vehiclePhoto;
  File? _licensePhoto;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final googleName = DriverAuthService.googleDisplayName;
    final googlePhoto = DriverAuthService.googlePhotoUrl;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.registerAsDriver),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () async {
            await DriverAuthService.signOut();
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  googlePhoto.isNotEmpty
                      ? CircleAvatar(
                          radius: 50,
                          backgroundImage: NetworkImage(googlePhoto),
                        )
                      : CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.teal.shade50,
                          child: Icon(Icons.person, size: 44, color: Colors.teal.shade700),
                        ),
                  SizedBox(height: 8),
                  if (googleName.isNotEmpty)
                    Text(googleName,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  Text(l.signedInWithGoogle,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 24),
            Text(l.phoneNumber,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '01XXXXXXXXX',
                prefixIcon: Icon(Icons.phone, color: Colors.teal.shade600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.vehicleId,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _vehicleController,
              decoration: InputDecoration(
                hintText: l.vehicleIdHint,
                prefixIcon: Icon(Icons.directions_boat, color: Colors.teal.shade600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.vehicleType,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            Builder(builder: (context) {
              final l = AppLocalizations.of(context);
              final vehicleTypes = [
                {'key': 'Felucca', 'label': l.felucca, 'icon': Icons.sailing},
                {'key': 'Horse Carriage', 'label': l.horseCarriage, 'icon': Icons.directions},
              ];
              return Row(
                children: vehicleTypes.asMap().entries.map((entry) {
                  final i = entry.key;
                  final vt = entry.value;
                  final selected = _selectedType == vt['key'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedType = vt['key'] as String),
                      child: Container(
                        margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? Colors.teal.shade700 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: selected
                                  ? Colors.teal.shade700
                                  : Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            Icon(vt['icon'] as IconData,
                                color: selected ? Colors.white : Colors.grey, size: 28),
                            SizedBox(height: 6),
                            Text(vt['label'] as String,
                                style: TextStyle(
                                  color: selected ? Colors.white : Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
            SizedBox(height: 16),
            Text(l.vehiclePhoto,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 4),
            Text(l.vehiclePhotoHint,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 70);
                if (picked != null) setState(() => _vehiclePhoto = File(picked.path));
              },
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _vehiclePhoto != null
                          ? Colors.teal.shade400
                          : Colors.grey.shade300,
                      width: 1.5),
                ),
                child: _vehiclePhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_vehiclePhoto!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 36, color: Colors.teal.shade300),
                          SizedBox(height: 8),
                          Text(l.tapToAddVehiclePhoto,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.driverLicensePhoto,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 4),
            Text(l.licensePhotoHint,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 80);
                if (picked != null) setState(() => _licensePhoto = File(picked.path));
              },
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _licensePhoto != null
                          ? Colors.orange.shade400
                          : Colors.grey.shade300,
                      width: 1.5),
                ),
                child: _licensePhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_licensePhoto!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 36, color: Colors.orange.shade300),
                          SizedBox(height: 8),
                          Text(l.tapToAddLicensePhoto,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 32),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () async {
                        final phone = _phoneController.text.trim();
                        final vehicle = _vehicleController.text.trim();
                        if (phone.isEmpty || vehicle.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.fillAllFields)));
                          return;
                        }
                        setState(() => _isLoading = true);
                        final regError =
                            await DriverAuthService.completeGoogleRegistration(
                                vehicle, _selectedType, phone);
                        if (!mounted) return;
                        if (regError != null) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(regError)));
                          return;
                        }
                        // Upload photos
                        final uid = DriverAuthService.currentDriverId;
                        if (uid.isNotEmpty) {
                          final uploadResults = await Future.wait([
                            if (_vehiclePhoto != null)
                              DriverAuthService.uploadVehiclePhoto(_vehiclePhoto!, uid),
                            if (_licensePhoto != null)
                              DriverAuthService.uploadLicensePhoto(_licensePhoto!, uid),
                          ]);
                          if (!mounted) return;
                          final uploadErrors =
                              uploadResults.whereType<String>().toList();
                          if (uploadErrors.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(l.photosUploadFailed),
                              duration: Duration(seconds: 6),
                            ));
                          }
                        }
                        if (!mounted) return;
                        setState(() => _isLoading = false);
                        Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DriverPendingApprovalScreen(
                                    name: DriverAuthService.googleDisplayName.isNotEmpty
                                        ? DriverAuthService.googleDisplayName
                                        : 'Driver')),
                            (_) => false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.registerAsDriver,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ===== 3. REGISTER SCREEN =====
class DriverRegisterScreen extends StatefulWidget {
  @override
  _DriverRegisterScreenState createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _selectedType = 'Felucca';
  File? _vehiclePhoto;
  File? _personalPhoto;
  File? _licensePhoto;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.registerAsDriver),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Personal photo picker
            Center(
              child: GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 80);
                  if (picked != null) {
                    setState(() => _personalPhoto = File(picked.path));
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    _personalPhoto != null
                        ? CircleAvatar(
                            radius: 50,
                            backgroundImage: FileImage(_personalPhoto!),
                          )
                        : CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.teal.shade50,
                            child: Icon(Icons.person_add,
                                size: 44, color: Colors.teal.shade700),
                          ),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.teal.shade700,
                      child: Icon(Icons.camera_alt,
                          color: Colors.white, size: 16),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 6),
            Center(
              child: Text(l.addProfilePhoto,
                  style: TextStyle(
                      color: Colors.teal.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
            SizedBox(height: 24),
            _buildField(l.name, 'Hassan Mahmoud', Icons.person,
                _nameController, TextInputType.name),
            SizedBox(height: 16),
            _buildField(l.phoneNumber, '01XXXXXXXXX', Icons.phone,
                _phoneController, TextInputType.phone),
            SizedBox(height: 16),
            _buildField(l.vehicleId, l.vehicleIdHint, Icons.directions_boat,
                _vehicleController, TextInputType.text),
            SizedBox(height: 16),
            Text(l.vehicleType,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            Builder(builder: (context) {
              final l = AppLocalizations.of(context);
              final vehicleTypes = [
                {'key': 'Felucca', 'label': l.felucca, 'icon': Icons.sailing},
                {'key': 'Horse Carriage', 'label': l.horseCarriage, 'icon': Icons.directions},
              ];
              return Row(
                children: vehicleTypes.asMap().entries.map((entry) {
                  final i = entry.key;
                  final vt = entry.value;
                  final selected = _selectedType == vt['key'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedType = vt['key'] as String),
                      child: Container(
                        margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? Colors.teal.shade700 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: selected
                                  ? Colors.teal.shade700
                                  : Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              vt['icon'] as IconData,
                              color: selected ? Colors.white : Colors.grey,
                              size: 28,
                            ),
                            SizedBox(height: 6),
                            Text(vt['label'] as String,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
            SizedBox(height: 16),
            Text(l.vehiclePhoto,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 4),
            Text(l.vehiclePhotoHint,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 70);
                if (picked != null) {
                  setState(() => _vehiclePhoto = File(picked.path));
                }
              },
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _vehiclePhoto != null
                          ? Colors.teal.shade400
                          : Colors.grey.shade300,
                      width: 1.5),
                ),
                child: _vehiclePhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_vehiclePhoto!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo,
                              size: 40, color: Colors.teal.shade400),
                          SizedBox(height: 8),
                          Text(l.tapToAddVehiclePhoto,
                              style: TextStyle(
                                  color: Colors.teal.shade600, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(l.optionalRecommended,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.driverLicensePhoto,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 4),
            Text(l.licensePhotoHint,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 80);
                if (picked != null) {
                  setState(() => _licensePhoto = File(picked.path));
                }
              },
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _licensePhoto != null
                          ? Colors.orange.shade400
                          : Colors.grey.shade300,
                      width: 1.5),
                ),
                child: _licensePhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_licensePhoto!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.credit_card,
                              size: 40, color: Colors.orange.shade400),
                          SizedBox(height: 8),
                          Text(l.tapToAddLicensePhoto,
                              style: TextStyle(
                                  color: Colors.orange.shade700, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(l.licensePhotoRequired,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.password,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: l.createPasswordHint,
                prefixIcon: Icon(Icons.lock, color: Colors.teal.shade600),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(l.confirmPassword,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                hintText: l.reenterPasswordHint,
                prefixIcon: Icon(Icons.lock_outline, color: Colors.teal.shade600),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
                ),
              ),
            ),
            SizedBox(height: 32),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = _nameController.text.trim();
                        final phone = _phoneController.text.trim();
                        final vehicle = _vehicleController.text.trim();
                        final password = _passwordController.text;
                        final confirmPassword = _confirmPasswordController.text;
                        if (name.isEmpty || phone.isEmpty || vehicle.isEmpty ||
                            password.isEmpty || confirmPassword.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.fillAllFields)),
                          );
                          return;
                        }
                        if (password != confirmPassword) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.passwordsDoNotMatch)),
                          );
                          return;
                        }
                        setState(() => _isLoading = true);
                        final regError = await DriverAuthService.register(
                            name, phone, vehicle, _selectedType);
                        if (!mounted) return;
                        if (regError != null) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(regError)));
                          return;
                        }
                        final error = await DriverAuthService.completeRegistration(password);
                        if (!mounted) return;
                        if (error != null) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)));
                        } else {
                          // Upload photos in parallel
                          final uid = DriverAuthService.currentDriverId;
                          if (uid.isNotEmpty) {
                            final uploadResults = await Future.wait([
                              if (_personalPhoto != null)
                                DriverAuthService.uploadPersonalPhoto(_personalPhoto!, uid),
                              if (_vehiclePhoto != null)
                                DriverAuthService.uploadVehiclePhoto(_vehiclePhoto!, uid),
                              if (_licensePhoto != null)
                                DriverAuthService.uploadLicensePhoto(_licensePhoto!, uid),
                            ]);
                            if (!mounted) return;
                            final uploadErrors = uploadResults.whereType<String>().toList();
                            if (uploadErrors.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(l.photosUploadFailed),
                                duration: Duration(seconds: 6),
                              ));
                            }
                          }
                          if (!mounted) return;
                          setState(() => _isLoading = false);
                          Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => DriverPendingApprovalScreen(
                                  name: name)),
                              (_) => false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.registerAsDriver,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String hint, IconData icon,
      TextEditingController controller, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.teal.shade600),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.teal.shade600, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ===== 4. DRIVER PENDING APPROVAL SCREEN =====
class DriverPendingApprovalScreen extends StatelessWidget {
  final String name;
  const DriverPendingApprovalScreen({required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                    color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Icon(Icons.hourglass_top,
                    size: 60, color: Colors.orange.shade700),
              ),
              SizedBox(height: 32),
              Text(l.applicationSubmitted,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: 12),
              Text(
                l.pendingApprovalBody(name),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 15, height: 1.6),
              ),
              SizedBox(height: 32),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.pendingDocsReady,
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => DriverLoginScreen()),
                      (_) => false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.teal.shade700, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l.backToLogin,
                      style: TextStyle(
                          color: Colors.teal.shade700,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 5. HOME SCREEN (Main shell) =====
class DriverHomeScreen extends StatefulWidget {
  @override
  _DriverHomeScreenState createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    DriverDashboardTab(),
    RideRequestsTab(),
    TripHistoryTab(),
    DriverEarningsTab(),
    DriverProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal.shade700,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        items: [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: AppLocalizations.of(context).tabHome),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_active), label: AppLocalizations.of(context).navRequests),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: AppLocalizations.of(context).tabTrips),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet), label: AppLocalizations.of(context).earnings),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: AppLocalizations.of(context).tabProfile),
        ],
      ),
    );
  }
}

// ===== 5. DASHBOARD TAB =====
class DriverDashboardTab extends StatefulWidget {
  @override
  _DriverDashboardTabState createState() => _DriverDashboardTabState();
}

class _DriverDashboardTabState extends State<DriverDashboardTab> {
  bool _isOnline = false;
  bool _togglingOnline = false;
  final LatLng _luxor = LatLng(25.6872, 32.6396);
  StreamSubscription<RemoteMessage>? _fcmSub;
  StreamSubscription<QuerySnapshot>? _acceptedTripSub;
  bool _navigatedToActiveRide = false;
  final Set<String> _handledTripIds = {}; // prevents re-navigating to same trip
  late Future<Map<String, dynamic>> _statsFuture;

  Future<Map<String, dynamic>> _loadStats() async {
    final uid = DriverAuthService.currentDriverId;
    final results = await Future.wait([
      DriverDatabaseService.instance.getEarningsSummary(uid),
      DriverDatabaseService.instance.getDriverProfile(uid),
    ]);
    return {'summary': results[0], 'profile': results[1]};
  }

  Stream<List<Map<String, dynamic>>> get _requestsStream =>
      FirebaseFirestore.instance
          .collection('trips')
          .where('status', isEqualTo: 'requested')
          .snapshots()
          .map((snap) => snap.docs.where((d) {
                if (_driverDeclinedTripIds.contains(d.id)) return false;
                // Only show trips from the last 2 hours — filters out stale test data
                final createdAt = (d.data()['createdAt'] as Timestamp?)?.toDate();
                if (createdAt == null) return false;
                if (DateTime.now().difference(createdAt).inHours >= 2) return false;
                // Filter by this driver's vehicle type (Dart-side — no composite index needed)
                final myType = DriverAuthService.currentVehicleType;
                if (myType.isNotEmpty) {
                  final tripType = d.data()['vehicleType'] as String? ?? '';
                  if (tripType != myType) return false;
                }
                return true;
              }).map((d) {
                final data = d.data();
                return {
                  'id': d.id,
                  'passenger': data['passengerName'] ?? 'Passenger',
                  'passengerId': data['passengerId'] ?? '',
                  'pickup': data['pickup'] ?? '',
                  'dropoff': data['dropoff'] ?? '',
                  'vehicleType': data['vehicleType'] ?? '',
                  'pickupLat': (data['pickupLat'] as num?)?.toDouble(),
                  'pickupLng': (data['pickupLng'] as num?)?.toDouble(),
                  'dropoffLat': (data['dropoffLat'] as num?)?.toDouble(),
                  'dropoffLng': (data['dropoffLng'] as num?)?.toDouble(),
                  'distance': '—',
                  'duration': '—',
                  'amount': (data['agreedFare'] as num?)?.toDouble() ?? (data['fare'] as num?)?.toDouble() ?? 0.0,
                  'proposedFare': (data['proposedFare'] as num?)?.toDouble() ?? 0.0,
                  'payment': data['paymentMethod'] ?? 'cash',
                  'time': 'Just now',
                };
              }).toList());

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    // Show a SnackBar + play sound when a trip-request FCM notification arrives in the foreground
    _fcmSub = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      final type = message.data['type'] ?? '';
      if (type == 'trip_request' || message.notification != null) {
        SoundService.playTripRequest();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification?.body ?? 'New trip request!'),
            backgroundColor: Colors.teal.shade700,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    });
    // Listen for when passenger accepts this driver's offer
    final driverId = DriverAuthService.currentDriverId;
    if (driverId.isNotEmpty) {
      _acceptedTripSub = FirebaseFirestore.instance
          .collection('trips')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'accepted')
          .snapshots()
          .listen((snap) {
        if (!mounted || snap.docs.isEmpty || _navigatedToActiveRide) return;
        // Find the newest unhandled trip (not just the first/oldest)
        final unhandled = snap.docs.where((d) => !_handledTripIds.contains(d.id)).toList();
        if (unhandled.isEmpty) return;
        final doc = unhandled.last; // .last = most recently created
        _handledTripIds.add(doc.id);
        _navigatedToActiveRide = true;
        SoundService.playOfferAccepted();
        final data = doc.data();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveRideScreen(request: {
              'id': doc.id,
              'passenger': data['passengerName'] ?? 'Passenger',
              'passengerId': data['passengerId'] ?? '',
              'pickup': data['pickup'] ?? '',
              'dropoff': data['dropoff'] ?? '',
              'pickupLat': data['pickupLat'],
              'pickupLng': data['pickupLng'],
              'dropoffLat': data['dropoffLat'],
              'dropoffLng': data['dropoffLng'],
              'amount': (data['agreedFare'] as num?)?.toDouble() ?? (data['fare'] as num?)?.toDouble() ?? 0.0,
              'payment': data['paymentMethod'] ?? 'cash',
              'vehicleType': data['vehicleType'] ?? '',
              'passengerPhone': data['passengerPhone'] ?? '',
              'time': 'Just now',
            }),
          ),
        ).then((_) {
          if (mounted) setState(() => _navigatedToActiveRide = false);
        });
      });
    }
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    _acceptedTripSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sailing, color: Colors.teal.shade700, size: 22),
            SizedBox(width: 8),
            Text(l.driverAppTitle),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.red.shade400),
            onPressed: () async {
              await DriverAuthService.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => DriverLoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Online/Offline toggle banner
            GestureDetector(
              onTap: _togglingOnline ? null : () async {
                if (_isOnline) {
                  // Going offline
                  DriverLocationService.stopBroadcasting(
                      DriverAuthService.currentDriverId);
                  setState(() => _isOnline = false);
                  try {
                    await DriverDatabaseService.instance.setOnlineStatus(
                        DriverAuthService.currentDriverId, false);
                  } catch (_) {}
                } else {
                  // Go online immediately — don't block on GPS
                  setState(() {
                    _isOnline = true;
                    _togglingOnline = false;
                  });
                  try {
                    await DriverDatabaseService.instance.setOnlineStatus(
                        DriverAuthService.currentDriverId, true);
                  } catch (_) {}
                  // Try to start GPS broadcasting in the background (optional)
                  final result = await DriverLocationService.getCurrentLocation();
                  if (!mounted) return;
                  if (result.isSuccess) {
                    DriverLocationService.startBroadcasting(
                        DriverAuthService.currentDriverId,
                        driverName: DriverAuthService.currentDriverName);
                    try {
                      await DriverDatabaseService.instance.setOnlineStatus(
                        DriverAuthService.currentDriverId, true,
                        latitude: result.position!.latitude,
                        longitude: result.position!.longitude,
                      );
                    } catch (_) {}
                    final hasBg = await DriverLocationService.hasBackgroundPermission();
                    if (!hasBg && mounted) {
                      DriverLocationService.showBackgroundPermissionDialog(context);
                    }
                  }
                  // GPS failure: driver stays online, just no location broadcasting
                }
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 400),
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isOnline
                        ? [Colors.teal.shade700, Colors.teal.shade400]
                        : [Colors.grey.shade600, Colors.grey.shade400],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white60, width: 2),
                      ),
                      child: Icon(
                        _isOnline ? Icons.wifi : Icons.wifi_off,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      _isOnline ? l.youAreOnline : l.youAreOffline,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _isOnline
                          ? l.tapToGoOffline
                          : l.tapToStartAccepting,
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Today's stats
                  Text(l.todaySummary,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _statsFuture,
                    builder: (context, snap) {
                      final summary = snap.data?['summary'] as EarningsSummary?;
                      final profile = snap.data?['profile'] as DriverModel?;
                      final tripsToday = summary?.tripsToday ?? 0;
                      final earnedToday = summary?.today ?? 0.0;
                      final rating = profile?.rating ?? 0.0;
                      return Row(
                        children: [
                          Expanded(
                              child: _buildStatCard(AppLocalizations.of(context).tripsToday, '$tripsToday',
                                  Icons.directions_boat, Colors.blue)),
                          SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard(AppLocalizations.of(context).earnedToday,
                                  'EGP ${earnedToday.toStringAsFixed(0)}',
                                  Icons.account_balance_wallet, Colors.teal)),
                          SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard(AppLocalizations.of(context).rating,
                                  '${rating.toStringAsFixed(1)} ★',
                                  Icons.star, Colors.orange)),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 24),

                  // Incoming request highlight (real Firestore)
                  if (_isOnline)
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _requestsStream,
                      builder: (context, snap) {
                        final reqs = snap.data ?? [];
                        if (reqs.isEmpty) return SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.newRideRequest,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade700)),
                            SizedBox(height: 10),
                            _buildInlineRequest(reqs.first),
                            SizedBox(height: 24),
                          ],
                        );
                      },
                    ),

                  // Live map
                  Text(l.yourLocation,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _luxor,
                          initialZoom: 14.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                            userAgentPackageName: 'com.flutour.driver',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 44,
                                height: 44,
                                point: _luxor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade700,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 6)
                                    ],
                                  ),
                                  child: Icon(Icons.sailing,
                                      color: Colors.white, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color.shade600, size: 20),
          ),
          SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color.shade700)),
          SizedBox(height: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _showDashboardOfferDialog(Map<String, dynamic> req) {
    final tripId = req['id'] as String;
    final passengerFare = (req['proposedFare'] as num?)?.toDouble() ?? (req['amount'] as num?)?.toDouble() ?? 0.0;
    double offerAmount = passengerFare;
    final ctrl = TextEditingController(text: passengerFare.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).sendFareOffer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${AppLocalizations.of(ctx).passengerOffered} ${passengerFare.toStringAsFixed(0)} EGP',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              SizedBox(height: 12),
              Text(AppLocalizations.of(ctx).yourFareOffer, style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixText: 'EGP',
                  hintText: AppLocalizations.of(ctx).enterYourFare,
                ),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null) setDialog(() => offerAmount = d);
                },
              ),
              SizedBox(height: 8),
              Text(AppLocalizations.of(ctx).passengerWillChoose,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).cancel)),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final profile = await DriverDatabaseService.instance
                      .getDriverProfile(DriverAuthService.currentDriverId);
                  await DriverDatabaseService.instance.submitDriverOffer(
                    tripId: tripId,
                    driverUid: DriverAuthService.currentDriverId,
                    driverName: DriverAuthService.currentDriverName,
                    driverPhone: DriverAuthService.currentDriverPhone,
                    instapayPhone: profile.instapayPhone,
                    photoUrl: profile.photoUrl ?? '',
                    rating: profile.rating,
                    suggestedFare: offerAmount,
                    vehicleType: profile.vehicleType.value,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context).offerSent),
                        backgroundColor: Colors.teal.shade700,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${AppLocalizations.of(context).failedToSendOffer}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              child: Text(AppLocalizations.of(ctx).sendOffer, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineRequest(Map<String, dynamic> req) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.teal.withOpacity(0.1),
              blurRadius: 10,
              offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.teal.shade700,
                child: Text(req['passenger'][0],
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req['passenger'],
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(req['time'],
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('\$${req['amount'].toStringAsFixed(0)}',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 12),
          _locationRow(Icons.trip_origin, Colors.green, req['pickup']),
          SizedBox(height: 6),
          _locationRow(Icons.location_on, Colors.red, req['dropoff']),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final tripId = req['id'] as String? ?? '';
                    if (tripId.isEmpty) return;
                    setState(() => _driverDeclinedTripIds.add(tripId));
                    final uid = DriverAuthService.currentDriverId;
                    if (uid.isNotEmpty) {
                      DriverDatabaseService.instance
                          .withdrawOffer(tripId, uid)
                          .catchError((_) {});
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(AppLocalizations.of(context).decline),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _showDashboardOfferDialog(req),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(AppLocalizations.of(context).makeOffer,
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
        ),
      ],
    );
  }
}

// ===== 6. RIDE REQUESTS TAB =====
class RideRequestsTab extends StatefulWidget {
  @override
  _RideRequestsTabState createState() => _RideRequestsTabState();
}

class _RideRequestsTabState extends State<RideRequestsTab> {
  late final Stream<List<Map<String, dynamic>>> _stream;
  String? _streamError;
  final Set<String> _acceptingIds = {};
  final Set<String> _knownRequestIds = {};
  StreamSubscription? _soundSub;
  // _driverDeclinedTripIds is the shared top-level set used across all tabs

  @override
  void initState() {
    super.initState();
    // Separate subscription just for sound — plays once per NEW trip ID
    _soundSub = FirebaseFirestore.instance
        .collection('trips')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .listen((snap) {
      final incoming = snap.docs.map((d) => d.id).toSet();
      final newIds = incoming.difference(_knownRequestIds);
      if (_knownRequestIds.isNotEmpty && newIds.isNotEmpty) {
        SoundService.playTripRequest();
      }
      _knownRequestIds.addAll(incoming);
    });
    _stream = FirebaseFirestore.instance
        .collection('trips')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .handleError((e) {
          if (mounted) setState(() => _streamError = e.toString());
        })
        .map((snap) => snap.docs.where((d) {
              // Only show trips from the last 2 hours
              final createdAt = (d.data()['createdAt'] as Timestamp?)?.toDate();
              if (createdAt == null) return false;
              if (DateTime.now().difference(createdAt).inHours >= 2) return false;
              // Filter by vehicle type on Dart-side — no composite index needed
              final myType = DriverAuthService.currentVehicleType;
              if (myType.isNotEmpty) {
                final tripType = d.data()['vehicleType'] as String? ?? '';
                if (tripType != myType) return false;
              }
              return true;
            }).map((d) {
              final data = d.data();
              return {
                'id': d.id,
                'passenger': data['passengerName'] ?? 'Passenger',
                'passengerId': data['passengerId'] ?? '',
                'pickup': data['pickup'] ?? '',
                'dropoff': data['dropoff'] ?? '',
                'vehicleType': data['vehicleType'] ?? '',
                'pickupLat': (data['pickupLat'] as num?)?.toDouble(),
                'pickupLng': (data['pickupLng'] as num?)?.toDouble(),
                'dropoffLat': (data['dropoffLat'] as num?)?.toDouble(),
                'dropoffLng': (data['dropoffLng'] as num?)?.toDouble(),
                'distance': '—',
                'duration': '—',
                'amount': (data['fare'] as num?)?.toDouble() ?? 0.0,
                'proposedFare': (data['proposedFare'] as num?)?.toDouble() ?? 0.0,
                'payment': data['paymentMethod'] ?? 'cash',
                'time': 'Just now',
              };
            }).toList());
  }

  @override
  void dispose() {
    _soundSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.rideRequests), centerTitle: true),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (_streamError != null) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                    SizedBox(height: 12),
                    Text(AppLocalizations.of(context).couldNotLoadRequests,
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(_streamError!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          final requests = (snapshot.data ?? [])
              .where((r) => !_driverDeclinedTripIds.contains(r['id'] as String? ?? ''))
              .toList();
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 60, color: Colors.grey.shade300),
                  SizedBox(height: 16),
                  Text(l.noRequests,
                      style: TextStyle(color: Colors.grey.shade500)),
                  SizedBox(height: 8),
                  Text('Vehicle type: ${DriverAuthService.currentVehicleType}',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, i) => _buildRequestCard(requests[i]),
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.teal.shade100,
                child: Text(req['passenger'][0],
                    style: TextStyle(
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req['passenger'],
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                        '${req['vehicleType'] == 'felucca' ? AppLocalizations.of(context).felucca : AppLocalizations.of(context).horseCarriage} · ${req['payment']}',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Text('${req['amount'].toStringAsFixed(0)} EGP',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700)),
            ],
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _locationRow(
                    Icons.trip_origin, Colors.green, AppLocalizations.of(context).from, req['pickup']),
                Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Container(
                    height: 20,
                    width: 1,
                    color: Colors.grey.shade300,
                  ),
                ),
                _locationRow(
                    Icons.location_on, Colors.red, AppLocalizations.of(context).to, req['dropoff']),
              ],
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              _infoChip(Icons.straighten, req['distance']),
              SizedBox(width: 10),
              _infoChip(Icons.access_time, req['duration']),
              SizedBox(width: 10),
              _infoChip(Icons.payment, req['payment']),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final tripId = req['id'] as String;
                    final driverUid = DriverAuthService.currentDriverId;
                    setState(() => _driverDeclinedTripIds.add(tripId));
                    if (driverUid.isNotEmpty) {
                      DriverDatabaseService.instance
                          .withdrawOffer(tripId, driverUid)
                          .catchError((_) {}); // fire-and-forget; local hide already applied
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(AppLocalizations.of(context).decline, style: TextStyle(fontSize: 15)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _acceptingIds.contains(req['id'] as String)
                      ? null
                      : () => _showOfferDialog(req),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _acceptingIds.contains(req['id'] as String)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(AppLocalizations.of(context).makeOffer,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOfferDialog(Map<String, dynamic> req) {
    final tripId = req['id'] as String;
    final passengerFare = (req['proposedFare'] as num?)?.toDouble() ?? (req['amount'] as num?)?.toDouble() ?? 0.0;
    double offerAmount = passengerFare;
    final ctrl = TextEditingController(text: passengerFare.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).sendFareOffer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${AppLocalizations.of(ctx).passengerOffered} ${passengerFare.toStringAsFixed(0)} EGP',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              SizedBox(height: 12),
              Text(AppLocalizations.of(ctx).yourFareOffer, style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixText: 'EGP',
                  hintText: AppLocalizations.of(ctx).enterYourFare,
                ),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null) setDialog(() => offerAmount = d);
                },
              ),
              SizedBox(height: 8),
              Text(AppLocalizations.of(ctx).passengerWillChoose,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).cancel)),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _acceptingIds.add(tripId));
                try {
                  final profile = await DriverDatabaseService.instance
                      .getDriverProfile(DriverAuthService.currentDriverId);
                  await DriverDatabaseService.instance.submitDriverOffer(
                    tripId: tripId,
                    driverUid: DriverAuthService.currentDriverId,
                    driverName: DriverAuthService.currentDriverName,
                    driverPhone: DriverAuthService.currentDriverPhone,
                    instapayPhone: profile.instapayPhone,
                    photoUrl: profile.photoUrl ?? '',
                    rating: profile.rating,
                    suggestedFare: offerAmount,
                    vehicleType: profile.vehicleType.value,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context).offerSent),
                        backgroundColor: Colors.teal.shade700,
                      ),
                    );
                    setState(() => _acceptingIds.remove(tripId));
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => _acceptingIds.remove(tripId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${AppLocalizations.of(context).failedToSendOffer}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              child: Text(AppLocalizations.of(ctx).sendOffer, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(
      IconData icon, Color color, String label, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: 8),
        Text('$label: ',
            style:
                TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        Expanded(
          child: Text(text,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.teal.shade600),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.teal.shade700)),
        ],
      ),
    );
  }
}

// ===== 7. ACTIVE RIDE SCREEN =====
class ActiveRideScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  ActiveRideScreen({required this.request});

  @override
  _ActiveRideScreenState createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  int _step = 0; // 0=heading to pickup, 1=arrived, 2=trip started, 3=completed
  int _passengerRating = 0; // 0 = not rated yet
  List<String> _stepLabels(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      l.headingToPickup,
      l.arrivedAtPickup,
      l.tripInProgress,
      l.tripCompletedLabel,
    ];
  }

  final LatLng _luxor = LatLng(25.6872, 32.6396);
  LatLng? _driverPos;
  StreamSubscription<Position>? _posStream;
  final MapController _mapCtrl = MapController();
  List<LatLng>? _routePoints;
  String? _etaLabel;
  DateTime? _lastRouteFetch;

  @override
  void initState() {
    super.initState();
    final driverId = DriverAuthService.currentDriverId;
    // Ensure broadcasting is running — it may not have started if GPS failed
    // at the online-toggle step, or if the driver resumed from a previous session.
    if (!DriverLocationService.isBroadcasting) {
      DriverLocationService.startBroadcasting(
        driverId,
        driverName: DriverAuthService.currentDriverName,
        isOnTrip: true,
      );
    } else {
      DriverLocationService.updateOnTripStatus(driverId, true);
    }
    _startTracking();
  }

  void _startTracking() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
    final driverId = DriverAuthService.currentDriverId;
    // Get current position immediately so route shows without waiting for stream
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _driverPos = loc);
      _mapCtrl.move(loc, 15.5);
      _fetchAndSetRoute();
      // Push to Firebase immediately — don't wait for the 3-second timer
      DriverLocationService.broadcastPosition(driverId, pos.latitude, pos.longitude);
    } catch (_) {}
    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _driverPos = loc);
      _mapCtrl.move(loc, 15.5);
      _fetchAndSetRoute();
      // Keep Firebase in sync on every movement
      DriverLocationService.broadcastPosition(driverId, pos.latitude, pos.longitude);
    });
  }

  Future<void> _fetchAndSetRoute() async {
    final driverPos = _driverPos;
    if (driverPos == null) return;

    LatLng? target;
    if (_step < 2) {
      // Heading to pickup or arrived — route to pickup
      final lat = (widget.request['pickupLat'] as num?)?.toDouble();
      final lng = (widget.request['pickupLng'] as num?)?.toDouble();
      if (lat != null && lng != null) target = LatLng(lat, lng);
    } else if (_step == 2) {
      // Trip in progress — route to destination
      final lat = (widget.request['dropoffLat'] as num?)?.toDouble();
      final lng = (widget.request['dropoffLng'] as num?)?.toDouble();
      if (lat != null && lng != null) target = LatLng(lat, lng);
    }
    if (target == null) return;
    final nonNullTarget = target;

    // Throttle ORS calls to once every 30 seconds to stay within free tier
    final now = DateTime.now();
    if (_lastRouteFetch != null && now.difference(_lastRouteFetch!).inSeconds < 30) return;
    _lastRouteFetch = now;
    final result = await RouteService.fetchRoute(driverPos, nonNullTarget);
    if (!mounted) return;
    if (result != null && result.points.length > 1) {
      setState(() {
        _routePoints = result.points;
        _etaLabel = RouteService.etaLabel(result.durationSeconds);
      });
    }
  }

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  Future<void> _nextStep() async {
    final l = AppLocalizations.of(context);
    final tripId = widget.request['id'] as String? ?? '';
    try {
      if (_step == 0) {
        // Heading → Arrived: tell Firestore driver has arrived at pickup
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.arriveTrip(tripId);
        }
        setState(() => _step = 1);
        _fetchAndSetRoute();
      } else if (_step == 1) {
        // Arrived → Trip in Progress: start the ride
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.startTrip(tripId);
        }
        setState(() => _step = 2);
        _fetchAndSetRoute();
      } else if (_step == 2) {
        // In Progress → Complete: finish the trip
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.completeTrip(
              tripId,
              (widget.request['amount'] as num?)?.toDouble() ?? 0.0,
              DriverAuthService.currentDriverId);
        }
        DriverLocationService.updateOnTripStatus(DriverAuthService.currentDriverId, false);
        setState(() => _step = 3);
      } else {
        // Step 3: show earnings and go back to dashboard
        if (!mounted) return;
        final fare = (widget.request['amount'] as num?)?.toDouble() ?? 0.0;
        final earning = fare * 0.85;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Row(children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text(l.tripComplete),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.earningsForTrip,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                SizedBox(height: 10),
                Text('${fare.toStringAsFixed(0)} EGP',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        color: Colors.teal.shade700)),
                SizedBox(height: 4),
                Text('${l.yourShare} ${earning.toStringAsFixed(0)} EGP',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close earnings dialog
                  _showPassengerRatingDialog();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700),
                child: Text(l.backToDashboard,
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l.updateFailed}: $e'), duration: Duration(seconds: 6)));
      }
    }
  }

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => DriverHomeScreen()),
      (_) => false,
    );
  }

  void _openNavigation() async {
    final isToPickup = _step < 2;
    final lat = isToPickup
        ? (widget.request['pickupLat'] as num?)?.toDouble()
        : (widget.request['dropoffLat'] as num?)?.toDouble();
    final lng = isToPickup
        ? (widget.request['pickupLng'] as num?)?.toDouble()
        : (widget.request['dropoffLng'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      // Fallback: use address text when coordinates are not available
      final address = isToPickup
          ? (widget.request['pickup'] as String? ?? '')
          : (widget.request['dropoff'] as String? ?? '');
      if (address.isEmpty) return;
      final encoded = Uri.encodeComponent(address);
      final uri = Uri.parse('https://maps.google.com/?q=$encoded');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    final gmapsNav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final gmapsWeb = Uri.parse('https://maps.google.com/?daddr=$lat,$lng');
    final waze = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    if (await canLaunchUrl(gmapsNav)) {
      await launchUrl(gmapsNav);
    } else if (await canLaunchUrl(waze)) {
      await launchUrl(waze);
    } else {
      await launchUrl(gmapsWeb, mode: LaunchMode.externalApplication);
    }
  }

  void _cancelTrip() {
    final l = AppLocalizations.of(context);
    String? _selectedReason;
    final reasons = [l.reasonPassengerNotFound, l.reasonVehicleIssue, l.reasonEmergency, l.reasonPassengerRequest, l.reasonOther];
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(l.cancelTripTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.selectReason, style: TextStyle(color: Colors.grey.shade700)),
              SizedBox(height: 8),
              ...reasons.map((r) => RadioListTile<String>(
                value: r, groupValue: _selectedReason,
                title: Text(r, style: TextStyle(fontSize: 13)),
                onChanged: (v) => setDialog(() => _selectedReason = v),
                contentPadding: EdgeInsets.zero, dense: true,
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.keepTrip)),
            ElevatedButton(
              onPressed: _selectedReason == null ? null : () async {
                final tripId = widget.request['id'] as String? ?? '';
                if (tripId.isNotEmpty) {
                  await DriverDatabaseService.instance.cancelTripByDriver(tripId, _selectedReason!);
                }
                DriverLocationService.updateOnTripStatus(DriverAuthService.currentDriverId, false);
                if (ctx.mounted) { Navigator.pop(ctx); _goToDashboard(); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(l.cancelTrip, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPassengerRatingDialog() {
    final l = AppLocalizations.of(context);
    int tempRating = 0;
    final commentCtrl = TextEditingController();
    final tripId = widget.request['id'] as String? ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Icon(Icons.person, size: 48, color: Colors.teal.shade600),
              SizedBox(height: 8),
              Text(l.ratePassenger, textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.howWasPassenger,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < tempRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () => setDialog(() => tempRating = i + 1),
                  );
                }),
              ),
              SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx).leaveComment,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                commentCtrl.dispose();
                Navigator.pop(ctx);
                _goToDashboard();
              },
              child: Text(AppLocalizations.of(ctx).skip, style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: tempRating == 0
                  ? null
                  : () async {
                      if (tripId.isNotEmpty) {
                        await FirebaseFirestore.instance
                            .collection('trips')
                            .doc(tripId)
                            .update({
                          'driverRating': tempRating,
                          if (commentCtrl.text.trim().isNotEmpty)
                            'driverComment': commentCtrl.text.trim(),
                        });
                      }
                      commentCtrl.dispose();
                      if (mounted) {
                        Navigator.pop(ctx);
                        _goToDashboard();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l.submitRating, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.activeRide),
        centerTitle: true,
        leading: _step == 0
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () async {
                  final tripId = widget.request['id'] as String? ?? '';
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(AppLocalizations.of(context).refuseTrip),
                      content: Text(AppLocalizations.of(context).refuseTripConfirm),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).no)),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: Text(AppLocalizations.of(context).yesRefuse, style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && tripId.isNotEmpty) {
                    try { await DriverDatabaseService.instance.cancelTripByDriver(tripId, 'Driver refused'); } catch (_) {}
                  }
                  if (confirm == true && mounted) {
                    DriverLocationService.updateOnTripStatus(DriverAuthService.currentDriverId, false);
                    _goToDashboard();
                  }
                },
              )
            : SizedBox.shrink(),
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? Colors.teal.shade600
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (i < 3) SizedBox(width: 4),
                    ],
                  ),
                );
              }),
            ),
          ),
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(bottom: 12),
            child: Center(
              child: Text(
                _stepLabels(context)[_step],
                style: TextStyle(
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _driverPos ?? _luxor,
                    initialZoom: 15.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                      userAgentPackageName: 'com.flutour.driver',
                    ),
                    if (_routePoints != null && _routePoints!.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints!,
                            strokeWidth: 4.5,
                            color: Colors.teal.shade600,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 44,
                          height: 44,
                          point: _driverPos ?? _luxor,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black26, blurRadius: 6)
                              ],
                            ),
                            child: Icon(Icons.sailing,
                                color: Colors.white, size: 22),
                          ),
                        ),
                        Marker(
                          width: 36,
                          height: 36,
                          point: LatLng(
                            (widget.request['pickupLat'] as num?)?.toDouble() ?? 25.6900,
                            (widget.request['pickupLng'] as num?)?.toDouble() ?? 32.6370,
                          ),
                          child: Icon(Icons.trip_origin,
                              color: Colors.green, size: 32),
                        ),
                        Marker(
                          width: 36,
                          height: 36,
                          point: LatLng(
                            (widget.request['dropoffLat'] as num?)?.toDouble() ?? 25.6840,
                            (widget.request['dropoffLng'] as num?)?.toDouble() ?? 32.6450,
                          ),
                          child: Icon(Icons.location_on,
                              color: Colors.red, size: 32),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_etaLabel != null)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                        ),
                        child: Text(
                          '${l.eta}: $_etaLabel',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom panel
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.teal.shade100,
                      child: Text(widget.request['passenger'][0],
                          style: TextStyle(
                              color: Colors.teal.shade700,
                              fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.request['passenger'],
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(
                              '${widget.request['pickup']} → ${widget.request['dropoff']}',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text(
                        '${widget.request['amount'].toStringAsFixed(0)} EGP',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade700)),
                  ],
                ),
                SizedBox(height: 12),
                // Navigate button
                if (_step < 3)
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => _openNavigation(),
                      icon: Icon(Icons.navigation, size: 18, color: Colors.teal.shade700),
                      label: Text(
                        _step < 2 ? l.navigateToPassenger : l.navigateToDestination,
                        style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.teal.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _step == 3
                          ? Colors.green.shade600
                          : Colors.teal.shade700,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _step == 0
                          ? l.arrivedAtPassenger
                          : _step == 1
                              ? l.startTrip
                              : _step == 2
                                  ? (widget.request['paymentMethod'] == 'instapay'
                                      ? l.paymentReceivedComplete
                                      : l.completeTrip)
                                  : l.doneBackToHome,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_step < 2)
                  TextButton(
                    onPressed: _cancelTrip,
                    child: Text(l.cancelTrip,
                        style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}

// ===== 8. TRIP HISTORY TAB =====
class TripHistoryTab extends StatefulWidget {
  @override
  _TripHistoryTabState createState() => _TripHistoryTabState();
}

class _TripHistoryTabState extends State<TripHistoryTab> {
  late Future<List<TripModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = DriverDatabaseService.instance
        .getTripHistory(DriverAuthService.currentDriverId);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.tripHistory), centerTitle: true),
      body: FutureBuilder<List<TripModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                  SizedBox(height: 12),
                  Text(AppLocalizations.of(context).couldNotLoadHistory,
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future =
                        DriverDatabaseService.instance
                            .getTripHistory(DriverAuthService.currentDriverId)),
                    child: Text(l.retry),
                  ),
                ],
              ),
            );
          }
          final trips = snap.data ?? [];
          if (trips.isEmpty) {
            return Center(child: Text(l.noTripsYet));
          }
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: trips.length,
            itemBuilder: (context, i) => _buildHistoryCard(trips[i]),
          );
        },
      ),
    );
  }

  Widget _buildHistoryCard(TripModel trip) {
    final bool isCompleted = trip.status == TripStatus.completed;
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.teal.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : Icons.cancel,
              color: isCompleted ? Colors.teal.shade600 : Colors.red.shade400,
              size: 28,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.passengerName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 3),
                Text('${trip.pickup} → ${trip.dropoff}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: 3),
                Text(
                    '${trip.createdAt.toString().substring(0, 10)} · ${trip.paymentMethod.label}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isCompleted ? 'EGP ${trip.fare.toStringAsFixed(0)}' : '-',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? Colors.teal.shade700 : Colors.grey),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(trip.status.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: isCompleted ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== 9. EARNINGS TAB =====
class DriverEarningsTab extends StatefulWidget {
  @override
  _DriverEarningsTabState createState() => _DriverEarningsTabState();
}

class _DriverEarningsTabState extends State<DriverEarningsTab> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final uid = DriverAuthService.currentDriverId;
    final results = await Future.wait([
      DriverDatabaseService.instance.getEarningsSummary(uid),
      DriverDatabaseService.instance.getDriverProfile(uid),
      DriverDatabaseService.instance.getDailyEarnings(uid),
      // withdrawal_requests: single-field query only (no compound index needed)
      FirebaseFirestore.instance
          .collection('withdrawal_requests')
          .where('driverId', isEqualTo: uid)
          .get(),
    ]);
    // Sort by requestedAt desc in Dart, take last 5
    final wSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final withdrawals = wSnap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .toList()
      ..sort((a, b) {
        final ta = (a['requestedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (b['requestedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

    // Read admin instapay separately with its own error handling
    String adminInstapay = '';
    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('admin')
          .get();
      adminInstapay = (adminDoc.data()?['instapayPhone'] as String?) ?? '';
    } catch (_) {}

    return {
      'summary': results[0],
      'profile': results[1],
      'daily': results[2],
      'withdrawals': withdrawals.take(5).toList(),
      'adminInstapay': adminInstapay,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.earnings), centerTitle: true),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                  SizedBox(height: 12),
                  Text(l.couldNotLoadEarnings,
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _future = _loadData()),
                    child: Text(l.retry),
                  ),
                ],
              ),
            );
          }
          final summary = snap.data?['summary'] as EarningsSummary? ??
              EarningsSummary(today: 0, thisWeek: 0, thisMonth: 0, tripsToday: 0, tripsThisWeek: 0);
          final profile = snap.data?['profile'] as DriverModel?;
          final daily = (snap.data?['daily'] as List<double>?) ?? List<double>.filled(7, 0);

          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade700, Colors.teal.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.3),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.thisMonth,
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                      SizedBox(height: 8),
                      Text('EGP ${summary.thisMonth.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          _balanceStat(l.totalRides, '${profile?.totalTrips ?? 0}'),
                          SizedBox(width: 24),
                          _balanceStat(l.rating, '${(profile?.rating ?? 0.0).toStringAsFixed(1)} ★'),
                          SizedBox(width: 24),
                          _balanceStat(l.vehicle, profile?.vehicleId ?? '—'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Text(l.thisPeriod,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatBox(l.todayTripsLabel, '${summary.tripsToday}', Colors.teal)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatBox(l.todayEarnedLabel, 'EGP ${summary.today.toStringAsFixed(0)}', Colors.green)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatBox(l.thisWeek, 'EGP ${summary.thisWeek.toStringAsFixed(0)}', Colors.orange)),
                  ],
                ),
                SizedBox(height: 24),
                // 7-day bar chart
                SizedBox(height: 24),
                Text(l.last7Days,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                _EarningsBarChart(daily: daily),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final balance = profile?.balance ?? 0.0;
                      final instapayNum = profile?.instapayPhone.trim() ?? '';

                      if (balance <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.noEarningsToWithdraw), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      if (instapayNum.isEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Row(children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(l.instapayMissing),
                            ]),
                            content: Text(l.instapayMissingBody),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                                child: Text(l.ok, style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Row(children: [
                            Icon(Icons.account_balance, color: Colors.teal.shade700),
                            SizedBox(width: 8),
                            Text(l.withdrawViaInstapay),
                          ]),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.amountLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              Text('EGP ${balance.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                              SizedBox(height: 12),
                              Text(l.willBeSentTo, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              Container(
                                margin: EdgeInsets.only(top: 6),
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.teal.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.phone, color: Colors.teal.shade700, size: 18),
                                    SizedBox(width: 8),
                                    Text(instapayNum,
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(l.instapayTransferNote,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(l.cancel),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('withdrawal_requests')
                                      .add({
                                    'driverId': DriverAuthService.currentDriverId,
                                    'driverName': DriverAuthService.currentDriverName,
                                    'driverPhone': DriverAuthService.currentDriverPhone,
                                    'instapayPhone': instapayNum,
                                    'amount': balance,
                                    'status': 'pending',
                                    'requestedAt': FieldValue.serverTimestamp(),
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l.withdrawalSubmitted),
                                        backgroundColor: Colors.teal.shade700,
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l.failedToSubmitRequest), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                              child: Text(l.confirmWithdrawal, style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.account_balance_wallet, color: Colors.white),
                    label: Text(l.withdrawEarnings,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // ── Cash commission info ─────────────────────────────────
                Builder(builder: (ctx) {
                  final adminInstapay = snap.data?['adminInstapay'] as String? ?? '';
                  if (adminInstapay.isEmpty) return SizedBox.shrink();
                  return Container(
                    padding: EdgeInsets.all(14),
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade700, size: 16),
                          SizedBox(width: 6),
                          Text(l.cashCommission,
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800, fontSize: 13)),
                        ]),
                        SizedBox(height: 6),
                        Text(l.cashCommissionNote,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                        SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.phone, color: Colors.teal.shade700, size: 15),
                          SizedBox(width: 6),
                          Text(adminInstapay,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ]),
                      ],
                    ),
                  );
                }),

                // ── Withdrawal history ────────────────────────────────────
                Builder(builder: (ctx) {
                  final withdrawals = (snap.data?['withdrawals'] as List<dynamic>?) ?? [];
                  if (withdrawals.isEmpty) return SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.recentWithdrawals,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      ...withdrawals.map((w) {
                        final req = w as Map<String, dynamic>;
                        final amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
                        final status = req['status'] as String? ?? 'pending';
                        final ts = (req['requestedAt'] as Timestamp?)?.toDate();
                        final dateStr = ts != null ? ts.toLocal().toString().substring(0, 10) : '—';
                        final isPaid = status == 'paid';
                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isPaid ? Icons.check_circle : Icons.schedule,
                                color: isPaid ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('EGP ${amount.toStringAsFixed(0)}',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isPaid ? l.paid : l.pendingStatus,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isPaid ? Colors.green.shade700 : Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  );
                }),
                SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _balanceStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildStatBox(String label, String value, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color.shade700)),
          SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 11, color: color.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ===== EARNINGS BAR CHART =====
class _EarningsBarChart extends StatelessWidget {
  final List<double> daily; // 7 values, index 0 = 6 days ago, index 6 = today
  const _EarningsBarChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final maxVal = daily.fold<double>(0, (m, v) => v > m ? v : m);
    final l = AppLocalizations.of(context);
    final days = [l.day6Ago, l.day5Ago, l.day4Ago, l.day3Ago, l.day2Ago, l.yesterday, l.today];
    return Container(
      height: 160,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final val = daily[i];
          final ratio = maxVal > 0 ? val / maxVal : 0.0;
          final isToday = i == 6;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (val > 0)
                    Text(
                      '${val.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 9, color: Colors.teal.shade700, fontWeight: FontWeight.bold),
                    ),
                  SizedBox(height: 2),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 600),
                    height: (100 * ratio).clamp(4, 100).toDouble(),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.teal.shade700 : Colors.teal.shade200,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(days[i], style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ===== 10. PROFILE TAB =====
class DriverProfileTab extends StatefulWidget {
  @override
  _DriverProfileTabState createState() => _DriverProfileTabState();
}

class _DriverProfileTabState extends State<DriverProfileTab> {
  late Future<DriverModel> _future;
  final _instapayCtrl = TextEditingController();
  bool _savingInstapay = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _future = DriverDatabaseService.instance
        .getDriverProfile(DriverAuthService.currentDriverId)
      ..then((d) {
        if (mounted) _instapayCtrl.text = d.instapayPhone;
      });
  }

  @override
  void dispose() {
    _instapayCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploadingPhoto = true);
    final error = await DriverAuthService.uploadProfilePhoto();
    if (mounted) {
      setState(() => _uploadingPhoto = false);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).photoUpdated), backgroundColor: Colors.teal),
        );
      }
    }
  }

  Future<void> _saveInstapay() async {
    final phone = _instapayCtrl.text.trim();
    setState(() => _savingInstapay = true);
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(DriverAuthService.currentDriverId)
          .update({'instapayPhone': phone});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).instapayNumberSaved), backgroundColor: Colors.teal),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).failedToSave), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingInstapay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.profile), centerTitle: true),
      body: FutureBuilder<DriverModel>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && snap.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                  SizedBox(height: 12),
                  Text(l.couldNotLoadProfile,
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future =
                        DriverDatabaseService.instance
                            .getDriverProfile(DriverAuthService.currentDriverId)),
                    child: Text(l.retry),
                  ),
                ],
              ),
            );
          }
          final name = snap.data?.name ?? DriverAuthService.currentDriverName;
          final phone = snap.data?.phone ?? DriverAuthService.currentDriverPhone;
          final rating = snap.data?.rating ?? 0.0;
          final vehicleType = snap.data?.vehicleType.label ?? '—';
          final vehicleId = snap.data?.vehicleId ?? '—';
          final totalTrips = snap.data?.totalTrips ?? 0;

          return SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickPhoto,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            _uploadingPhoto
                                ? CircleAvatar(
                                    radius: 44,
                                    backgroundColor: Colors.teal.shade100,
                                    child: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : DriverAuthService.currentPhotoUrl.isNotEmpty
                                    ? CircleAvatar(
                                        radius: 44,
                                        backgroundImage: NetworkImage(
                                            DriverAuthService.currentPhotoUrl),
                                      )
                                    : CircleAvatar(
                                        radius: 44,
                                        backgroundColor: Colors.teal.shade100,
                                        child: Text(
                                          name.isNotEmpty ? name[0] : 'D',
                                          style: TextStyle(
                                              fontSize: 36,
                                              color: Colors.teal.shade700,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.teal.shade600,
                              child: Icon(Icons.camera_alt, color: Colors.white, size: 14),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 14),
                      Text(name,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(phone,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 18),
                          SizedBox(width: 4),
                          Text('${rating.toStringAsFixed(1)} ${l.rating}',
                              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                          SizedBox(width: 16),
                          Icon(Icons.circle, color: Colors.green, size: 10),
                          SizedBox(width: 4),
                          Text(l.approved,
                              style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                _buildSection(l.myVehicle, [
                  _profileRow(Icons.directions_boat, l.vehicleType, vehicleType),
                  _profileRow(Icons.numbers, l.vehicleId, vehicleId),
                  _profileRow(Icons.route, l.totalRides, '$totalTrips'),
                ]),
                SizedBox(height: 16),
                // InstaPay phone section
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.instapayNumber,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.grey.shade700)),
                      SizedBox(height: 4),
                      Text(l.instapayNote,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _instapayCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.phone, color: Colors.teal.shade600),
                                hintText: '01XXXXXXXXX',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          _savingInstapay
                              ? SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : ElevatedButton(
                                  onPressed: _saveInstapay,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                  ),
                                  child: Text(l.save,
                                      style: TextStyle(color: Colors.white)),
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                // Language toggle
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
                      ]),
                  child: ListTile(
                    leading: Icon(Icons.language, color: Colors.teal.shade700),
                    title: Text(l.language),
                    trailing: DropdownButton<String>(
                      value: Localizations.localeOf(context).languageCode,
                      underline: SizedBox(),
                      items: [
                        DropdownMenuItem(value: 'en', child: Text(l.english)),
                        DropdownMenuItem(value: 'ar', child: Text(l.arabic)),
                      ],
                      onChanged: (code) {
                        if (code != null) {
                          context.read<LocaleProvider>().setLocale(Locale(code));
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(height: 16),
                _buildSection(l.account, [
                  _actionRow(Icons.person_outline, l.editProfile, Colors.indigo, () => _editProfile(context)),
                  _actionRow(Icons.lock, l.changePassword, Colors.blue, () => _changePassword(context)),
                  _actionRow(Icons.support_agent, l.contactSupport, Colors.teal, () => _contactSupport(context)),
                  _actionRow(Icons.logout, l.signOut, Colors.red, () async {
                    await DriverAuthService.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => DriverLoginScreen()),
                      );
                    }
                  }),
                ]),
                SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editProfile(BuildContext context) {
    final l = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: DriverAuthService.currentDriverName);
    final phoneCtrl = TextEditingController(text: DriverAuthService.currentDriverPhone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editProfile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: l.fullName,
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { nameCtrl.dispose(); phoneCtrl.dispose(); Navigator.pop(ctx); },
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              nameCtrl.dispose(); phoneCtrl.dispose();
              Navigator.pop(ctx);
              if (name.isEmpty) return;
              final uid = DriverAuthService.currentDriverId;
              final updates = <String, dynamic>{'name': name};
              if (phone.isNotEmpty) updates['phone'] = phone;
              await FirebaseFirestore.instance.collection('drivers').doc(uid).update(updates);
              DriverAuthService.updateCachedProfile(name: name, phone: phone);
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: Text(l.save, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _changePassword(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l.changePassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: l.currentPassword,
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setS(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: l.newPasswordLabel,
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setS(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () { currentCtrl.dispose(); newCtrl.dispose(); Navigator.pop(ctx); },
              child: Text(l.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final current = currentCtrl.text;
                final newPass = newCtrl.text;
                currentCtrl.dispose(); newCtrl.dispose();
                if (newPass.length < 6) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l.passwordMin6)));
                  return;
                }
                Navigator.pop(ctx);
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null && user.email != null) {
                    final cred = EmailAuthProvider.credential(email: user.email!, password: current);
                    await user.reauthenticateWithCredential(cred);
                    await user.updatePassword(newPass);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.passwordUpdated), backgroundColor: Colors.green));
                  }
                } on FirebaseAuthException catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.code == 'wrong-password'
                        ? l.wrongCurrentPassword : (e.message ?? l.error)),
                        backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
              child: Text(l.updateBtn, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _contactSupport(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.support_agent, color: Colors.teal.shade700),
          SizedBox(width: 8),
          Text(l.contactSupport),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.driverSupportTeam, style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email, color: Colors.blue),
              title: Text('support@app.flutour.com'),
              subtitle: Text(l.emailSupport),
              onTap: () async {
                final uri = Uri.parse('mailto:support@app.flutour.com?subject=FluTour Driver Support');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.chat, color: Colors.green),
              title: Text('WhatsApp'),
              subtitle: Text('01020773548'),
              onTap: () async {
                final uri = Uri.parse('https://wa.me/201020773548');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade700)),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.teal.shade500),
          SizedBox(width: 12),
          Text('$label:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _actionRow(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ===== WEEK 5: TRIP REQUEST NOTIFICATION SCREEN =====
class TripRequestNotificationScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  const TripRequestNotificationScreen({required this.request});
  @override
  _TripRequestNotificationScreenState createState() =>
      _TripRequestNotificationScreenState();
}

class _TripRequestNotificationScreenState
    extends State<TripRequestNotificationScreen> {
  int _seconds = 30;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    SoundService.playTripRequest(); // alert driver a new request just arrived
    _countdown = Timer.periodic(Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_seconds <= 1) {
        t.cancel();
        _autoDecline();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _autoDecline() {
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).requestTimedOut)));
  }

  void _accept() async {
    _countdown?.cancel();
    // Accept at passenger's offered fare
    final fare = (widget.request['proposedFare'] as num?)?.toDouble()
        ?? (widget.request['amount'] as num?)?.toDouble()
        ?? 0.0;
    _submitOffer(fare);
  }

  void _submitOffer(double fare) async {
    try {
      final profile = await DriverDatabaseService.instance
          .getDriverProfile(DriverAuthService.currentDriverId);
      await DriverDatabaseService.instance.submitDriverOffer(
        tripId: widget.request['id'] as String,
        driverUid: DriverAuthService.currentDriverId,
        driverName: DriverAuthService.currentDriverName,
        driverPhone: DriverAuthService.currentDriverPhone,
        instapayPhone: profile.instapayPhone,
        photoUrl: profile.photoUrl ?? '',
        rating: profile.rating,
        suggestedFare: fare,
        vehicleType: profile.vehicleType.value,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).failedToSubmitOffer)));
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).offerSentWaiting),
        backgroundColor: Colors.teal.shade700,
      ),
    );
    Navigator.pop(context);
  }

  void _decline() {
    _countdown?.cancel();
    final tripId = widget.request['id'] as String? ?? '';
    if (tripId.isNotEmpty) {
      _driverDeclinedTripIds.add(tripId);
      final uid = DriverAuthService.currentDriverId;
      if (uid.isNotEmpty) {
        DriverDatabaseService.instance
            .withdrawOffer(tripId, uid)
            .catchError((_) {});
      }
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).requestDeclined)));
  }

  void _counter() {
    _countdown?.cancel();
    double counterAmount = (widget.request['proposedFare'] ?? widget.request['amount'] ?? 60).toDouble();
    final ctrl = TextEditingController(text: counterAmount.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).suggestYourFare),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context).enterFareOffer, style: TextStyle(color: Colors.grey.shade600)),
            SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixText: 'EGP',
              ),
              onChanged: (v) { final d = double.tryParse(v); if (d != null) counterAmount = d; },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).cancel)),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _submitOffer(counterAmount);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: Text(AppLocalizations.of(ctx).sendOffer, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final req = widget.request;
    final bool urgent = _seconds < 10;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(l.newTripRequest),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.teal.shade700,
          titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(height: 12),
              // Countdown timer circle
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: urgent ? Colors.red.shade600 : Colors.teal.shade700,
                      width: 5),
                ),
                child: Center(
                  child: Text('$_seconds',
                      style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: urgent ? Colors.red.shade600 : Colors.teal.shade700)),
                ),
              ),
              SizedBox(height: 6),
              Text(urgent ? l.expiringSoon : l.secondsRemaining,
                  style: TextStyle(
                      color: urgent ? Colors.red.shade600 : Colors.grey.shade600,
                      fontSize: 13)),
              SizedBox(height: 24),
              // Request card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal.shade200),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: Icon(Icons.person, color: Colors.teal.shade700),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(req['passenger'],
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17,
                                color: Colors.teal.shade800)),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.teal.shade200)),
                        child: Text(
                            req['vehicleType'] == 'horse_carriage' || req['vehicleType'] == 'Horse Carriage'
                                ? l.horseCarriage
                                : l.felucca,
                            style: TextStyle(color: Colors.teal.shade700,
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ]),
                    SizedBox(height: 14),
                    _reqRow(Icons.trip_origin, Colors.green, '${req['pickup']} → ${req['dropoff']}'),
                    SizedBox(height: 8),
                    _reqRow(Icons.route, Colors.blue, '${req['distance']} · ${req['duration']}'),
                    SizedBox(height: 8),
                    _reqRow(Icons.access_time, Colors.grey, '${req['time']} · ${req['payment']}'),
                    SizedBox(height: 12),
                    // Proposed fare display
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          Text(l.passengerOffer,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            '${(req['proposedFare'] ?? req['amount'] ?? 0).toStringAsFixed(0)} EGP',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Spacer(),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _decline,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text('✗  ${l.decline}',
                          style: TextStyle(color: Colors.grey.shade700,
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _counter,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade700,
                        side: BorderSide(color: Colors.orange.shade700),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: Size(0, 52),
                      ),
                      child: Text(l.counterOffer, style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _accept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text('✓  ${l.accept}',
                          style: TextStyle(color: Colors.white,
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reqRow(IconData icon, Color color, String text) => Row(
    children: [
      Icon(icon, size: 15, color: color),
      SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
    ],
  );
}

// ===== WEEK 5: DRIVER ACTIVE TRIP SCREEN =====
class DriverActiveTripScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  const DriverActiveTripScreen({required this.request});
  @override
  _DriverActiveTripScreenState createState() => _DriverActiveTripScreenState();
}

class _DriverActiveTripScreenState extends State<DriverActiveTripScreen> {
  int _step = 0;
  int _passengerRating = 0; // 0 = not rated yet
  List<String> _stepsLabels(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [l.navigateToPassenger, l.arrivedAtPassenger, l.tripInProgress, l.tripCompletedLabel];
  }
  final _stepColors = [Colors.blue, Colors.orange, Colors.teal, Colors.green];

  void _advance() {
    final labels = _stepsLabels(context);
    if (_step < labels.length - 1) {
      setState(() => _step++);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_stepsLabels(context)[_step])));
    } else {
      _showComplete();
    }
  }

  void _showComplete() {
    final l = AppLocalizations.of(context);
    final fare = widget.request['amount'] as double;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text(l.tripComplete),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.earningsForTrip, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            SizedBox(height: 8),
            Text('${fare.toStringAsFixed(0)} ${l.egpFare}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal.shade700)),
            SizedBox(height: 4),
            Text('${(fare * 0.8).toStringAsFixed(0)} ${l.egpAfterCommission}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showPassengerRatingDialog();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: Text(AppLocalizations.of(context).backToDashboard, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => DriverHomeScreen()),
      (_) => false,
    );
  }

  void _showPassengerRatingDialog() {
    final l = AppLocalizations.of(context);
    int tempRating = 0;
    final commentCtrl = TextEditingController();
    final tripId = widget.request['id'] as String? ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Icon(Icons.person, size: 48, color: Colors.teal.shade600),
              SizedBox(height: 8),
              Text(l.ratePassenger, textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.howWasPassenger,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < tempRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () => setDialog(() => tempRating = i + 1),
                  );
                }),
              ),
              SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx).leaveComment,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                commentCtrl.dispose();
                Navigator.pop(ctx);
                _goToDashboard();
              },
              child: Text(AppLocalizations.of(ctx).skip, style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: tempRating == 0
                  ? null
                  : () async {
                      if (tripId.isNotEmpty) {
                        await FirebaseFirestore.instance
                            .collection('trips')
                            .doc(tripId)
                            .update({
                          'driverRating': tempRating,
                          if (commentCtrl.text.trim().isNotEmpty)
                            'driverComment': commentCtrl.text.trim(),
                        });
                      }
                      commentCtrl.dispose();
                      if (mounted) {
                        Navigator.pop(ctx);
                        _goToDashboard();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l.submitRating, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).activeRide),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.teal.shade700,
        titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 55,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(25.6987, 32.6390),
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                  userAgentPackageName: 'com.flutour.driver',
                ),
                MarkerLayer(markers: [
                  Marker(
                    width: 44, height: 44,
                    point: LatLng(25.6987, 32.6390),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: Icon(Icons.person_pin_circle, color: Colors.white, size: 26),
                    ),
                  ),
                  Marker(
                    width: 44, height: 44,
                    point: LatLng(25.7188, 32.6571),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: Icon(Icons.location_on, color: Colors.white, size: 26),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          // Trip info + status buttons
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.person, color: Colors.teal.shade700),
                  SizedBox(width: 8),
                  Text(req['passenger'],
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Spacer(),
                  Text('${(req['amount'] as double).toStringAsFixed(0)} EGP',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 18, color: Colors.teal.shade700)),
                ]),
                SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.trip_origin, size: 13, color: Colors.green),
                  SizedBox(width: 6),
                  Expanded(child: Text(req['pickup'],
                      style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  Icon(Icons.arrow_forward, size: 13, color: Colors.grey),
                  SizedBox(width: 6),
                  Icon(Icons.location_on, size: 13, color: Colors.red),
                  SizedBox(width: 4),
                  Expanded(child: Text(req['dropoff'],
                      style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                ]),
                SizedBox(height: 16),
                // Step indicator
                Builder(builder: (ctx) {
                  final labels = _stepsLabels(ctx);
                  return Row(children: List.generate(labels.length, (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < labels.length - 1 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: i <= _step ? _stepColors[_step] : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )));
                }),
                SizedBox(height: 10),
                Text(_stepsLabels(context)[_step],
                    style: TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 14, color: _stepColors[_step])),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _advance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _stepColors[_step],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _step < _stepsLabels(context).length - 1 ? _stepsLabels(context)[_step + 1] : AppLocalizations.of(context).completeTrip,
                      style: TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
