// lib/main.dart - FluTour Passenger App
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models.dart';
import 'database_service.dart';
import 'location_service.dart';
import 'route_service.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app_localizations.dart';
import 'locale_provider.dart';

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
  await AuthService.loadSession();
  final localeProvider = await LocaleProvider.load(defaultLocale: const Locale('en'));
  runApp(
    ChangeNotifierProvider.value(
      value: localeProvider,
      child: FluTourPassengerApp(),
    ),
  );
}

class FluTourPassengerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    return MaterialApp(
      title: 'FluTour',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color(0xFFF4F6FA),
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
      home: SplashScreen(),
    );
  }
}

// ===== AUTH SERVICE =====
class AuthService {
  static String _currentUserName = '';
  static String _currentUserPhone = '';
  static String _currentPhotoUrl = '';
  static String _tempPassword = '';

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
  static String get currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  static String get currentUserName => _currentUserName;
  static String get currentUserPhone => _currentUserPhone;
  static String get currentPhotoUrl => _currentPhotoUrl;

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserName = prefs.getString('passenger_name') ?? '';
    _currentUserPhone = prefs.getString('passenger_phone') ?? '';
    _currentPhotoUrl = prefs.getString('passenger_photo') ?? '';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        if (doc.exists) {
          _currentUserName = doc.data()?['name'] ?? _currentUserName;
          _currentUserPhone = doc.data()?['phone'] ?? _currentUserPhone;
          _currentPhotoUrl = doc.data()?['photoUrl'] ?? user.photoURL ?? _currentPhotoUrl;
          await prefs.setString('passenger_name', _currentUserName);
          await prefs.setString('passenger_phone', _currentUserPhone);
          await prefs.setString('passenger_photo', _currentPhotoUrl);
        }
      } catch (_) {}
    }
    // Load live surge multipliers from Firestore
    await FareEstimator.loadSurge();
  }

  // imgBB free image hosting — same key as driver app (api.imgbb.com)
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

  /// Pick photo from gallery, upload to imgBB, save URL to Firestore.
  static Future<String?> uploadProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked == null) return null;
      final uid = currentUserId;
      if (uid.isEmpty) return 'Not logged in';
      final url = await _uploadToImgBB(File(picked.path));
      if (url == null) return 'Failed to upload photo';
      _currentPhotoUrl = url;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'photoUrl': url});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_photo', url);
      return null;
    } catch (e) {
      return 'Failed to upload photo: $e';
    }
  }

  static String _phoneToEmail(String phone) =>
      '${phone.replaceAll(RegExp(r'[^0-9]'), '')}@flutour.app';

  static Future<String?> signIn(String phone, String password) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _phoneToEmail(phone), password: password);
      _currentUserPhone = phone.trim();
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).get();
      _currentUserName = doc.data()?['name'] ?? 'Passenger';
      _currentPhotoUrl = doc.data()?['photoUrl'] ?? '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_name', _currentUserName);
      await prefs.setString('passenger_phone', _currentUserPhone);
      await prefs.setString('passenger_photo', _currentPhotoUrl);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'No account found for this phone number';
      if (e.code == 'wrong-password') return 'Incorrect password';
      return e.message ?? 'Sign in failed';
    } catch (_) {
      return 'Service unavailable. Please check your connection.';
    }
  }

  static Future<String?> register(String name, String phone, String password,
      {String nationality = ''}) async {
    if (name.isEmpty || phone.isEmpty || password.length < 6)
      return 'Password must be at least 6 characters';
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _phoneToEmail(phone), password: password);
      _currentUserName = name;
      _currentUserPhone = phone.trim();
      await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).set({
        'name': _currentUserName,
        'phone': _currentUserPhone,
        'nationality': nationality,
        'role': 'passenger',
        'totalRides': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_name', _currentUserName);
      await prefs.setString('passenger_phone', _currentUserPhone);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return 'An account already exists for this phone number';
      if (e.code == 'weak-password') return 'Password must be at least 6 characters';
      return e.message ?? 'Registration failed';
    } catch (_) {
      return 'Registration failed. Please check your connection.';
    }
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
      // Load or create Firestore user doc
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final googlePhoto = cred.user?.photoURL ?? googleUser.photoUrl ?? '';
      if (!doc.exists) {
        _currentUserName = cred.user?.displayName ?? googleUser.displayName ?? 'Passenger';
        _currentUserPhone = cred.user?.phoneNumber ?? '';
        _currentPhotoUrl = googlePhoto;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': _currentUserName,
          'phone': _currentUserPhone,
          'nationality': '',
          'photoUrl': _currentPhotoUrl,
          'role': 'passenger',
          'totalRides': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        _currentUserName = doc.data()?['name'] ?? cred.user?.displayName ?? 'Passenger';
        _currentUserPhone = doc.data()?['phone'] ?? '';
        _currentPhotoUrl = doc.data()?['photoUrl'] ?? googlePhoto;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_name', _currentUserName);
      await prefs.setString('passenger_phone', _currentUserPhone);
      await prefs.setString('passenger_photo', _currentPhotoUrl);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Google sign-in failed';
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  static Future<String?> sendPasswordReset(String phone) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
          email: _phoneToEmail(phone));
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send reset';
    }
  }

  // ── Phone OTP verification ────────────────────────────────────────────────
  static String _lastVerificationId = '';

  /// Formats Egyptian phone (01XXXXXXXXX → +201XXXXXXXXX) and sends OTP via Firebase.
  static Future<String?> sendPhoneOtp(String phone) async {
    String formatted = phone.trim();
    if (formatted.startsWith('0')) {
      formatted = '+20${formatted.substring(1)}';
    } else if (!formatted.startsWith('+')) {
      formatted = '+20$formatted';
    }
    try {
      final completer = Completer<String?>();
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formatted,
        verificationCompleted: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        verificationFailed: (e) {
          if (!completer.isCompleted) completer.complete(e.message ?? 'Verification failed');
        },
        codeSent: (verificationId, _) {
          _lastVerificationId = verificationId;
          if (!completer.isCompleted) completer.complete(null);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _lastVerificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
      return await completer.future;
    } catch (e) {
      return 'Failed to send code: $e';
    }
  }

  /// Verifies the 6-digit OTP and links phone to the existing account.
  static Future<String?> verifyOtp(String smsCode) async {
    if (_lastVerificationId.isEmpty) return 'Session expired. Please resend code.';
    try {
      final credential = PhoneAuthProvider.credential(
          verificationId: _lastVerificationId, smsCode: smsCode);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'provider-already-linked' && e.code != 'credential-already-in-use') {
            return e.message ?? 'Invalid code';
          }
        }
        await FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .update({'phoneVerified': true});
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Invalid code';
    }
  }

  static void updateCachedProfile({String? name, String? phone}) async {
    if (name != null && name.isNotEmpty) _currentUserName = name;
    if (phone != null && phone.isNotEmpty) _currentUserPhone = phone;
    final prefs = await SharedPreferences.getInstance();
    if (name != null && name.isNotEmpty) await prefs.setString('passenger_name', name);
    if (phone != null && phone.isNotEmpty) await prefs.setString('passenger_phone', phone);
  }

  static Future<String?> changePassword(String currentPassword, String newPassword) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return 'Not logged in';
      final cred = EmailAuthProvider.credential(email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') return 'Current password is incorrect';
      return e.message ?? 'Failed to change password';
    } catch (e) {
      return 'Failed to change password: $e';
    }
  }

  static Future<void> signOut() async {
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    _currentUserName = '';
    _currentUserPhone = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('passenger_name');
    await prefs.remove('passenger_phone');
  }
}


// ===== 1. SPLASH SCREEN =====
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: Duration(seconds: 2));
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _float = Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
    // Firebase.initializeApp() in main() has already restored the persisted
    // credential — currentUser is synchronously available here.
    Future.delayed(Duration(seconds: 3), () {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => PassengerHomeScreen()));
      } else {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => LoginScreen()));
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
            colors: [Colors.blue.shade900, Colors.blue.shade600, Colors.blue.shade400],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Transform.scale(
                      scale: _scale.value,
                      child: Transform.translate(
                        offset: Offset(0, _float.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30, width: 2),
                              ),
                              child: Icon(Icons.sailing, size: 80, color: Colors.white),
                            ),
                            SizedBox(height: 28),
                            Text('FluTour',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 46,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Passenger',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16, letterSpacing: 2)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 36),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => LoginScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Get Started',
                        style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
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
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _login() async {
    if (_phoneCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter phone and password')));
      return;
    }
    setState(() => _loading = true);
    final error = await AuthService.signIn(
        _phoneCtrl.text.trim(), _passCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)));
    } else {
      // Save FCM token so Cloud Functions can send trip-status notifications
      try {
        await FirebaseMessaging.instance.requestPermission();
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && AuthService.currentUserId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(AuthService.currentUserId)
              .update({'fcmToken': token});
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => PassengerHomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Hero gradient section ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24, bottom: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.blue.shade600, Colors.blue.shade400],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 2),
                  ),
                  child: Icon(Icons.sailing, size: 38, color: Colors.white),
                ),
                SizedBox(height: 12),
                Text('FluTour',
                    style: TextStyle(
                        color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Luxor's Felucca & Carriage Rides",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          // ── Form section ─────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(28, 28, 28, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Phone Number'),
                  SizedBox(height: 8),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDeco('01XXXXXXXXX', Icons.phone),
                  ),
                  SizedBox(height: 20),
                  _label('Password'),
                  SizedBox(height: 8),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: _inputDeco('••••••••', Icons.lock).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  SizedBox(height: 6),
                  _loading
                      ? Center(child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(color: Colors.blue.shade700)))
                      : SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(l.signIn,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                  SizedBox(height: 14),
                  // ── Google Sign-In ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _googleLoading ? null : () async {
                        setState(() => _googleLoading = true);
                        final error = await AuthService.signInWithGoogle();
                        if (!mounted) return;
                        setState(() => _googleLoading = false);
                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)));
                        } else {
                          Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => PassengerHomeScreen()),
                              (_) => false);
                        }
                      },
                      icon: _googleLoading
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.g_mobiledata, size: 26, color: Colors.red.shade700),
                      label: Text('Continue with Google',
                          style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => RegisterScreen())),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.blue.shade700, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.createAccount,
                          style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ForgotPasswordScreen())),
                      child: Text('Forgot password?',
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14));

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue.shade600),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
        ),
      );
}

// ===== 3. REGISTER SCREEN =====
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nationalityCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.createAccount),
        centerTitle: true,
        leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50, shape: BoxShape.circle),
                child: Icon(Icons.person_add, size: 50, color: Colors.blue.shade700),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(l.joinFluTour,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            SizedBox(height: 4),
            Center(
              child: Text('Book Felucca & Horse Carriage rides in Luxor',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            SizedBox(height: 32),
            _field('Full Name', 'Ahmed Hassan', Icons.person, _nameCtrl,
                TextInputType.name),
            SizedBox(height: 16),
            _field('Nationality', 'e.g. Egyptian, British...', Icons.flag, _nationalityCtrl,
                TextInputType.text),
            SizedBox(height: 16),
            _field('Phone Number', '01XXXXXXXXX', Icons.phone, _phoneCtrl,
                TextInputType.phone),
            SizedBox(height: 16),
            Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: Icon(Icons.lock, color: Colors.blue.shade600),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                ),
              ),
            ),
            SizedBox(height: 32),
            _loading
                ? Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_nameCtrl.text.trim().isEmpty ||
                            _phoneCtrl.text.trim().isEmpty ||
                            _passCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Please fill all fields')));
                          return;
                        }
                        setState(() => _loading = true);
                        // Step 1: create account
                        final error = await AuthService.register(
                            _nameCtrl.text.trim(),
                            _phoneCtrl.text.trim(),
                            _passCtrl.text.trim(),
                            nationality: _nationalityCtrl.text.trim());
                        if (!mounted) return;
                        if (error != null) {
                          setState(() => _loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)));
                          return;
                        }
                        // Step 2: send OTP for phone verification
                        final otpError = await AuthService.sendPhoneOtp(_phoneCtrl.text.trim());
                        if (!mounted) return;
                        setState(() => _loading = false);
                        if (otpError != null) {
                          // OTP send failed — go to home anyway (can verify later)
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Account created! Phone verification skipped: $otpError')));
                          Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => PassengerHomeScreen()),
                              (_) => false);
                        } else {
                          // Step 3: navigate to OTP screen
                          Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => OtpScreen(
                                  phone: _phoneCtrl.text.trim(),
                                  name: _nameCtrl.text.trim())));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.createAccount,
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

  Widget _field(String label, String hint, IconData icon,
      TextEditingController ctrl, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.blue.shade600),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ===== 4. OTP VERIFICATION SCREEN =====
class OtpScreen extends StatefulWidget {
  final String phone;
  final String name;
  const OtpScreen({required this.phone, required this.name});
  @override
  _OtpScreenState createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _ctrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focus = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _resendSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendSeconds == 0) { t.cancel(); return; }
      setState(() => _resendSeconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _ctrl) c.dispose();
    for (var f in _focus) f.dispose();
    super.dispose();
  }

  String get _otp => _ctrl.map((c) => c.text).join();

  void _verify() async {
    if (_otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter the 6-digit code')));
      return;
    }
    setState(() => _loading = true);
    final error = await AuthService.verifyOtp(_otp);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone verified successfully!')));
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => PassengerHomeScreen()), (_) => false);
    }
  }

  void _resend() async {
    setState(() => _loading = true);
    final error = await AuthService.sendPhoneOtp(widget.phone);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code resent!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Verify Phone'),
        centerTitle: true,
        leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 32),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(Icons.sms, size: 50, color: Colors.blue.shade700),
            ),
            SizedBox(height: 20),
            Text('Verification Code',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Enter the 6-digit verification code sent to your phone',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => SizedBox(
                width: 44,
                height: 54,
                child: TextField(
                  controller: _ctrl[i],
                  focusNode: _focus[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  decoration: InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && i < 5) _focus[i + 1].requestFocus();
                    if (val.isEmpty && i > 0) _focus[i - 1].requestFocus();
                    if (i == 5 && val.isNotEmpty) _verify();
                  },
                ),
              )),
            ),
            SizedBox(height: 36),
            _loading
                ? CircularProgressIndicator(color: Colors.blue.shade700)
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Verify & Continue',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
            SizedBox(height: 20),
            _resendSeconds > 0
                ? Text('Resend code in $_resendSeconds seconds',
                    style: TextStyle(color: Colors.grey.shade500))
                : TextButton(
                    onPressed: _loading ? null : _resend,
                    child: Text('Resend Code',
                        style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
          ],
        ),
      ),
    );
  }
}

// ===== 5. FORGOT PASSWORD SCREEN =====
class ForgotPasswordScreen extends StatefulWidget {
  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _sendReset() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter your phone number')));
      return;
    }
    setState(() => _loading = true);
    final error = await AuthService.sendPasswordReset(_phoneCtrl.text.trim());
    if (!mounted) return;
    setState(() { _loading = false; _sent = error == null; });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Forgot Password'),
        centerTitle: true,
        leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 32),
            Center(
              child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50, shape: BoxShape.circle),
                child: Icon(Icons.lock_reset, size: 50, color: Colors.blue.shade700),
              ),
            ),
            SizedBox(height: 24),
            if (_sent) ...[
              Center(
                child: Column(children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 60),
                  SizedBox(height: 12),
                  Text('Reset link sent!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Check your messages for the password reset link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 24),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Back to Login',
                          style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold))),
                ]),
              ),
            ] else ...[
              Text('Reset Password',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text("Enter your phone number and we'll send you a reset link.",
                  style: TextStyle(color: Colors.grey.shade600)),
              SizedBox(height: 32),
              Text('Phone Number',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '01XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone, color: Colors.blue.shade600),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                  ),
                ),
              ),
              SizedBox(height: 32),
              _loading
                  ? Center(child: CircularProgressIndicator(color: Colors.blue.shade700))
                  : SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _sendReset,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Send Reset Link',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===== 6. PASSENGER HOME SCREEN (Shell) =====
class PassengerHomeScreen extends StatefulWidget {
  @override
  _PassengerHomeScreenState createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  int _idx = 0;
  String? vehicleFilter;
  final _bookRideKey = GlobalKey<_BookRideTabState>();
  late final List<Widget> _tabs;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeTab(),
      BookRideTab(key: _bookRideKey),
      MyTripsTab(),
      ProfileTab(),
    ];
    // Listen for trip-status FCM notifications while app is in foreground
    _fcmSub = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.notification?.body ??
              message.data['body'] as String? ??
              'Trip status updated'),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context).tabHome),
          BottomNavigationBarItem(icon: Icon(Icons.sailing), label: AppLocalizations.of(context).tabBook),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: AppLocalizations.of(context).tabTrips),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: AppLocalizations.of(context).tabProfile),
        ],
      ),
    );
  }
}

// ===== 5. HOME TAB =====
class HomeTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sailing, color: Colors.blue.shade700, size: 24),
            SizedBox(width: 8),
            Text('FluTour'),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.blue.shade700),
                  SizedBox(width: 4),
                  Text('Passenger',
                      style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome banner
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, ${AuthService.currentUserName.split(' ').first}!',
                            style: TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Where to today?',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            // Switch to Book tab
                            final state = context
                                .findAncestorStateOfType<_PassengerHomeScreenState>();
                            state?.setState(() => state._idx = 1);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search, color: Colors.blue.shade700, size: 18),
                                SizedBox(width: 8),
                                Text('Book a ride',
                                    style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.sailing, size: 70, color: Colors.white24),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Ride types
            Text('Ride Types',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _rideTypeCard(context, 'Felucca',
                    AppLocalizations.of(context).felucca,
                    Icons.sailing, Colors.blue, 'Traditional Nile boat ride')),
                SizedBox(width: 12),
                Expanded(
                    child: _rideTypeCard(context, 'Horse Carriage',
                        AppLocalizations.of(context).horseCarriage,
                        Icons.directions, Colors.orange, 'Classic Hantour ride')),
              ],
            ),
            SizedBox(height: 24),

            // Popular spots
            Text('Popular in Luxor',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _spotCard(context, 'Luxor Temple', '⭐ 4.9', Colors.amber),
                  _spotCard(context, 'Karnak Temple', '⭐ 4.8', Colors.orange),
                  _spotCard(context, 'Nile Corniche', '⭐ 4.7', Colors.blue),
                  _spotCard(context, 'Winter Palace', '⭐ 4.6', Colors.purple),
                ],
              ),
            ),
            SizedBox(height: 24),

            SizedBox(height: 20),

            // Safety info
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.blue.shade700, size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safe & Verified Rides',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800)),
                        SizedBox(height: 4),
                        Text('All drivers are approved and vehicles inspected.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color.shade600, size: 18),
          ),
          SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color.shade700)),
          SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _rideTypeCard(BuildContext context, String type, String displayName,
      IconData icon, MaterialColor color, String desc) {
    return GestureDetector(
      onTap: () {
        final state =
            context.findAncestorStateOfType<_PassengerHomeScreenState>();
        state?.setState(() {
          state.vehicleFilter = type;
          state._idx = 1;
        });
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.shade50, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color.shade700, size: 28),
            ),
            SizedBox(height: 10),
            Text(displayName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text(desc,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: color.shade700,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(AppLocalizations.of(context).bookNow,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spotCard(BuildContext context, String name, String rating, MaterialColor color) {
    return GestureDetector(
      onTap: () {
        final homeState =
            context.findAncestorStateOfType<_PassengerHomeScreenState>();
        homeState?._bookRideKey.currentState?.setDropoff(name);
        homeState?.setState(() => homeState._idx = 1);
      },
      child: Container(
        width: 140,
        margin: EdgeInsets.only(right: 12),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.shade200),
          boxShadow: [
            BoxShadow(color: color.shade100, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.place, color: color.shade600, size: 22),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.shade600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Book',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(name,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            SizedBox(height: 4),
            Text(rating,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            SizedBox(height: 6),
            Text('Tap to set destination',
                style: TextStyle(fontSize: 10, color: color.shade400)),
          ],
        ),
      ),
    );
  }

}

// ===== 6. BOOK RIDE TAB (Map → Vehicle → Payment) =====
class BookRideTab extends StatefulWidget {
  const BookRideTab({Key? key}) : super(key: key);

  @override
  _BookRideTabState createState() => _BookRideTabState();
}

class _BookRideTabState extends State<BookRideTab> {
  LatLng _center = LatLng(25.6872, 32.6396); // default: Luxor Corniche
  final _mapController = MapController();
  LatLng? _pickupLoc;      // GPS-detected pickup
  LatLng? _destinationLoc;
  bool _locating = false;  // spinner while getting GPS
  String? _fareEstimate;   // shown after both points are set
  double? _feluccaFareAmt;
  double? _hantourFareAmt;
  List<LatLng>? _routePoints;
  bool _fetchingRoute = false;
  String? _routeInfo; // "1.2 km · 4 min"
  DateTime? _scheduledAt;
  bool get _isScheduled => _scheduledAt != null && _scheduledAt!.isAfter(DateTime.now());

  static const _spotCoords = {
    'Luxor Temple':  LatLng(25.6987, 32.6390),
    'Karnak Temple': LatLng(25.7188, 32.6571),
    'Nile Corniche': LatLng(25.6872, 32.6370),
    'Winter Palace': LatLng(25.6938, 32.6393),
  };

  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  void setDropoff(String destination) {
    setState(() {
      _dropoffCtrl.text = destination;
      _destinationLoc = _spotCoords[destination];
    });
    final loc = _spotCoords[destination];
    if (loc != null) {
      Future.microtask(() => _mapController.move(loc, 15.5));
    }
    _updateFareEstimate();
  }

  // Auto-detect GPS pickup point
  Future<void> _detectMyLocation() async {
    setState(() => _locating = true);
    final result = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _locating = false);

    if (result.isSuccess) {
      final pos = result.position!;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _pickupLoc = loc;
        _center = loc;
        _pickupCtrl.text = 'My Location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
      });
      _mapController.move(loc, 15.5);
      _updateFareEstimate();
    } else {
      if (result.errorMessage!.contains('permanently')) {
        LocationService.showPermissionDeniedDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.errorMessage!)));
      }
    }
  }

  Future<void> _updateFareEstimate() async {
    final pickup = _pickupLoc;
    final dest = _destinationLoc;
    if (pickup == null || dest == null) {
      setState(() { _fareEstimate = null; _routePoints = null; _routeInfo = null; _feluccaFareAmt = null; _hantourFareAmt = null; });
      return;
    }
    // Haversine distance used for Horse Carriage fare (carriages don't follow car roads)
    final dist = FareEstimator.distanceKm(
        pickup.latitude, pickup.longitude, dest.latitude, dest.longitude);
    setState(() { _fetchingRoute = true; });
    final result = await RouteService.fetchRoute(pickup, dest);
    if (!mounted) return;
    if (result != null) {
      final eta = RouteService.etaLabel(result.durationSeconds);
      final durationMin = result.durationSeconds / 60.0;
      final feluccaFare = FareEstimator.estimate(result.distanceKm,
          vehicleType: 'felucca', durationMinutes: durationMin);
      // Horse carriage uses straight-line (haversine) dist — ORS road distance is too long
      final hantourFare = FareEstimator.estimate(dist, vehicleType: 'horse_carriage');
      setState(() {
        _routePoints = result.points;
        _routeInfo = '${dist.toStringAsFixed(1)} km · $eta';
        _feluccaFareAmt = feluccaFare.total;
        _hantourFareAmt = hantourFare.total;
        _fareEstimate = 'set';
        _fetchingRoute = false;
      });
    } else {
      // Fallback to straight-line if ORS fails
      final eta = FareEstimator.etaString(dist);
      final feluccaFare = FareEstimator.estimate(dist, vehicleType: 'felucca');
      final hantourFare = FareEstimator.estimate(dist, vehicleType: 'horse_carriage');
      setState(() {
        _routeInfo = null;
        _feluccaFareAmt = feluccaFare.total;
        _hantourFareAmt = hantourFare.total;
        _fareEstimate = 'set';
        _fetchingRoute = false;
      });
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a future time')));
      return;
    }
    setState(() {
      _scheduledAt = scheduled;
      _dateCtrl.text = '${date.day}/${date.month}/${date.year}';
      _timeCtrl.text = time.format(context);
    });
  }

  void _clearSchedule() {
    setState(() {
      _scheduledAt = null;
      _timeCtrl.text = 'Now';
      _dateCtrl.text = 'Today';
    });
  }

  @override
  void initState() {
    super.initState();
    _timeCtrl.text = 'Now';
    _dateCtrl.text = 'Today';
  }

  Future<void> _openPickupSearch() async {
    final l = AppLocalizations.of(context);
    final result = await Navigator.push<GeoSuggestion>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(title: l.searchPickupLocation),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pickupCtrl.text = result.name;
        _pickupLoc = result.location;
        _center = result.location;
      });
      _mapController.move(result.location, 15.5);
      _updateFareEstimate();
    }
  }

  Future<void> _openDropoffSearch() async {
    final l = AppLocalizations.of(context);
    final result = await Navigator.push<GeoSuggestion>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(title: l.searchDropoffLocation),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _dropoffCtrl.text = result.name;
        _destinationLoc = result.location;
      });
      _mapController.move(result.location, 15.5);
      _updateFareEstimate();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _timeCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).bookARide), centerTitle: true),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14.0,
              interactionOptions: InteractionOptions(),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                userAgentPackageName: 'com.flutour.passenger',
              ),
              if (_routePoints != null && _routePoints!.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints!,
                      strokeWidth: 4.0,
                      color: Colors.blue.shade600,
                    ),
                  ],
                ),
              MarkerLayer(markers: [
                // GPS pickup marker (blue dot)
                Marker(
                  width: 44,
                  height: 44,
                  point: _pickupLoc ?? _center,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Icon(Icons.person_pin_circle, color: Colors.white, size: 26),
                  ),
                ),
                // Destination marker (shown when a spot is selected)
                if (_destinationLoc != null)
                  Marker(
                    width: 48,
                    height: 48,
                    point: _destinationLoc!,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                          ),
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.location_on, color: Colors.white, size: 22),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _dropoffCtrl.text.split(' ').first,
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
          // "My Location" floating button (top-right)
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'myloc',
              backgroundColor: Colors.white,
              onPressed: _locating ? null : _detectMyLocation,
              child: _locating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.my_location, color: Colors.blue.shade700),
            ),
          ),
          // Fare estimate chip (shown when pickup + dropoff are both known)
          if (_fareEstimate != null && _feluccaFareAmt != null && _hantourFareAmt != null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 24),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🚣 Felucca: EGP ${_feluccaFareAmt!.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.teal.shade800)),
                    SizedBox(height: 2),
                    Text('🐎 Horse: EGP ${_hantourFareAmt!.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.brown.shade700)),
                  ],
                ),
              ),
            ),
          if (_fetchingRoute)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).findingRoute, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ),

          // Bottom booking sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // absorbs map tap events
              child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 10),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Icon(Icons.location_searching, color: Colors.blue.shade700),
                        SizedBox(width: 10),
                        Text(AppLocalizations.of(context).planYourRide,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _openPickupSearch,
                          child: AbsorbPointer(
                            child: _mapInput(_pickupCtrl, AppLocalizations.of(context).pickupPoint,
                                AppLocalizations.of(context).searchPickupLocation, Icons.trip_origin, Colors.green),
                          ),
                        ),
                        SizedBox(height: 10),
                        GestureDetector(
                          onTap: _openDropoffSearch,
                          child: AbsorbPointer(
                            child: _mapInput(_dropoffCtrl, AppLocalizations.of(context).dropoffPoint,
                                AppLocalizations.of(context).searchDropoffLocation, Icons.location_on, Colors.red),
                          ),
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickDateTime,
                                child: AbsorbPointer(
                                  child: _mapInput(_timeCtrl, AppLocalizations.of(context).pickupTime,
                                      'Now', Icons.access_time, Colors.blue),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickDateTime,
                                child: AbsorbPointer(
                                  child: _mapInput(_dateCtrl, AppLocalizations.of(context).date,
                                      'Today', Icons.calendar_today, Colors.purple),
                                ),
                              ),
                            ),
                            if (_scheduledAt != null)
                              IconButton(
                                icon: Icon(Icons.close, color: Colors.grey),
                                onPressed: _clearSchedule,
                                tooltip: 'Clear schedule',
                              ),
                          ],
                        ),
                        if (_isScheduled)
                          Container(
                            margin: EdgeInsets.only(top: 6),
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule, size: 14, color: Colors.blue.shade700),
                                SizedBox(width: 6),
                                Text(
                                  'Scheduled: ${_timeCtrl.text} · ${_dateCtrl.text}',
                                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_pickupCtrl.text.trim().isEmpty ||
                                  _dropoffCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(AppLocalizations.of(context).enterPickupDropoff)));
                                return;
                              }
                              final homeState = context
                                  .findAncestorStateOfType<_PassengerHomeScreenState>();
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => VehicleSelectScreen(
                                            pickup: _pickupCtrl.text.trim(),
                                            dropoff: _dropoffCtrl.text.trim(),
                                            time: _timeCtrl.text.trim(),
                                            date: _dateCtrl.text.trim(),
                                            filter: homeState?.vehicleFilter,
                                            pickupLat: _pickupLoc?.latitude,
                                            pickupLng: _pickupLoc?.longitude,
                                            dropoffLat: _destinationLoc?.latitude,
                                            dropoffLng: _destinationLoc?.longitude,
                                            scheduledAt: _scheduledAt?.toIso8601String(),
                                            feluccaFare: _feluccaFareAmt ?? 0.0,
                                            hantourFare: _hantourFareAmt ?? 0.0,
                                          )));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(AppLocalizations.of(context).findRides,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapInput(TextEditingController ctrl, String label, String hint,
      IconData icon, MaterialColor color) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: color.shade600, size: 18),
          labelStyle: TextStyle(fontSize: 13),
        ),
        style: TextStyle(fontSize: 14),
      ),
    );
  }
}

// ===== LOCATION SEARCH SCREEN =====
class LocationSearchScreen extends StatefulWidget {
  final String title;
  const LocationSearchScreen({required this.title, Key? key}) : super(key: key);
  @override
  _LocationSearchScreenState createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<GeoSuggestion> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    final text = _ctrl.text.trim();
    if (text.length < 2) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final list = await GeocodingService.searchEgypt(text);
      if (mounted) setState(() { _results = list; _searching = false; });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              decoration: InputDecoration(
                hintText: l.typeToSearch,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _ctrl.clear())
                        : null,
              ),
            ),
          ),
        ),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: _results.isEmpty
          ? Center(
              child: Text(
                _ctrl.text.trim().length < 2
                    ? l.typeToSearch
                    : (_searching ? l.searchingPlaces : l.noResultsFound),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            )
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = _results[i];
                return ListTile(
                  leading: Icon(Icons.location_on, color: Colors.red.shade400),
                  title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, s),
                );
              },
            ),
    );
  }
}

// ===== 7. VEHICLE SELECT SCREEN =====
class VehicleSelectScreen extends StatefulWidget {
  final String pickup;
  final String dropoff;
  final String time;
  final String date;
  final String? filter;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? scheduledAt;
  final double feluccaFare;
  final double hantourFare;

  VehicleSelectScreen({
    required this.pickup,
    required this.dropoff,
    required this.time,
    required this.date,
    this.filter,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.scheduledAt,
    this.feluccaFare = 0.0,
    this.hantourFare = 0.0,
  });

  @override
  _VehicleSelectScreenState createState() => _VehicleSelectScreenState();
}

class _VehicleSelectScreenState extends State<VehicleSelectScreen> {
  String? _selId, _selType, _selDriver;
  String? _activeFilter;
  double _proposedFare = 0;
  final TextEditingController _fareCtrl = TextEditingController();
  double _feluccaFare = 0;
  double _hantourFare = 0;
  int? _feluccaDurationMin; // 15, 30, or 60 — drives Felucca fare

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.filter;

    // Horse Carriage: use passed fare, or compute from distance (GPS + landmark lookup)
    _hantourFare = widget.hantourFare;
    if (_hantourFare <= 0) {
      _computeFares(); // resolves coords internally — safe even without dropoffLat
    }
    // Felucca fare is always set by duration selection, not distance

    // Auto-select the pre-filtered vehicle so the UI appears immediately
    if (_activeFilter != null) {
      _selType = _activeFilter;
      _selId = _activeFilter!.toLowerCase();
      _selDriver = '';
      if (_activeFilter == 'Horse Carriage') {
        // Only pre-fill fare if already known; otherwise wait for _computeFares() result
        if (_hantourFare > 0) {
          _proposedFare = _hantourFare;
          _fareCtrl.text = _hantourFare.toStringAsFixed(0);
        }
      }
      // Felucca: fare is set when user picks a duration below
    }
  }

  void _updateFareField() {
    // Felucca fare is driven by duration selection, not distance — skip it here
    if (_selType == 'Horse Carriage') {
      _proposedFare = _hantourFare;
      _fareCtrl.text = _hantourFare.toStringAsFixed(0);
    }
  }

  Future<void> _computeFares() async {
    // Resolve pickup: use passed coords, get GPS, or fall back to Luxor Corniche
    double pickupLat = widget.pickupLat ?? 0;
    double pickupLng = widget.pickupLng ?? 0;
    if (pickupLat == 0 || pickupLng == 0) {
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low);
        pickupLat = pos.latitude;
        pickupLng = pos.longitude;
      } catch (_) {
        pickupLat = 25.6872; // Luxor Corniche
        pickupLng = 32.6396;
      }
    }

    // Resolve dropoff: use passed coords, look up known landmarks, or use 2 km offset
    double dropLat = widget.dropoffLat ?? 0;
    double dropLng = widget.dropoffLng ?? 0;
    if (dropLat == 0 || dropLng == 0) {
      const landmarks = {
        'Luxor Temple':     [25.6987, 32.6390],
        'Karnak Temple':    [25.7188, 32.6571],
        'Nile Corniche':    [25.6872, 32.6370],
        'Winter Palace':    [25.6938, 32.6393],
        'Luxor Museum':     [25.7010, 32.6390],
        'Luxor Airport':    [25.6710, 32.7061],
        'Hatshepsut':       [25.7379, 32.6073],
        'Valley of Kings':  [25.7402, 32.6014],
      };
      bool found = false;
      for (final entry in landmarks.entries) {
        if (widget.dropoff.toLowerCase().contains(entry.key.toLowerCase())) {
          dropLat = entry.value[0];
          dropLng = entry.value[1];
          found = true;
          break;
        }
      }
      if (!found) {
        // Unknown destination — estimate with a 2 km offset from pickup
        dropLat = pickupLat + 0.018;
        dropLng = pickupLng;
      }
    }

    // Haversine distance for Horse Carriage (carriages don't follow car roads)
    final distKm = FareEstimator.distanceKm(pickupLat, pickupLng, dropLat, dropLng);
    if (!mounted) return;
    setState(() {
      _hantourFare = FareEstimator.estimate(distKm, vehicleType: 'horse_carriage').total;
      _updateFareField();
    });
  }

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).selectVehicle),
        centerTitle: true,
        leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          // Route summary bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(children: [
                        Icon(Icons.trip_origin, size: 14, color: Colors.green),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text(widget.pickup,
                                style: TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis)),
                      ]),
                      SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.location_on, size: 14, color: Colors.red),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text(widget.dropoff,
                                style: TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(widget.time,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(widget.date,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1),

          // Vehicle type selection
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(14),
              children: [
                if (_activeFilter == null || _activeFilter == 'Felucca') ...[
                  _buildTypeCard(
                    type: 'Felucca',
                    label: 'Nile Felucca Ride',
                    description: 'Scenic Nile sailing experience',
                    icon: Icons.sailing,
                    gradientA: Color(0xFF0D47A1),
                    gradientB: Color(0xFF42A5F5),
                    tagColor: Color(0xFF1976D2),
                    calcFare: _feluccaFare,
                  ),
                  if (_activeFilter == null) SizedBox(height: 12),
                ],
                if (_activeFilter == null || _activeFilter == 'Horse Carriage')
                  _buildTypeCard(
                    type: 'Horse Carriage',
                    label: 'Hantour Carriage Ride',
                    description: 'Traditional horse carriage through Luxor',
                    icon: Icons.directions,
                    gradientA: Color(0xFFBF360C),
                    gradientB: Color(0xFFFFB74D),
                    tagColor: Color(0xFF43A047),
                    calcFare: _hantourFare,
                  ),
              ],
            ),
          ),

          // Fare/duration section — shown once a type is selected
          if (_selType != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _selType == 'Felucca'
                  ? _buildFeluccaDurationPicker()
                  : _buildHantourFareField(),
            ),

          // Proceed button
          if (_selType != null)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (_selType == 'Felucca' && _feluccaDurationMin == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Please select a trip duration for your Felucca ride')));
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentScreen(
                          vehicleId: _selType!.toLowerCase(),
                          type: _selType!,
                          driver: '',
                          pickup: widget.pickup,
                          dropoff: widget.dropoff,
                          proposedFare: _proposedFare,
                          pickupLat: widget.pickupLat,
                          pickupLng: widget.pickupLng,
                          dropoffLat: widget.dropoffLat,
                          dropoffLng: widget.dropoffLng,
                          scheduledAt: widget.scheduledAt,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Proceed',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeCard({
    required String type,
    required String label,
    required String description,
    required IconData icon,
    required Color gradientA,
    required Color gradientB,
    required Color tagColor,
    required double calcFare,
  }) {
    final isSelected = _selType == type;
    final isFelucca = type == 'Felucca';
    final fare = isFelucca ? 0.0 : (calcFare > 0 ? calcFare : 30.0);
    return GestureDetector(
      onTap: () => setState(() {
        if (_selType != type) _feluccaDurationMin = null;
        _selType = type;
        _selId = type.toLowerCase();
        _selDriver = '';
        if (isFelucca) {
          _proposedFare = 0;
        } else {
          _proposedFare = fare;
          _fareCtrl.text = fare.toStringAsFixed(0);
        }
      }),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Colors.blue.shade600 : Colors.grey.shade200,
              width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
                color: isSelected
                    ? Colors.blue.withOpacity(0.15)
                    : Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 3))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [gradientA, gradientB],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 40)),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  SizedBox(height: 4),
                  Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  SizedBox(height: 8),
                  Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: isFelucca
                          ? Text('50–120 EGP',
                              style: TextStyle(color: tagColor, fontWeight: FontWeight.bold, fontSize: 13))
                          : Text('${fare.toStringAsFixed(0)} EGP',
                              style: TextStyle(color: tagColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
                    SizedBox(width: 4),
                    Flexible(child: Text(
                        isFelucca ? 'Time-based pricing' : 'Distance-based pricing',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11))),
                  ]),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.blue.shade600, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFeluccaDurationPicker() {
    final durations = [15, 30, 60];
    final fares = [50.0, 80.0, 120.0];
    final labels = ['15 min', '30 min', '1 hr'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select trip duration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        SizedBox(height: 10),
        Row(
          children: List.generate(3, (i) {
            final mins = durations[i];
            final total = (fares[i] * FareEstimator.feluccaSurge).round();
            final isSelected = _feluccaDurationMin == mins;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _feluccaDurationMin = mins;
                  _proposedFare = total.toDouble();
                  _fareCtrl.text = total.toString();
                }),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade700 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.blue.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(labels[i],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected ? Colors.white : Colors.black87,
                          )),
                      SizedBox(height: 4),
                      Text('$total EGP',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white70 : Colors.grey.shade600,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildHantourFareField() {
    final suggested = _hantourFare > 0
        ? _hantourFare
        : widget.hantourFare > 0
            ? widget.hantourFare
            : 30.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your price offer (EGP)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _fareCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter your offer',
                    suffixText: 'EGP',
                  ),
                  onChanged: (v) {
                    final d = double.tryParse(v);
                    if (d != null) setState(() => _proposedFare = d);
                  },
                ),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Suggested: ${suggested.toStringAsFixed(0)} EGP',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

}

/// Returns the minimum session fare for the vehicle type.
/// Felucca: 50 EGP (≤15 min), Horse Carriage: 30 EGP (≤500 m).
/// Surge is applied on top.
double _fareForType(String type) {
  final isFelucca = type == 'Felucca';
  final surge = isFelucca ? FareEstimator.feluccaSurge : FareEstimator.hantourSurge;
  final base = isFelucca ? 50.0 : 30.0; // minimum session fare
  return double.parse((base * surge).toStringAsFixed(0));
}

// ===== 8. PAYMENT SCREEN =====
class PaymentScreen extends StatefulWidget {
  final String vehicleId;
  final String type;
  final String driver;
  final String pickup;
  final String dropoff;
  final double proposedFare;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? scheduledAt;

  PaymentScreen({
    required this.vehicleId,
    required this.type,
    required this.driver,
    required this.pickup,
    required this.dropoff,
    this.proposedFare = 0,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.scheduledAt,
  });

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selected = 'Cash';
  final _promoCtrl = TextEditingController();
  double _discount = 0;
  bool _promoApplied = false;
  bool _promoLoading = false;
  String? _promoError;

  // Use the passenger's proposed fare when available, otherwise fall back to minimum fare
  double get _baseFare => widget.proposedFare > 0 ? widget.proposedFare : _fareForType(widget.type);

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _promoLoading = true; _promoError = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('promoCodes')
          .where('code', isEqualTo: code)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        setState(() { _promoError = 'Invalid or expired promo code'; _promoLoading = false; });
        return;
      }
      final data = snap.docs.first.data();
      final discountPct = (data['discountPercent'] as num?)?.toDouble() ?? 0;
      setState(() {
        _discount = (_baseFare * discountPct / 100).roundToDouble();
        _promoApplied = true;
        _promoLoading = false;
      });
    } catch (e) {
      setState(() { _promoError = 'Could not apply code: $e'; _promoLoading = false; });
    }
  }

  void _removePromo() {
    setState(() { _discount = 0; _promoApplied = false; _promoCtrl.clear(); _promoError = null; });
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final List<Map<String, dynamic>> methods = [
      {'name': l.cash, 'key': 'Cash', 'icon': Icons.money, 'desc': l.payAtEndOfRide},
      {'name': 'InstaPay', 'key': 'InstaPay', 'icon': Icons.account_balance, 'desc': 'Transfer via InstaPay after booking'},
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.paymentMethod),
        centerTitle: true,
        leading: IconButton(
            icon: Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Booking summary card
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Booking Summary',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.blue.shade800)),
                        SizedBox(height: 12),
                        _summaryRow(Icons.directions_boat, 'Vehicle',
                            '${widget.type} (${widget.vehicleId})'),
                        _summaryRow(Icons.drive_eta, 'Driver', widget.driver),
                        _summaryRow(Icons.trip_origin, l.from, widget.pickup),
                        _summaryRow(Icons.location_on, l.to, widget.dropoff),
                        Divider(height: 16),
                        Builder(builder: (context) {
                          final fare = _baseFare;
                          final serviceFee = (fare * 0.10).roundToDouble();
                          final total = (fare + serviceFee - _discount).clamp(0, double.infinity);
                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Ride price:', style: TextStyle(color: Colors.grey.shade700)),
                                  Text('EGP ${fare.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w500)),
                                ],
                              ),
                              SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Service fee:', style: TextStyle(color: Colors.grey.shade700)),
                                  Text('EGP ${serviceFee.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w500)),
                                ],
                              ),
                              if (_discount > 0) ...[
                                SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Promo discount:', style: TextStyle(color: Colors.green.shade700)),
                                    Text('- EGP ${_discount.toStringAsFixed(0)}',
                                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                              Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('EGP ${total.toStringAsFixed(0)}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Colors.blue.shade700)),
                                ],
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),

                  Text(l.paymentMethod,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),

                  ...methods.map((m) => GestureDetector(
                        onTap: () => setState(() => _selected = m['key'] as String),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _selected == m['key']
                                ? Colors.blue.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selected == m['key']
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade200,
                              width: _selected == m['key'] ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: _selected == m['key']
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 3))
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _selected == m['key']
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(m['icon'],
                                    color: _selected == m['key']
                                        ? Colors.blue.shade700
                                        : Colors.grey.shade600,
                                    size: 24),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m['name'] as String,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    Text(m['desc'] as String,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (_selected == m['key'])
                                Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: Colors.blue.shade700,
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.check,
                                      color: Colors.white, size: 14),
                                ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ),
          // InstaPay info
          if (_selected == 'InstaPay')
            Container(
              margin: EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                    SizedBox(width: 8),
                    Text('How InstaPay works', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 14)),
                  ]),
                  SizedBox(height: 8),
                  Text('1. Confirm your booking', style: TextStyle(fontSize: 13, color: Colors.blue.shade900)),
                  Text('2. Driver\'s InstaPay number will be shown', style: TextStyle(fontSize: 13, color: Colors.blue.shade900)),
                  Text('3. Transfer the fare via your bank app', style: TextStyle(fontSize: 13, color: Colors.blue.shade900)),
                  Text('4. Driver confirms receipt — no fees, instant', style: TextStyle(fontSize: 13, color: Colors.blue.shade900)),
                ],
              ),
            ),
          // Promo code field
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _promoCtrl,
                          enabled: !_promoApplied,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Promo code',
                            prefixIcon: Icon(Icons.local_offer, color: Colors.green.shade600, size: 18),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    _promoApplied
                        ? TextButton.icon(
                            onPressed: _removePromo,
                            icon: Icon(Icons.close, size: 16),
                            label: Text('Remove'),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                          )
                        : ElevatedButton(
                            onPressed: _promoLoading ? null : _applyPromo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _promoLoading
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text('Apply', style: TextStyle(color: Colors.white)),
                          ),
                  ],
                ),
                if (_promoApplied)
                  Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
                      SizedBox(width: 6),
                      Text('Promo applied! - EGP ${_discount.toStringAsFixed(0)} off',
                          style: TextStyle(color: Colors.green.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                if (_promoError != null)
                  Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(_promoError!, style: TextStyle(color: Colors.red.shade600, fontSize: 13)),
                  ),
              ],
            ),
          ),
          // Pay button
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SearchingDriverScreen(
                        pickup: widget.pickup,
                        dropoff: widget.dropoff,
                        vehicleType: widget.type,
                        driver: widget.driver,
                        payment: _selected,
                        fare: _baseFare,
                        proposedFare: widget.proposedFare,
                        pickupLat: widget.pickupLat,
                        pickupLng: widget.pickupLng,
                        dropoffLat: widget.dropoffLat,
                        dropoffLng: widget.dropoffLng,
                        scheduledAt: widget.scheduledAt,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('${l.pay} · $_selected',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade400),
          SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ===== 9. CASH PAYMENT SCREEN =====
class CashPaymentScreen extends StatefulWidget {
  final String vehicleId, type, pickup, dropoff, driver;
  CashPaymentScreen(
      {required this.vehicleId,
      required this.type,
      required this.pickup,
      required this.dropoff,
      required this.driver});

  @override
  _CashPaymentScreenState createState() => _CashPaymentScreenState();
}

class _CashPaymentScreenState extends State<CashPaymentScreen> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(l.cash),
          centerTitle: true,
          leading:
              IconButton(icon: Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.money, size: 32, color: Colors.green.shade700),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cash Payment',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: Colors.green.shade700)),
                        Text('Pay your driver at end of ride',
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Text('Trip Details',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            _row('Vehicle', '${widget.type} (${widget.vehicleId})'),
            _row('Driver', widget.driver),
            _row(l.from, widget.pickup),
            _row(l.to, widget.dropoff),
            _row('Ride Price', 'EGP ${(_fareForType(widget.type) * 0.9).toStringAsFixed(0)}'),
            _row('Service Fee (10%)', 'EGP ${(_fareForType(widget.type) * 0.1).toStringAsFixed(0)}'),
            Divider(height: 20),
            _row('Total', 'EGP ${_fareForType(widget.type).toStringAsFixed(0)}', bold: true),
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Instructions',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 13)),
                  SizedBox(height: 8),
                  Text('• Driver confirms the final amount\n• Pay upon ride completion\n• Request a receipt',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
            Spacer(),
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: Text('I agree to pay EGP ${_fareForType(widget.type).toStringAsFixed(0)} in cash',
                  style: TextStyle(fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _agreed
                    ? () async {
                        try {
                          final trip = await DatabaseService.instance.requestTrip(
                            passengerId: AuthService.currentUserId,
                            passengerName: AuthService.currentUserName.isNotEmpty
                                ? AuthService.currentUserName
                                : 'Passenger',
                            vehicleType: VehicleTypeX.fromString(widget.type),
                            pickup: widget.pickup,
                            dropoff: widget.dropoff,
                            fare: _fareForType(widget.type),
                            paymentMethod: PaymentMethod.cash,
                          );
                          if (context.mounted) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => BookingConfirmedScreen(
                                        vehicleId: widget.vehicleId,
                                        type: widget.type,
                                        driver: widget.driver,
                                        pickup: widget.pickup,
                                        dropoff: widget.dropoff,
                                        payment: 'Cash',
                                        tripId: trip.id)));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Booking failed: $e'),
                                    duration: Duration(seconds: 8)));
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _agreed ? Colors.blue.shade700 : Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Confirm Booking',
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

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: bold ? Colors.blue.shade700 : Colors.black,
                  fontSize: bold ? 16 : 14)),
        ],
      ),
    );
  }
}

// ===== 10. CREDIT CARD SCREEN =====
class CreditCardPaymentScreen extends StatefulWidget {
  final String vehicleId, type, pickup, dropoff, driver;
  CreditCardPaymentScreen(
      {required this.vehicleId,
      required this.type,
      required this.pickup,
      required this.dropoff,
      required this.driver});

  @override
  _CreditCardPaymentScreenState createState() =>
      _CreditCardPaymentScreenState();
}

class _CreditCardPaymentScreenState extends State<CreditCardPaymentScreen> {
  final _numCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  bool _processing = false;
  int _prevExpLen = 0;

  @override
  void dispose() {
    _numCtrl.dispose();
    _nameCtrl.dispose();
    _expCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String _formatNum(String n) {
    String c = n.replaceAll(' ', '');
    if (c.length <= 16)
      return c
          .replaceAllMapped(RegExp(r'.{1,4}'), (m) => '${m.group(0)} ')
          .trim();
    return n;
  }

  void _pay() async {
    if (_numCtrl.text.length < 16) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Enter valid 16-digit card number')));
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Enter card holder name')));
      return;
    }
    if (!_expCtrl.text.contains('/') || _expCtrl.text.length < 5) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Enter valid expiry (MM/YY)')));
      return;
    }
    if (_cvvCtrl.text.length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Enter valid 3-digit CVV')));
      return;
    }
    setState(() => _processing = true);
    final trip = await DatabaseService.instance.requestTrip(
      passengerId: AuthService.currentUserId,
      passengerName: AuthService.currentUserName.isNotEmpty ? AuthService.currentUserName : 'Passenger',
      vehicleType: VehicleTypeX.fromString(widget.type),
      pickup: widget.pickup,
      dropoff: widget.dropoff,
      fare: _fareForType(widget.type),
      paymentMethod: PaymentMethod.creditCard,
    );
    Future.delayed(Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => BookingConfirmedScreen(
                  vehicleId: widget.vehicleId,
                  type: widget.type,
                  driver: widget.driver,
                  pickup: widget.pickup,
                  dropoff: widget.dropoff,
                  payment: 'Credit Card',
                  tripId: trip.id)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('Credit Card'),
          centerTitle: true,
          leading: IconButton(
              icon: Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card preview
            Container(
              height: 190,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.blue.shade800, Colors.blue.shade500]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 14,
                      offset: Offset(0, 6))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.credit_card, color: Colors.white, size: 36),
                      Text('FluTour',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ],
                  ),
                  Text(
                    _numCtrl.text.isEmpty
                        ? '•••• •••• •••• ••••'
                        : _formatNum(_numCtrl.text),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CARD HOLDER',
                            style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Text(
                            _nameCtrl.text.isEmpty
                                ? 'YOUR NAME'
                                : _nameCtrl.text.toUpperCase(),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('EXPIRES',
                            style: TextStyle(color: Colors.white54, fontSize: 10)),
                        Text(
                            _expCtrl.text.isEmpty ? 'MM/YY' : _expCtrl.text,
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 28),
            _label('Card Number'),
            SizedBox(height: 8),
            TextField(
              controller: _numCtrl,
              keyboardType: TextInputType.number,
              maxLength: 16,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: '1234 5678 9012 3456',
                prefixIcon: Icon(Icons.credit_card),
                counterText: '',
              ),
            ),
            SizedBox(height: 14),
            _label('Card Holder Name'),
            SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: 'Full Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Expiry Date'),
                  SizedBox(height: 8),
                  TextField(
                    controller: _expCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    onChanged: (v) {
                      if (v.length == 2 &&
                          !v.contains('/') &&
                          v.length > _prevExpLen) {
                        _expCtrl.text = v + '/';
                        _expCtrl.selection =
                            TextSelection.fromPosition(TextPosition(offset: 3));
                      }
                      _prevExpLen = _expCtrl.text.length;
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: 'MM/YY',
                      counterText: '',
                    ),
                  ),
                ]),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('CVV'),
                  SizedBox(height: 8),
                  TextField(
                    controller: _cvvCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: '•••',
                      counterText: '',
                    ),
                  ),
                ]),
              ),
            ]),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Amount',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('EGP ${_fareForType(widget.type).toStringAsFixed(0)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.blue.shade700)),
                ],
              ),
            ),
            SizedBox(height: 24),
            _processing
                ? Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _pay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Pay EGP ${_fareForType(widget.type).toStringAsFixed(0)}',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
            SizedBox(height: 12),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Secured with SSL encryption',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) =>
      Text(t, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
}

// ===== 11. MOBILE WALLET SCREEN =====
class MobileWalletScreen extends StatefulWidget {
  final String vehicleId, type, pickup, dropoff, driver;
  MobileWalletScreen(
      {required this.vehicleId,
      required this.type,
      required this.pickup,
      required this.dropoff,
      required this.driver});

  @override
  _MobileWalletScreenState createState() => _MobileWalletScreenState();
}

class _MobileWalletScreenState extends State<MobileWalletScreen> {
  final _mobileCtrl = TextEditingController();
  String _provider = 'Vodafone Cash';
  bool _processing = false;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = ['Vodafone Cash', 'Orange Money', 'Etisalat Cash', 'Credit Wallet'];
    return Scaffold(
      appBar: AppBar(
          title: Text('Mobile Wallet'),
          centerTitle: true,
          leading: IconButton(
              icon: Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200)),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: Colors.orange.shade700, size: 32),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mobile Wallet',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.orange.shade700)),
                        Text('Fast & secure wallet payment',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Text('Wallet Provider',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _provider,
                  isExpanded: true,
                  items: providers
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _provider = v);
                  },
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('Mobile Number',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '01XXXXXXXXX',
                prefixIcon: Icon(Icons.phone, color: Colors.orange.shade600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.orange.shade600, width: 2),
                ),
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('EGP ${_fareForType(widget.type).toStringAsFixed(0)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.orange.shade700)),
                ],
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.shield, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('Secured with SSL encryption',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 24),
            _processing
                ? Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () async {
                        final mobile = _mobileCtrl.text.trim();
                        if (mobile.isEmpty ||
                            mobile.length != 11 ||
                            !mobile.startsWith('01')) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  'Enter valid 11-digit number starting with 01')));
                          return;
                        }
                        setState(() => _processing = true);
                        final trip = await DatabaseService.instance.requestTrip(
                          passengerId: AuthService.currentUserId,
                          passengerName: AuthService.currentUserName.isNotEmpty ? AuthService.currentUserName : 'Passenger',
                          vehicleType: VehicleTypeX.fromString(widget.type),
                          pickup: widget.pickup,
                          dropoff: widget.dropoff,
                          fare: _fareForType(widget.type),
                          paymentMethod: PaymentMethod.mobileWallet,
                        );
                        Future.delayed(Duration(seconds: 2), () {
                          if (!mounted) return;
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => BookingConfirmedScreen(
                                      vehicleId: widget.vehicleId,
                                      type: widget.type,
                                      driver: widget.driver,
                                      pickup: widget.pickup,
                                      dropoff: widget.dropoff,
                                      payment: _provider,
                                      tripId: trip.id)));
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Confirm Payment',
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

// ===== 12. BOOKING CONFIRMED + ACTIVE RIDE TRACKER =====
class BookingConfirmedScreen extends StatefulWidget {
  final String vehicleId, type, driver, pickup, dropoff, payment;
  final String? tripId;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? scheduledAt;

  BookingConfirmedScreen({
    required this.vehicleId,
    required this.type,
    required this.driver,
    required this.pickup,
    required this.dropoff,
    required this.payment,
    this.tripId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.scheduledAt,
  });

  @override
  _BookingConfirmedScreenState createState() => _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState extends State<BookingConfirmedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  int _rideStep = 0; // 0=confirmed, 1=driver on way, 2=arrived, 3=in progress
  StreamSubscription? _tripSub;
  Timer? _pollTimer;
  bool _navigated = false;
  LatLng? _driverLoc;
  String? _driverId;
  StreamSubscription? _driverLocSub;
  final MapController _mapCtrl = MapController();
  List<LatLng>? _routePoints;
  List<LatLng>? _tripRoutePoints;
  DateTime? _lastRouteFetch;
  double? _counterFare;
  String? _driverInstapayPhone;
  String? _driverPhone;
  String? _vehiclePhotoUrl;
  String? _driverPhotoUrl;
  double _driverRating = 0.0;
  DateTime? _tripStartedAt;
  bool _counterPending = false;
  double _actualFare = 0.0;
  final GlobalKey _shareTripKey = GlobalKey();

  double get _displayFare => _actualFare > 0 ? _actualFare : _fareForType(widget.type);

  List<Map<String, dynamic>> _steps(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      {'label': l.bookingConfirmed, 'icon': Icons.check_circle, 'color': Colors.green},
      {'label': l.driverOnTheWay, 'icon': Icons.drive_eta, 'color': Colors.blue},
      {'label': l.driverArrived, 'icon': Icons.where_to_vote, 'color': Colors.orange},
      {'label': l.rideInProgress, 'icon': Icons.sailing, 'color': Colors.teal},
    ];
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _scaleAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();

    // Use cached route instantly, then fetch ORS route async to update
    if (RouteService.lastResult != null) {
      _tripRoutePoints = RouteService.lastResult!.points;
    }
    if (widget.pickupLat != null && widget.pickupLng != null &&
        widget.dropoffLat != null && widget.dropoffLng != null) {
      final pickup = LatLng(widget.pickupLat!, widget.pickupLng!);
      final dropoff = LatLng(widget.dropoffLat!, widget.dropoffLng!);
      RouteService.fetchRoute(pickup, dropoff).then((result) {
        if (!mounted) return;
        if (result != null && result.points.length > 1) {
          setState(() => _tripRoutePoints = result.points);
        }
      });
    }

    if (widget.tripId != null) {
      // Real-time listener — primary mechanism
      _tripSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .snapshots()
          .listen(
        (doc) {
          if (!mounted || _navigated) return;
          if (!doc.exists) return;
          final data = doc.data()!;
          _handleStatusUpdate(data['status'] ?? '');
          // Detect counter offers from driver
          final counterFare = (data['counterFare'] as num?)?.toDouble();
          final negotiationStatus = data['negotiationStatus'] as String? ?? 'open';
          if (negotiationStatus == 'countered' && counterFare != null && counterFare > 0) {
            setState(() {
              _counterFare = counterFare;
              _counterPending = true;
            });
          }
          if (negotiationStatus == 'agreed') {
            setState(() { _counterPending = false; _counterFare = null; });
          }
          // Extract agreed fare (may update after counter-offer negotiation)
          final rawFare = data['agreedFare'] ?? data['fare'];
          final tripFare = (rawFare as num?)?.toDouble();
          if (tripFare != null && tripFare > 0 && _actualFare != tripFare) {
            setState(() => _actualFare = tripFare);
          }
          // Extract driver phone and InstaPay phone once driver accepts
          final instapayPhone = data['driverInstapayPhone'] as String?;
          if (instapayPhone != null && _driverInstapayPhone != instapayPhone) {
            setState(() => _driverInstapayPhone = instapayPhone);
          }
          final driverPhone = data['driverPhone'] as String?;
          if (driverPhone != null && driverPhone.isNotEmpty && _driverPhone != driverPhone) {
            setState(() => _driverPhone = driverPhone);
          }
          // Start driver location listener once we have driverId
          final driverId = data['driverId'] as String?;
          if (driverId != null && driverId.isNotEmpty && _driverId != driverId) {
            _driverId = driverId;
            _startDriverLocationListener(driverId);
            // Fetch vehicle photo + real driver rating
            FirebaseFirestore.instance
                .collection('drivers')
                .doc(driverId)
                .get()
                .then((d) {
              if (!mounted) return;
              final vehicleUrl = d.data()?['vehiclePhotoUrl'] as String?;
              final driverUrl = d.data()?['photoUrl'] as String?;
              final rating = (d.data()?['rating'] as num?)?.toDouble() ?? 0.0;
              setState(() {
                if (vehicleUrl != null && vehicleUrl.isNotEmpty) _vehiclePhotoUrl = vehicleUrl;
                if (driverUrl != null && driverUrl.isNotEmpty) _driverPhotoUrl = driverUrl;
                if (rating > 0) _driverRating = rating;
              });
            }).catchError((_) {});
          }
          // Record when trip actually starts (for duration calculation)
          if (data['status'] == 'in_progress' && _tripStartedAt == null) {
            final ts = data['startedAt'];
            _tripStartedAt = ts is Timestamp ? ts.toDate() : DateTime.now();
          }
        },
        onError: (_) {
          // Listener failed — polling timer will catch the next status change
        },
      );

      // Polling fallback — checks every 5 s in case the listener misses an update
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (widget.tripId == null || _navigated || !mounted) return;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('trips')
              .doc(widget.tripId)
              .get();
          if (!doc.exists) return;
          _handleStatusUpdate(doc.data()?['status'] ?? '');
        } catch (_) {}
      });

    }
  }

  void _handleStatusUpdate(String status) {
    if (!mounted || _navigated) return;
    if (status == 'completed') {
      _navigated = true;
      _tripSub?.cancel();
      _pollTimer?.cancel();
      // Calculate real duration from trip start timestamp
      final durationMin = _tripStartedAt != null
          ? DateTime.now().difference(_tripStartedAt!).inMinutes.clamp(1, 999)
          : 0;
      // Calculate straight-line distance from coordinates if available
      double distanceKm = 0.0;
      if (widget.pickupLat != null && widget.pickupLng != null &&
          widget.dropoffLat != null && widget.dropoffLng != null) {
        final meters = const Distance().as(
          LengthUnit.Meter,
          LatLng(widget.pickupLat!, widget.pickupLng!),
          LatLng(widget.dropoffLat!, widget.dropoffLng!),
        );
        distanceKm = meters / 1000.0;
      }
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => TripCompletionScreen(
                    driverName: widget.driver,
                    pickup: widget.pickup,
                    dropoff: widget.dropoff,
                    distanceKm: distanceKm,
                    durationMin: durationMin,
                    fareTotal: _displayFare,
                  )));
      return;
    }
    int step = _rideStep;
    if (status == 'accepted') step = 1;
    if (status == 'arrived') step = 2;
    if (status == 'in_progress') step = 3;
    setState(() => _rideStep = step);
  }

  String _formatScheduled(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  void _startDriverLocationListener(String driverId) {
    _driverLocSub?.cancel();
    final ref = FirebaseDatabase.instance.ref('drivers_location/$driverId');
    _driverLocSub = ref.onValue.listen((event) {
      if (!mounted) return;
      final val = event.snapshot.value;
      if (val == null) return;
      final map = Map<String, dynamic>.from(val as Map);
      final lat = (map['lat'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final loc = LatLng(lat, lng);
      setState(() => _driverLoc = loc);
      // Move map to driver
      try { _mapCtrl.move(loc, 15.0); } catch (_) {}
      // Route to dropoff when in progress, otherwise route to pickup
      final isInProgress = _rideStep >= 3;
      final destLat = isInProgress ? widget.dropoffLat : widget.pickupLat;
      final destLng = isInProgress ? widget.dropoffLng : widget.pickupLng;
      if (destLat != null && destLng != null) {
        final dest = LatLng(destLat, destLng);
        // Throttle ORS calls to once every 30 seconds to stay within free tier
        final now = DateTime.now();
        if (_lastRouteFetch == null || now.difference(_lastRouteFetch!).inSeconds >= 30) {
          _lastRouteFetch = now;
          RouteService.fetchRoute(loc, dest).then((result) {
            if (!mounted) return;
            if (result != null && result.points.length > 1) {
              setState(() => _routePoints = result.points);
            }
          });
        }
      }
    });
  }

  Future<void> _triggerSOS() async {
    // Get current GPS position
    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Use pickup coords as fallback
      lat = widget.pickupLat;
      lng = widget.pickupLng;
    }

    final locationText = (lat != null && lng != null)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : 'Location unavailable';

    final message = Uri.encodeComponent(
      '🆘 EMERGENCY — FluTour passenger needs help!\n'
      'Driver: ${widget.driver}\n'
      'Trip: ${widget.pickup} → ${widget.dropoff}\n'
      'Location: $locationText',
    );

    // Try WhatsApp first
    final waUri = Uri.parse('whatsapp://send?text=$message');
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri);
      return;
    }

    // Fallback to SMS
    final smsUri = Uri.parse('sms:?body=$message');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
      return;
    }

    // Last resort — show dialog with location
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency Info'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share this with emergency services:'),
              SizedBox(height: 8),
              SelectableText(locationText,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _shareTrip() async {
    try {
      final boundary = _shareTripKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.5);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final bytes = byteData.buffer.asUint8List();
          final dir = await getTemporaryDirectory();
          final file = await File('${dir.path}/flutour_trip.png').writeAsBytes(bytes);
          await Share.shareXFiles([XFile(file.path)], subject: 'My FluTour Ride - Luxor');
          return;
        }
      }
    } catch (_) {}
    // Fallback to text
    final text = 'I\'m on a FluTour ride in Luxor!\nFrom: ${widget.pickup}\nTo: ${widget.dropoff}';
    Share.share(text, subject: 'My FluTour Ride');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tripSub?.cancel();
    _pollTimer?.cancel();
    _driverLocSub?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = _steps(context);
    final step = steps[_rideStep];
    final Color stepColor = step['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.rideStatus),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Animated status icon
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: stepColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(step['icon'] as IconData, size: 72, color: stepColor),
              ),
            ),
            SizedBox(height: 16),
            Text(step['label'] as String,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: stepColor)),
            SizedBox(height: 8),
            Text(
              _rideStep == 0
                  ? 'Your booking is confirmed!'
                  : _rideStep == 1
                      ? '${widget.driver} is heading to your location'
                      : _rideStep == 2
                          ? 'Your driver has arrived. Enjoy your ride!'
                          : 'Your Nile adventure is underway!',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),

            // Scheduled ride chip
            if (widget.scheduledAt != null)
              Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, color: Colors.blue.shade700, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Scheduled: ${_formatScheduled(widget.scheduledAt!)}',
                      style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Counter offer banner — shown when driver sends a counter
            if (_counterPending && _counterFare != null)
              Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Icon(Icons.price_change, color: Colors.orange.shade700),
                      SizedBox(width: 8),
                      Text('Driver Counter Offer',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange.shade800)),
                    ]),
                    SizedBox(height: 8),
                    Text('${_counterFare!.toStringAsFixed(0)} EGP',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('trips')
                                  .doc(widget.tripId)
                                  .update({'negotiationStatus': 'declined_counter'});
                              setState(() { _counterPending = false; _counterFare = null; });
                            },
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: Text('Decline'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('trips')
                                  .doc(widget.tripId)
                                  .update({
                                'fare': _counterFare,
                                'negotiationStatus': 'agreed',
                              });
                              setState(() { _counterPending = false; _counterFare = null; });
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600),
                            child: Text('Accept', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Progress steps
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
                  ]),
              child: Column(
                children: List.generate(steps.length, (i) {
                  final done = i <= _rideStep;
                  final active = i == _rideStep;
                  return Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: done
                              ? (steps[i]['color'] as Color)
                              : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          done ? Icons.check : Icons.circle,
                          color: done ? Colors.white : Colors.grey.shade400,
                          size: done ? 18 : 10,
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(steps[i]['label'] as String,
                                style: TextStyle(
                                    fontWeight: active
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: done ? Colors.black : Colors.grey,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                      if (active)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: stepColor),
                        ),
                    ],
                  );
                })
                    .expand((w) => [
                          w,
                          Padding(
                            padding: EdgeInsets.only(left: 15),
                            child: Container(
                                height: 20, width: 2, color: Colors.grey.shade200),
                          ),
                        ])
                    .toList()
                  ..removeLast(),
              ),
            ),
            SizedBox(height: 20),

            // Live map — always shown when coordinates are known
            if (widget.pickupLat != null && widget.pickupLng != null)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                clipBehavior: Clip.hardEdge,
                child: FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _driverLoc ?? (widget.pickupLat != null && widget.pickupLng != null
                          ? LatLng(widget.pickupLat!, widget.pickupLng!)
                          : LatLng(25.6872, 32.6396)),
                      initialZoom: 14.5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                        userAgentPackageName: 'com.flutour.passenger',
                      ),
                      if (_routePoints != null && _routePoints!.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints!,
                              strokeWidth: 4.0,
                              color: Colors.blue.shade600,
                            ),
                          ],
                        )
                      else if (_tripRoutePoints != null && _tripRoutePoints!.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _tripRoutePoints!,
                              strokeWidth: 4.0,
                              color: Colors.teal.shade600,
                            ),
                          ],
                        ),
                      MarkerLayer(markers: [
                        if (_driverLoc != null)
                          Marker(
                            width: 44,
                            height: 44,
                            point: _driverLoc!,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                              ),
                              child: Icon(Icons.directions_car, color: Colors.white, size: 24),
                            ),
                          ),
                        if (widget.pickupLat != null && widget.pickupLng != null)
                          Marker(
                            width: 36,
                            height: 36,
                            point: LatLng(widget.pickupLat!, widget.pickupLng!),
                            child: Icon(Icons.trip_origin, color: Colors.green, size: 32),
                          ),
                        if (widget.dropoffLat != null && widget.dropoffLng != null)
                          Marker(
                            width: 36,
                            height: 36,
                            point: LatLng(widget.dropoffLat!, widget.dropoffLng!),
                            child: Icon(Icons.location_on, color: Colors.red, size: 32),
                          ),
                      ]),
                    ],
                  ),
              ),

            SizedBox(height: 20),

            // Driver & ride info
            RepaintBoundary(
              key: _shareTripKey,
              child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
                  ]),
              child: Column(
                children: [
                  // Vehicle photo strip (shown when available)
                  if (_vehiclePhotoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _vehiclePhotoUrl!,
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => SizedBox.shrink(),
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        radius: 26,
                        backgroundImage: _driverPhotoUrl != null && _driverPhotoUrl!.isNotEmpty
                            ? NetworkImage(_driverPhotoUrl!) as ImageProvider
                            : null,
                        child: _driverPhotoUrl == null || _driverPhotoUrl!.isEmpty
                            ? Text(widget.driver.isNotEmpty ? widget.driver[0] : '?',
                                style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20))
                            : null,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.driver,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('${widget.type} · ${widget.vehicleId}',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 13)),
                            Row(children: [
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(_driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—',
                                  style: TextStyle(
                                      color: Colors.grey.shade600, fontSize: 12)),
                            ]),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final phone = _driverPhone ?? '';
                          if (phone.isEmpty) return;
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        child: Column(
                          children: [
                            Icon(Icons.phone, color: _driverPhone != null ? Colors.blue.shade700 : Colors.grey),
                            SizedBox(height: 4),
                            Text(l.call, style: TextStyle(color: _driverPhone != null ? Colors.blue.shade700 : Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _shareTrip,
                        child: Column(
                          children: [
                            Icon(Icons.share, color: Colors.teal.shade600),
                            SizedBox(height: 4),
                            Text('Share', style: TextStyle(color: Colors.teal.shade600, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 20),
                  _infoRow(Icons.trip_origin, Colors.green, l.from, widget.pickup),
                  SizedBox(height: 6),
                  _infoRow(Icons.location_on, Colors.red, l.to, widget.dropoff),
                  Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${l.paymentMethod}: ${widget.payment}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      Text('EGP ${_displayFare.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                              fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            ),
            SizedBox(height: 20),

            // InstaPay transfer panel — shown only for InstaPay payment once driver accepts
            if (_rideStep >= 1 && widget.payment == 'InstaPay' && _driverInstapayPhone != null && _driverInstapayPhone!.isNotEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.account_balance, color: Colors.blue.shade700),
                      SizedBox(width: 8),
                      Text('InstaPay Transfer',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue.shade800)),
                    ]),
                    SizedBox(height: 12),
                    Text('Transfer the fare to your driver:',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.phone, color: Colors.blue.shade700, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Driver InstaPay Number',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                Builder(builder: (_) {
                                  final displayNum = (_driverInstapayPhone?.isNotEmpty == true)
                                      ? _driverInstapayPhone!
                                      : (_driverPhone?.isNotEmpty == true)
                                          ? _driverPhone!
                                          : null;
                                  return Text(
                                    displayNum ?? '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: Colors.blue.shade800,
                                        letterSpacing: 1.2),
                                  );
                                }),
                              ],
                            ),
                          ),
                          Builder(builder: (ctx) {
                            final displayNum = (_driverInstapayPhone?.isNotEmpty == true)
                                ? _driverInstapayPhone!
                                : (_driverPhone?.isNotEmpty == true)
                                    ? _driverPhone!
                                    : null;
                            if (displayNum == null) return SizedBox.shrink();
                            return IconButton(
                              icon: Icon(Icons.copy, color: Colors.blue.shade600),
                              tooltip: 'Copy number',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: displayNum));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Number copied to clipboard')));
                                }
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Amount to transfer: EGP ${_displayFare.toStringAsFixed(0)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 14),
                    ),
                    SizedBox(height: 6),
                    Text('Open your bank app → InstaPay → enter number above → transfer amount.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),

            if (_rideStep == 3) ...[
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: Icon(Icons.home, color: Colors.white),
                  label: Text(l.backToHome,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: Icon(Icons.home),
                  label: Text('Back to Home', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade700),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
            SizedBox(height: 20),
          ],
        ),
      ),
      floatingActionButton: _rideStep >= 1
          ? FloatingActionButton.small(
              heroTag: 'sos_fab',
              onPressed: _triggerSOS,
              backgroundColor: Colors.red.shade600,
              child: Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _infoRow(IconData icon, Color color, String label, String val) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Expanded(
            child: Text(val,
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

// ===== 13. MY TRIPS TAB =====
class MyTripsTab extends StatefulWidget {
  @override
  _MyTripsTabState createState() => _MyTripsTabState();
}

class _MyTripsTabState extends State<MyTripsTab> {
  String _filter = 'All';
  final _filters = ['All', 'Completed', 'Cancelled'];
  late Future<List<TripModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getTripHistory(AuthService.currentUserId);
  }

  List<TripModel> _applyFilter(List<TripModel> trips) {
    if (_filter == 'All') return trips;
    return trips.where((t) => t.status.label == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.tabTrips), centerTitle: true),
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
                  Text('Could not load trips',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future =
                        DatabaseService.instance
                            .getTripHistory(AuthService.currentUserId)),
                    child: Text(l.retry),
                  ),
                ],
              ),
            );
          }
          final all = snap.data ?? [];
          final filtered = _applyFilter(all);

          return Column(
            children: [
              // Filter chips
              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: _filters.map((f) {
                    final selected = _filter == f;
                    final filterLabel = {
                      'All': l.all,
                      'Completed': l.completed,
                      'Cancelled': l.cancelled,
                    }[f] ?? f;
                    return Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected ? Colors.blue.shade700 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: selected ? Colors.blue.shade700 : Colors.grey.shade300),
                          ),
                          child: Text(filterLabel,
                              style: TextStyle(
                                  color: selected ? Colors.white : Colors.grey.shade700,
                                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sailing, size: 64, color: Colors.grey.shade300),
                            SizedBox(height: 16),
                            Text(l.noTripsYet,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                            SizedBox(height: 8),
                            Text('Book your first Nile ride!',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _buildTripCard(context, filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, TripModel trip) {
    final bool done = trip.status == TripStatus.completed;
    final Color statusColor = done
        ? Colors.green
        : trip.status == TripStatus.cancelled
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: done ? Colors.blue.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  trip.vehicleType == VehicleType.felucca ? Icons.sailing : Icons.directions,
                  color: done ? Colors.blue.shade700 : Colors.red.shade400,
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.vehicleType.label,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(trip.driverName.isNotEmpty ? trip.driverName : '—',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(trip.status.label,
                        style: TextStyle(
                            color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    done ? 'EGP ${trip.fare.toStringAsFixed(0)}' : '-',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Row(children: [
                  Icon(Icons.trip_origin, size: 13, color: Colors.green),
                  SizedBox(width: 6),
                  Expanded(
                      child: Text(trip.pickup,
                          style: TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis)),
                ]),
                SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.location_on, size: 13, color: Colors.red),
                  SizedBox(width: 6),
                  Expanded(
                      child: Text(trip.dropoff,
                          style: TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 12, color: Colors.grey),
              SizedBox(width: 4),
              Text(trip.createdAt.toString().substring(0, 10),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              SizedBox(width: 12),
              Icon(Icons.payment, size: 12, color: Colors.grey),
              SizedBox(width: 4),
              Text(trip.paymentMethod.label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Spacer(),
              GestureDetector(
                onTap: () => _showReceipt(context, trip),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200)),
                  child: Row(children: [
                    Icon(Icons.receipt_long, size: 13, color: Colors.teal.shade700),
                    SizedBox(width: 4),
                    Text('Receipt',
                        style: TextStyle(
                            color: Colors.teal.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
              SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => VehicleSelectScreen(
                              pickup: trip.pickup,
                              dropoff: trip.dropoff,
                              time: '20:00 PM',
                              date: 'Today',
                            ))),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200)),
                  child: Row(children: [
                    Icon(Icons.replay, size: 13, color: Colors.blue.shade700),
                    SizedBox(width: 4),
                    Text('Re-book',
                        style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
              SizedBox(width: 8),
              if (done && trip.passengerRating == 0)
                GestureDetector(
                  onTap: () => _rateDialog(context, trip),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300)),
                    child: Row(children: [
                      Icon(Icons.star_border, size: 14, color: Colors.amber),
                      SizedBox(width: 4),
                      Text('Rate',
                          style: TextStyle(
                              color: Colors.amber.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              if (done && trip.passengerRating > 0)
                Row(
                    children: List.generate(
                        5,
                        (i) => Icon(
                            i < trip.passengerRating ? Icons.star : Icons.star_border,
                            size: 14,
                            color: Colors.amber))),
            ],
          ),
        ],
      ),
    );
  }

  void _showReceipt(BuildContext context, TripModel trip) {
    final fare = trip.fare;
    final serviceFee = fare * 0.10;
    final driverPay = fare * 0.85;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            SizedBox(height: 16),
            Row(children: [
              Icon(Icons.receipt_long, color: Colors.teal.shade700),
              SizedBox(width: 8),
              Text('Trip Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Spacer(),
              IconButton(
                icon: Icon(Icons.share, color: Colors.teal.shade600),
                onPressed: () async {
                  final receiptText = '''
🚕 FluTour Trip Receipt
━━━━━━━━━━━━━━━━━━━━
Trip ID: ${trip.id.substring(0, 8).toUpperCase()}
Date: ${trip.createdAt.toString().substring(0, 16)}
━━━━━━━━━━━━━━━━━━━━
Vehicle: ${trip.vehicleType.label}
Driver: ${trip.driverName.isNotEmpty ? trip.driverName : '—'}
━━━━━━━━━━━━━━━━━━━━
📍 From: ${trip.pickup}
📍 To: ${trip.dropoff}
━━━━━━━━━━━━━━━━━━━━
Subtotal: ${(fare - serviceFee).toStringAsFixed(0)} EGP
Service Fee: ${serviceFee.toStringAsFixed(0)} EGP
💰 Total: ${fare.toStringAsFixed(0)} EGP
Payment: ${trip.paymentMethod.label}
━━━━━━━━━━━━━━━━━━━━
FluTour — Luxor, Egypt
''';
                  Share.share(receiptText.trim(), subject: 'FluTour Trip Receipt');
                },
              ),
            ]),
            Divider(height: 20),
            _receiptRow('Trip ID', trip.id.substring(0, 8).toUpperCase()),
            _receiptRow('Date', trip.createdAt.toString().substring(0, 16)),
            _receiptRow('Vehicle', trip.vehicleType.label),
            _receiptRow('Driver', trip.driverName.isNotEmpty ? trip.driverName : '—'),
            Divider(height: 20),
            _receiptRow('From', trip.pickup),
            _receiptRow('To', trip.dropoff),
            Divider(height: 20),
            _receiptRow('Subtotal', '${(fare - serviceFee).toStringAsFixed(0)} EGP'),
            _receiptRow('Service Fee (10%)', '${serviceFee.toStringAsFixed(0)} EGP'),
            Divider(height: 12),
            _receiptRow('Total', '${fare.toStringAsFixed(0)} EGP', bold: true, color: Colors.teal.shade700),
            _receiptRow('Payment', trip.paymentMethod.label),
            SizedBox(height: 16),
            Center(child: Text('Thank you for riding with FluTour!',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Spacer(),
          Text(value, style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 15 : 13,
              color: color ?? Colors.black87)),
        ],
      ),
    );
  }

  void _rateDialog(BuildContext context, TripModel trip) {
    int tempRating = 5;
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Rate Your Ride'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'How was your ${trip.vehicleType.label} ride with ${trip.driverName}?',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setS(() => tempRating = i + 1),
                    child: Icon(
                      i < tempRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Leave a comment (optional)',
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
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final comment = commentCtrl.text.trim();
                commentCtrl.dispose();
                await DatabaseService.instance.rateTrip(trip.id, tempRating,
                    comment: comment.isNotEmpty ? comment : null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
              child: Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 14. PROFILE TAB =====
class ProfileTab extends StatefulWidget {
  @override
  _ProfileTabState createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _uploadingPhoto = false;

  Future<void> _pickPhoto() async {
    setState(() => _uploadingPhoto = true);
    final error = await AuthService.uploadProfilePhoto();
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!')));
    }
  }

  void _editProfile(BuildContext context) {
    final nameCtrl = TextEditingController(text: AuthService.currentUserName);
    final phoneCtrl = TextEditingController(text: AuthService.currentUserPhone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { nameCtrl.dispose(); phoneCtrl.dispose(); Navigator.pop(ctx); },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              nameCtrl.dispose(); phoneCtrl.dispose();
              Navigator.pop(ctx);
              if (name.isEmpty) return;
              await DatabaseService.instance.updateProfile(
                  AuthService.currentUserId, name: name, phone: phone.isNotEmpty ? phone : null);
              AuthService.updateCachedProfile(name: name, phone: phone);
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
            child: Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _changePassword(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
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
                  labelText: 'New Password (min 6 chars)',
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
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final current = currentCtrl.text;
                final newPass = newCtrl.text;
                currentCtrl.dispose(); newCtrl.dispose();
                if (newPass.length < 6) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Password must be at least 6 characters')));
                  return;
                }
                Navigator.pop(ctx);
                final error = await AuthService.changePassword(current, newPass);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error ?? 'Password updated successfully'),
                    backgroundColor: error == null ? Colors.green : Colors.red,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
              child: Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _contactSupport(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.support_agent, color: Colors.blue.shade700),
          SizedBox(width: 8),
          Text('Contact Support'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We\'re here to help!', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email, color: Colors.blue),
              title: Text('support@app.flutour.com'),
              subtitle: Text('Email support'),
              onTap: () async {
                final uri = Uri.parse('mailto:support@app.flutour.com?subject=FluTour Passenger Support');
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
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
        ],
      ),
    );
  }

  void _showFAQ(BuildContext context) {
    final faqs = [
      ('How do I book a felucca?', 'Tap "Book a Ride" on the home screen, choose Felucca as vehicle type, pick your pickup and dropoff, then confirm booking.'),
      ('How is the fare calculated?', 'Felucca fares are time-based. Up to 15 min: 50 EGP, up to 30 min: 80 EGP, up to 60 min: 120 EGP. Horse carriage fares are distance-based.'),
      ('How do I pay?', 'You can pay in cash, credit card, or mobile wallet (InstaPay). Select your preferred method before confirming.'),
      ('Can I cancel a trip?', 'Yes, tap "Cancel" on the searching or booking screen and select a reason.'),
      ('How do I share my ride?', 'Tap the Share icon on the active ride screen to send your ride details to a contact.'),
    ];
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help & FAQ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: ListView.separated(
                  itemCount: faqs.length,
                  separatorBuilder: (_, __) => Divider(),
                  itemBuilder: (_, i) => ExpansionTile(
                    title: Text(faqs[i].$1, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    children: [Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(faqs[i].$2, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    )],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = AuthService.currentUserName;
    final phone = AuthService.currentUserPhone;
    final photoUrl = AuthService.currentPhotoUrl;
    return Scaffold(
      appBar: AppBar(title: Text(l.profile), centerTitle: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
                  ]),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickPhoto,
                    child: Stack(
                      children: [
                        _uploadingPhoto
                            ? CircleAvatar(
                                radius: 44,
                                backgroundColor: Colors.blue.shade100,
                                child: CircularProgressIndicator(
                                    color: Colors.blue.shade700, strokeWidth: 2))
                            : (photoUrl.isNotEmpty
                                ? CircleAvatar(
                                    radius: 44,
                                    backgroundImage: NetworkImage(photoUrl))
                                : CircleAvatar(
                                    radius: 44,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                      style: TextStyle(
                                          fontSize: 36,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold),
                                    ))),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.all(5),
                            decoration: BoxDecoration(
                                color: Colors.blue.shade700, shape: BoxShape.circle),
                            child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                          ),
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
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _badge('Passenger', Icons.verified, Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),

            // Account section
            _section('Account Settings', [
              _action(Icons.person_outline, 'Edit Profile', Colors.blue, () => _editProfile(context)),
              _action(Icons.lock_outline, 'Change Password', Colors.orange, () => _changePassword(context)),
              _action(Icons.notifications_outlined, 'Notifications', Colors.purple, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen()));
              }),
            ]),
            SizedBox(height: 16),

            // Support section
            _section('Support', [
              _action(Icons.help_outline, 'Help & FAQ', Colors.teal, () => _showFAQ(context)),
              _action(Icons.support_agent, 'Contact Support', Colors.blue, () => _contactSupport(context)),
              _action(Icons.star_outline, 'Rate the App', Colors.amber, () async {
                final uri = Uri.parse('https://play.google.com/store/apps/details?id=app.flutour.passenger');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              }),
            ]),
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
                leading: Icon(Icons.language, color: Colors.blue.shade700),
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

            // Logout
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await AuthService.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: Icon(Icons.logout, color: Colors.red),
                label: Text(l.signOut,
                    style: TextStyle(
                        color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            SizedBox(height: 12),
            Text('FluTour Passenger v1.0',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, IconData icon, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.shade200)),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color.shade600),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color.shade700, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey.shade600)),
          SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ===== VEHICLE THUMBNAIL PAINTERS =====

/// Draws a felucca sailboat scene on the Nile.
/// F072 = sunset (warm orange sky), F015 = daytime (teal/cyan sky)
class _FeluccaScenePainter extends CustomPainter {
  final Color primaryColor;
  final Color accentColor;
  final bool hasSunset;

  const _FeluccaScenePainter({
    required this.primaryColor,
    required this.accentColor,
    this.hasSunset = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          colors: hasSunset
              ? [const Color(0xFF0D47A1), const Color(0xFFBF360C), const Color(0xFFFF8F00)]
              : [primaryColor, accentColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: hasSunset ? [0.0, 0.55, 1.0] : [0.0, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Water (bottom 36%)
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.64, w, h * 0.36),
      Paint()
        ..shader = LinearGradient(
          colors: [primaryColor.withOpacity(0.9), primaryColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, h * 0.64, w, h * 0.36)),
    );

    // Horizon shimmer
    canvas.drawLine(Offset(0, h * 0.64), Offset(w, h * 0.64),
        Paint()..color = Colors.white.withOpacity(0.25)..strokeWidth = 0.8);

    // Sun / moon
    if (hasSunset) {
      canvas.drawCircle(Offset(w * 0.76, h * 0.21), 9,
          Paint()..color = const Color(0xFFFFE082));
      canvas.drawCircle(Offset(w * 0.76, h * 0.21), 14,
          Paint()..color = const Color(0xFFFFE082).withOpacity(0.22));
    } else {
      canvas.drawCircle(Offset(w * 0.18, h * 0.17), 7,
          Paint()..color = Colors.white.withOpacity(0.85));
    }

    // Mast
    final mx = w * 0.48;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(mx - 1.5, h * 0.11, 3, h * 0.53), Radius.circular(1.5)),
      Paint()..color = const Color(0xFF795548),
    );

    // Main sail (large left triangle)
    canvas.drawPath(
      Path()
        ..moveTo(mx, h * 0.13)
        ..lineTo(mx, h * 0.63)
        ..lineTo(mx - w * 0.33, h * 0.61)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.95),
    );

    // Jib sail (small right triangle)
    canvas.drawPath(
      Path()
        ..moveTo(mx, h * 0.15)
        ..lineTo(mx, h * 0.48)
        ..lineTo(mx + w * 0.28, h * 0.55)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.68),
    );

    // Hull
    canvas.drawPath(
      Path()
        ..moveTo(mx - w * 0.33, h * 0.64)
        ..lineTo(mx + w * 0.32, h * 0.64)
        ..quadraticBezierTo(mx + w * 0.26, h * 0.75, mx, h * 0.77)
        ..quadraticBezierTo(mx - w * 0.28, h * 0.75, mx - w * 0.33, h * 0.64)
        ..close(),
      Paint()..color = const Color(0xFF4E342E),
    );

    // Water ripples
    final rp = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final ry = h * (0.79 + i * 0.065);
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.07, ry)
          ..quadraticBezierTo(w * 0.28, ry - 2.5, w * 0.5, ry)
          ..quadraticBezierTo(w * 0.72, ry + 2.5, w * 0.93, ry),
        rp,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Draws a horse-carriage (Hantour) night scene.
/// H003 = Luxor temple columns in background, H062 = open road/corniche
class _HantourScenePainter extends CustomPainter {
  final Color primaryColor;
  final Color accentColor;
  final bool hasTemple;

  const _HantourScenePainter({
    required this.primaryColor,
    required this.accentColor,
    this.hasTemple = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background sky
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          colors: [primaryColor, accentColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Ground
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.75, w, h * 0.25),
      Paint()..color = Colors.black.withOpacity(0.32),
    );

    // Temple columns in background (H003)
    if (hasTemple) {
      final cp = Paint()..color = Colors.white.withOpacity(0.16);
      for (double cx = 0.04; cx < 1.0; cx += 0.16) {
        canvas.drawRect(Rect.fromLTWH(w * cx, h * 0.20, w * 0.08, h * 0.55), cp);
        canvas.drawRect(Rect.fromLTWH(w * cx - w * 0.015, h * 0.18, w * 0.11, h * 0.045), cp);
      }
    }

    // Stars
    final sp = Paint()..color = Colors.white.withOpacity(0.65);
    for (final s in [(0.14, 0.08), (0.5, 0.05), (0.78, 0.11), (0.32, 0.17), (0.65, 0.13), (0.88, 0.06)]) {
      canvas.drawCircle(Offset(w * s.$1, h * s.$2), 1.2, sp);
    }

    // Crescent moon
    canvas.drawCircle(Offset(w * 0.11, h * 0.15), 7, Paint()..color = Colors.white.withOpacity(0.90));
    canvas.drawCircle(Offset(w * 0.14, h * 0.12), 5.5, Paint()..color = primaryColor);

    // Carriage body
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.04, h * 0.44, w * 0.40, h * 0.28), Radius.circular(5)),
      Paint()..color = const Color(0xFF5D4037),
    );
    // Carriage roof arch
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.03, h * 0.44)
        ..quadraticBezierTo(w * 0.24, h * 0.36, w * 0.45, h * 0.44),
      Paint()..color = const Color(0xFF3E2723)..strokeWidth = 3..style = PaintingStyle.stroke,
    );
    // Windows
    for (final wx in [0.08, 0.25]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * wx, h * 0.49, w * 0.11, h * 0.13), Radius.circular(3)),
        Paint()..color = Colors.white.withOpacity(0.30),
      );
    }

    // Wheels with spokes
    for (final wc in [0.15, 0.37]) {
      final r = h * 0.095;
      final cx = w * wc;
      final cy = h * 0.78;
      canvas.drawCircle(cx < w * 0.3 ? Offset(cx, cy) : Offset(cx, cy), r, Paint()..color = const Color(0xFF3E2723));
      for (int s = 0; s < 6; s++) {
        final ang = s * pi / 3;
        canvas.drawLine(
          Offset(cx + r * 0.85 * cos(ang), cy + r * 0.85 * sin(ang)),
          Offset(cx, cy),
          Paint()..color = Colors.white.withOpacity(0.28)..strokeWidth = 1,
        );
      }
    }

    // Harness pole
    canvas.drawLine(
      Offset(w * 0.44, h * 0.65),
      Offset(w * 0.58, h * 0.62),
      Paint()..color = const Color(0xFF795548)..strokeWidth = 2.2,
    );

    // Horse body
    final hx = w * 0.70;
    final hy = h * 0.58;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: w * 0.30, height: h * 0.17),
      Paint()..color = const Color(0xFF1A1A1A),
    );
    // Neck
    canvas.drawPath(
      Path()
        ..moveTo(hx + w * 0.10, hy - h * 0.04)
        ..lineTo(hx + w * 0.16, hy - h * 0.15)
        ..lineTo(hx + w * 0.21, hy - h * 0.13)
        ..lineTo(hx + w * 0.14, hy - h * 0.01)
        ..close(),
      Paint()..color = const Color(0xFF1A1A1A),
    );
    // Head
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(hx + w * 0.16, hy - h * 0.20, w * 0.12, h * 0.11), Radius.circular(4)),
      Paint()..color = const Color(0xFF1A1A1A),
    );
    // Legs
    final lp = Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = 3.5..style = PaintingStyle.stroke;
    for (final lx in [-0.11, -0.04, 0.05, 0.12]) {
      canvas.drawLine(Offset(hx + w * lx, hy + h * 0.07), Offset(hx + w * lx + w * 0.01, hy + h * 0.19), lp);
    }
    // Tail
    canvas.drawPath(
      Path()
        ..moveTo(hx - w * 0.14, hy - h * 0.02)
        ..quadraticBezierTo(hx - w * 0.23, hy - h * 0.09, hx - w * 0.20, hy + h * 0.07),
      Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = 3..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ===== WEEK 5: SEARCHING DRIVER SCREEN =====
class SearchingDriverScreen extends StatefulWidget {
  final String pickup, dropoff, vehicleType, driver, payment;
  final double fare;
  final double proposedFare;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? scheduledAt;

  const SearchingDriverScreen({
    required this.pickup, required this.dropoff,
    required this.vehicleType, required this.driver,
    required this.payment, required this.fare,
    this.proposedFare = 0,
    this.pickupLat, this.pickupLng, this.dropoffLat, this.dropoffLng,
    this.scheduledAt,
  });
  @override
  _SearchingDriverScreenState createState() => _SearchingDriverScreenState();
}

class _SearchingDriverScreenState extends State<SearchingDriverScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  String? _tripId;
  StreamSubscription? _tripSub;
  Timer? _pollTimer;
  bool _navigated = false;
  List<Map<String, dynamic>> _driverOffers = [];
  StreamSubscription? _offersSub;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _createTripAndListen();
  }

  void _navigateToConfirmed(String driverName) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _tripSub?.cancel();
    _offersSub?.cancel();
    _pollTimer?.cancel();
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => BookingConfirmedScreen(
                  vehicleId: '',
                  type: widget.vehicleType,
                  driver: driverName,
                  pickup: widget.pickup,
                  dropoff: widget.dropoff,
                  payment: widget.payment,
                  tripId: _tripId,
                  pickupLat: widget.pickupLat,
                  pickupLng: widget.pickupLng,
                  dropoffLat: widget.dropoffLat,
                  dropoffLng: widget.dropoffLng,
                  scheduledAt: widget.scheduledAt,
                )));
  }

  Future<void> _createTripAndListen() async {
    try {
      final payMethod = widget.payment == 'Credit Card'
          ? PaymentMethod.creditCard
          : widget.payment == 'Mobile Wallet' || widget.payment == 'InstaPay'
              ? PaymentMethod.mobileWallet
              : PaymentMethod.cash;
      final trip = await DatabaseService.instance.requestTrip(
        passengerId: AuthService.currentUserId,
        passengerName: AuthService.currentUserName.isNotEmpty
            ? AuthService.currentUserName
            : 'Passenger',
        vehicleType: VehicleTypeX.fromString(widget.vehicleType),
        pickup: widget.pickup,
        dropoff: widget.dropoff,
        fare: widget.proposedFare > 0 ? widget.proposedFare : widget.fare,
        paymentMethod: payMethod,
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
        dropoffLat: widget.dropoffLat,
        dropoffLng: widget.dropoffLng,
        scheduledAt: widget.scheduledAt,
      );
      _tripId = trip.id;

      // Listen to trip status (for when passenger accepts an offer)
      _tripSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(_tripId)
          .snapshots()
          .listen((doc) {
        if (!mounted || _navigated) return;
        if (!doc.exists) return;
        final status = doc.data()?['status'] ?? '';
        final driverName = doc.data()?['driverName'] as String? ?? '';
        if (status == 'accepted' || status == 'in_progress') {
          _navigateToConfirmed(driverName);
        }
      }, onError: (_) {});

      // Listen to driver offers subcollection
      _offersSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(_tripId)
          .collection('offers')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() {
          _driverOffers = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        });
      }, onError: (_) {});

      // Polling fallback
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_tripId == null || _navigated || !mounted) return;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('trips')
              .doc(_tripId)
              .get();
          if (!doc.exists) return;
          final status = doc.data()?['status'] ?? '';
          final driverName = doc.data()?['driverName'] as String? ?? '';
          if (status == 'accepted' || status == 'in_progress') {
            _navigateToConfirmed(driverName);
          }
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Booking failed: $e'),
                duration: Duration(seconds: 8)));
      }
    }
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    if (_accepting || _tripId == null) return;
    setState(() => _accepting = true);
    try {
      await DatabaseService.instance.acceptDriverOffer(
        tripId: _tripId!,
        driverUid: offer['driverUid'] as String? ?? offer['id'] as String,
        driverName: offer['driverName'] as String? ?? 'Driver',
        driverPhone: offer['driverPhone'] as String? ?? '',
        instapayPhone: offer['instapayPhone'] as String? ?? '',
        agreedFare: (offer['suggestedFare'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to accept: $e')));
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tripSub?.cancel();
    _offersSub?.cancel();
    _pollTimer?.cancel();
    if (_tripId != null && !_navigated) {
      DatabaseService.instance.cancelTrip(_tripId!).catchError((_) {});
    }
    super.dispose();
  }

  void _cancel() {
    String? _selectedReason;
    final reasons = [
      'Driver too far away',
      'Changed my mind',
      'Wrong pickup location',
      'Found another ride',
      'Other',
    ];
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Cancel Booking?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please select a reason:', style: TextStyle(color: Colors.grey.shade700)),
              SizedBox(height: 8),
              ...reasons.map((r) => RadioListTile<String>(
                value: r,
                groupValue: _selectedReason,
                title: Text(r, style: TextStyle(fontSize: 14)),
                onChanged: (v) => setDialog(() => _selectedReason = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Keep')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (_tripId != null) {
                  DatabaseService.instance.cancelTrip(_tripId!, reason: _selectedReason ?? '').catchError((_) {});
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Cancel Booking', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Driver Offers'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.blue.shade700,
          titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          actions: [
            TextButton(
              onPressed: _cancel,
              child: Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        body: Column(
          children: [
            // Route + offered fare summary
            Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(children: [
                    Icon(Icons.trip_origin, size: 14, color: Colors.green),
                    SizedBox(width: 6),
                    Expanded(child: Text(widget.pickup, style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  ]),
                  SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on, size: 14, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(child: Text(widget.dropoff, style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  ]),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your offer: ${(widget.proposedFare > 0 ? widget.proposedFare : widget.fare).toStringAsFixed(0)} EGP',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(widget.vehicleType,
                            style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1),

            // Offers list or searching animation
            Expanded(
              child: _driverOffers.isEmpty
                  ? _buildSearchingState()
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _driverOffers.length,
                      itemBuilder: (ctx, i) => _buildOfferCard(_driverOffers[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 100 + _pulse.value * 20,
              height: 100 + _pulse.value * 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.shade100.withOpacity(0.5 + _pulse.value * 0.3),
              ),
              child: Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.shade700,
                  ),
                  child: Icon(Icons.search, color: Colors.white, size: 40),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),
          Text('Looking for drivers...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Drivers will send you their fare offers', style: TextStyle(color: Colors.grey.shade600)),
          SizedBox(height: 4),
          Text('Choose the best offer for you', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> offer) {
    final driverName = offer['driverName'] as String? ?? 'Driver';
    final fare = (offer['suggestedFare'] as num?)?.toDouble() ?? 0.0;
    final rating = (offer['rating'] as num?)?.toDouble() ?? 0.0;
    final photoUrl = offer['photoUrl'] as String? ?? '';
    final offeredFare = widget.proposedFare > 0 ? widget.proposedFare : widget.fare;
    final isLower = fare < offeredFare;
    final isHigher = fare > offeredFare;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLower ? Colors.green.shade200 : isHigher ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.teal.shade100,
            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Text(driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700, fontSize: 20))
                : null,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driverName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.star, size: 14, color: Colors.amber),
                  SizedBox(width: 2),
                  Text(rating > 0 ? rating.toStringAsFixed(1) : 'New',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
                SizedBox(height: 4),
                if (isLower)
                  Text('Lower than your offer!',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.w600))
                else if (isHigher)
                  Text('Higher than your offer',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 11))
                else
                  Text('Matches your offer',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${fare.toStringAsFixed(0)} EGP',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isLower ? Colors.green.shade700 : isHigher ? Colors.orange.shade700 : Colors.blue.shade700)),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: _accepting ? null : () => _acceptOffer(offer),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size(0, 0),
                ),
                child: _accepting
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== WEEK 5: ACTIVE TRIP SCREEN =====
class ActiveTripScreen extends StatefulWidget {
  final String driverName, vehicleType, pickup, dropoff;
  final double rating, fareTotal;
  final String? driverPhone;
  const ActiveTripScreen({
    required this.driverName, required this.vehicleType,
    required this.rating, required this.pickup,
    required this.dropoff, required this.fareTotal,
    this.driverPhone,
  });
  @override
  _ActiveTripScreenState createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  int _statusIdx = 0;
  final _statuses = ['Driver en route', 'Driver arrived', 'Trip in progress'];
  LatLng _driverPos = LatLng(25.6950, 32.6380);
  StreamSubscription<LatLngPoint>? _locSub;
  DateTime? _tripStartedAt;

  @override
  void initState() {
    super.initState();
    _locSub = LocationService.watchDriverLocation('sim').listen((p) {
      if (mounted) setState(() => _driverPos = LatLng(p.lat, p.lng));
    });
  }

  @override
  void dispose() {
    _locSub?.cancel();
    super.dispose();
  }

  void _advance() {
    if (_statusIdx < _statuses.length - 1) {
      // Record when trip actually begins
      if (_statusIdx == 1) _tripStartedAt = DateTime.now();
      setState(() => _statusIdx++);
    } else {
      final durationMin = _tripStartedAt != null
          ? DateTime.now().difference(_tripStartedAt!).inMinutes.clamp(1, 999)
          : 0;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => TripCompletionScreen(
                    driverName: widget.driverName,
                    pickup: widget.pickup,
                    dropoff: widget.dropoff,
                    distanceKm: 0.0,
                    durationMin: durationMin,
                    fareTotal: widget.fareTotal,
                  )));
    }
  }

  void _sos() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning, color: Colors.red),
          SizedBox(width: 8),
          Text('Emergency'),
        ]),
        content: Text(
            'Call 123 for police or tap OK to alert the FluTour admin team.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Alert Admin', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFelucca = widget.vehicleType == 'Felucca';
    final statusColors = [Colors.blue, Colors.orange, Colors.teal];
    final btnLabels = ['Driver arrived', 'Trip started', 'End Trip'];

    return Scaffold(
      body: Column(
        children: [
          // ── Map (55% of screen) ──────────────────────────────────────────
          Expanded(
            flex: 55,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(25.6987, 32.6390),
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                      userAgentPackageName: 'com.flutour.passenger',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        width: 44, height: 44,
                        point: LatLng(25.6987, 32.6390),
                        child: Container(
                          decoration: BoxDecoration(
                              color: Colors.blue.shade700,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                          child: Icon(Icons.person_pin_circle, color: Colors.white, size: 26),
                        ),
                      ),
                      Marker(
                        width: 44, height: 44,
                        point: _driverPos,
                        child: Container(
                          decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                          child: Icon(isFelucca ? Icons.sailing : Icons.directions_car,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ]),
                  ],
                ),
                // Status chip
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10, left: 12, right: 12,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                              color: statusColors[_statusIdx], shape: BoxShape.circle),
                        ),
                        SizedBox(width: 8),
                        Text(_statuses[_statusIdx],
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Driver info card (45%) ───────────────────────────────────────
          Expanded(
            flex: 45,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.teal.shade100,
                        child: Icon(Icons.person, color: Colors.teal.shade700, size: 32),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.driverName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            SizedBox(height: 4),
                            Row(children: [
                              Icon(isFelucca ? Icons.sailing : Icons.directions_car,
                                  size: 14, color: Colors.teal.shade700),
                              SizedBox(width: 6),
                              Text(widget.vehicleType,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              SizedBox(width: 10),
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text('${widget.rating.toStringAsFixed(1)} ★',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ]),
                          ],
                        ),
                      ),
                      Text('${widget.fareTotal.toStringAsFixed(0)} EGP',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.teal.shade700)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.trip_origin, size: 13, color: Colors.green),
                      SizedBox(width: 6),
                      Expanded(child: Text(widget.pickup,
                          style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                      Icon(Icons.arrow_forward, size: 13, color: Colors.grey),
                      SizedBox(width: 6),
                      Icon(Icons.location_on, size: 13, color: Colors.red),
                      SizedBox(width: 4),
                      Expanded(child: Text(widget.dropoff,
                          style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                  SizedBox(height: 12),
                  // Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _iconBtn(Icons.phone, Colors.blue, () async {
                        final phone = widget.driverPhone;
                        if (phone != null && phone.isNotEmpty) {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Driver phone unavailable')));
                        }
                      }),
                      _iconBtn(Icons.warning_amber_rounded, Colors.red, _sos),
                      _iconBtn(Icons.message, Colors.grey, () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Messaging not available yet')))),
                    ],
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _advance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusColors[_statusIdx],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(btnLabels[_statusIdx],
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 24),
    ),
  );
}

// ===== WEEK 5: TRIP COMPLETION SCREEN =====
class TripCompletionScreen extends StatefulWidget {
  final String driverName, pickup, dropoff;
  final double distanceKm, fareTotal;
  final int durationMin;
  const TripCompletionScreen({
    required this.driverName, required this.pickup,
    required this.dropoff, required this.distanceKm,
    required this.durationMin, required this.fareTotal,
  });
  @override
  _TripCompletionScreenState createState() => _TripCompletionScreenState();
}

class _TripCompletionScreenState extends State<TripCompletionScreen> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  final GlobalKey _receiptKey = GlobalKey();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _stars > 0) {
        // No tripId passed to this screen — save rating as a pending review
        // linked to the passenger so it can be matched to the trip server-side.
        await FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .collection('pendingRatings').add({
          'stars': _stars,
          'comment': _commentCtrl.text.trim(),
          'driverName': widget.driverName,
          'pickup': widget.pickup,
          'dropoff': widget.dropoff,
          'ratedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => PassengerHomeScreen()),
        (_) => false);
  }

  Future<void> _shareReceipt() async {
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.5);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final bytes = byteData.buffer.asUint8List();
          final dir = await getTemporaryDirectory();
          final file = await File('${dir.path}/flutour_receipt.png').writeAsBytes(bytes);
          await Share.shareXFiles([XFile(file.path)], subject: 'FluTour Ride Receipt - Luxor');
          return;
        }
      }
    } catch (_) {}
    final text = 'FluTour Ride Receipt\nFrom: ${widget.pickup}\nTo: ${widget.dropoff}\nFare: ${widget.fareTotal.toStringAsFixed(0)} EGP';
    Share.share(text, subject: 'FluTour Ride Receipt');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.tripComplete),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(height: 16),
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 72),
              SizedBox(height: 12),
              Text(l.tripComplete,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Thanks for riding with ${widget.driverName}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center),
              SizedBox(height: 24),
              // Summary card (shareable)
              RepaintBoundary(
                key: _receiptKey,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_boat, color: Colors.teal.shade600, size: 20),
                          SizedBox(width: 6),
                          Text('FluTour Receipt',
                              style: TextStyle(fontWeight: FontWeight.bold,
                                  fontSize: 15, color: Colors.teal.shade700)),
                        ],
                      ),
                      Divider(height: 20),
                      _summaryRow(Icons.route, 'Distance', '${widget.distanceKm.toStringAsFixed(1)} km'),
                      Divider(height: 20),
                      _summaryRow(Icons.timer, 'Duration', '${widget.durationMin} min'),
                      Divider(height: 20),
                      _summaryRow(Icons.attach_money, 'Fare',
                          '${widget.fareTotal.toStringAsFixed(0)} EGP',
                          valueColor: Colors.teal.shade700),
                      Divider(height: 20),
                      _summaryRow(Icons.trip_origin, l.from, widget.pickup),
                      Divider(height: 12),
                      _summaryRow(Icons.location_on, l.to, widget.dropoff),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Share receipt button
              OutlinedButton.icon(
                onPressed: _shareReceipt,
                icon: Icon(Icons.share, size: 18),
                label: Text('Share Receipt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
              SizedBox(height: 24),
              // Star rating
              Text(l.rateYourDriver,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      i < _stars ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                  ),
                )),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Leave a comment (optional)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              _submitting
                  ? CircularProgressIndicator(color: Colors.blue.shade700)
                  : SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(l.submitRating,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => PassengerHomeScreen()),
                    (_) => false),
                child: Text(l.skip,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blue.shade400),
        SizedBox(width: 10),
        Text('$label: ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: valueColor ?? Colors.black87),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

// ===== NOTIFICATIONS SCREEN =====
class NotificationsScreen extends StatefulWidget {
  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NotificationModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getNotifications(AuthService.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notifications'), centerTitle: true),
      body: FutureBuilder<List<NotificationModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade300),
                  SizedBox(height: 16),
                  Text('No notifications yet',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = items[i];
              return Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: n.read ? Colors.white : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.notifications, color: Colors.blue.shade700, size: 18),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 4),
                          Text(n.body, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (!n.read)
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
