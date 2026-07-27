// lib/main.dart - FluTour Passenger App
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models.dart';
import 'database_service.dart';
import 'location_service.dart';

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
  // Load persisted login session before UI renders
  await AuthService.loadSession();
  runApp(FluTourPassengerApp());
}

class FluTourPassengerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluTour Passenger',
      debugShowCheckedModeBanner: false,
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
  static String _tempPassword = '';

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
  static String get currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  static String get currentUserName => _currentUserName;
  static String get currentUserPhone => _currentUserPhone;

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserName = prefs.getString('passenger_name') ?? '';
    _currentUserPhone = prefs.getString('passenger_phone') ?? '';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _currentUserName.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        _currentUserName = doc.data()?['name'] ?? '';
        _currentUserPhone = doc.data()?['phone'] ?? '';
        await prefs.setString('passenger_name', _currentUserName);
        await prefs.setString('passenger_phone', _currentUserPhone);
      } catch (_) {}
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_name', _currentUserName);
      await prefs.setString('passenger_phone', _currentUserPhone);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'No account found for this phone number';
      if (e.code == 'wrong-password') return 'Incorrect password';
      return e.message ?? 'Sign in failed';
    } catch (_) {
      return 'Service unavailable. Please check your connection.';
    }
  }

  static Future<String?> register(String name, String phone, String password) async {
    if (name.isEmpty || phone.isEmpty || password.length < 6)
      return 'Password must be at least 6 characters';
    _currentUserName = name;
    _currentUserPhone = phone;
    _tempPassword = password;
    return null;
  }

  static String _lastOtpError = '';
  static String get lastOtpError => _lastOtpError;

  static Future<bool> verifyOtp(String otp) async {
    // Accept any 6-digit code — OTP is simulated (no real SMS gateway yet)
    if (otp.length < 6) return false;
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _phoneToEmail(_currentUserPhone), password: _tempPassword);
      _tempPassword = '';
      _lastOtpError = '';
      await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).set({
        'name': _currentUserName,
        'phone': _currentUserPhone,
        'role': 'passenger',
        'createdAt': FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_name', _currentUserName);
      await prefs.setString('passenger_phone', _currentUserPhone);
      return true;
    } on FirebaseAuthException catch (e) {
      _tempPassword = '';
      _lastOtpError = e.message ?? e.code;
      return false;
    } catch (e) {
      _tempPassword = '';
      _lastOtpError = e.toString();
      return false;
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
    Timer(Duration(seconds: 3), () {
      if (!mounted) return;
      // Navigation guard: skip login if already authenticated
      if (AuthService.isLoggedIn) {
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
                            child: Text('Sign In',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
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
                      child: Text('Create Account',
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
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Account'),
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
              child: Text('Join FluTour',
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
                        // TODO: FirebaseAuth will send OTP to phone number
                        final error = await AuthService.register(
                            _nameCtrl.text.trim(),
                            _phoneCtrl.text.trim(),
                            _passCtrl.text.trim());
                        if (!mounted) return;
                        setState(() => _loading = false);
                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)));
                        } else {
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => OtpScreen(
                                  phone: _phoneCtrl.text.trim(),
                                  name: _nameCtrl.text.trim())));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Create Account',
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
    // TODO: Pass real Firebase OTP credential when account is recovered
    final success = await AuthService.verifyOtp(_otp);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => PassengerHomeScreen()), (_) => false);
    } else {
      final err = AuthService.lastOtpError;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.isNotEmpty ? err : 'Registration failed. Try again.')));
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
            Text('SMS not enabled yet — enter any 6 digits to continue',
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
                    onPressed: () {
                      _startTimer();
                      // TODO: Trigger FirebaseAuth resend OTP
                    },
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
    // TODO: Connect to FirebaseAuth.instance.sendPasswordResetEmail()
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
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.sailing), label: 'Book Ride'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'My Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
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
                Expanded(child: _rideTypeCard(context, 'Felucca', Icons.sailing,
                    Colors.blue, 'Traditional Nile boat ride')),
                SizedBox(width: 12),
                Expanded(
                    child: _rideTypeCard(context, 'Horse Carriage', Icons.directions,
                        Colors.orange, 'Classic Hantour ride')),
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

  Widget _rideTypeCard(BuildContext context, String type, IconData icon,
      MaterialColor color, String desc) {
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
            Text(type,
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
              child: Text('Book Now',
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

  void _updateFareEstimate() {
    final pickup = _pickupLoc;
    final dest = _destinationLoc;
    if (pickup == null || dest == null) {
      setState(() => _fareEstimate = null);
      return;
    }
    final dist = FareEstimator.distanceKm(
        pickup.latitude, pickup.longitude, dest.latitude, dest.longitude);
    final eta = FareEstimator.etaString(dist);
    setState(() {
      // Fixed prices: Felucca 50 EGP · Horse Carriage 80 EGP
      _fareEstimate = '~${dist.toStringAsFixed(1)} km · EGP 50–80 · $eta';
    });
  }

  @override
  void initState() {
    super.initState();
    _timeCtrl.text = '20:00 PM';
    _dateCtrl.text = 'Today';
    // Location detected only when user taps the pin button — avoids ANR from
    // IndexedStack initialising all tabs simultaneously on home screen load.
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
      appBar: AppBar(title: Text('Book a Ride'), centerTitle: true),
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
          if (_fareEstimate != null)
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
                    Icon(Icons.monetization_on, color: Colors.teal.shade700, size: 16),
                    SizedBox(width: 6),
                    Text(_fareEstimate!,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.teal.shade800)),
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
                        Text('Plan Your Ride',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _mapInput(_pickupCtrl, 'Pickup point',
                            'Luxor Temple, your hotel...', Icons.trip_origin, Colors.green),
                        SizedBox(height: 10),
                        _mapInput(_dropoffCtrl, 'Drop off point',
                            'Karnak, Nile Corniche...', Icons.location_on, Colors.red),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: _mapInput(_timeCtrl, 'Pickup Time',
                                    '20:00 PM', Icons.access_time, Colors.blue)),
                            SizedBox(width: 10),
                            Expanded(
                                child: _mapInput(_dateCtrl, 'Date',
                                    'DD/MM/YYYY', Icons.calendar_today, Colors.purple)),
                          ],
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
                                    content: Text(
                                        'Please enter pickup and drop-off locations')));
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
                                          )));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('Find Rides',
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

// ===== 7. VEHICLE SELECT SCREEN =====
class VehicleSelectScreen extends StatefulWidget {
  final String pickup;
  final String dropoff;
  final String time;
  final String date;
  final String? filter;

  VehicleSelectScreen(
      {required this.pickup,
      required this.dropoff,
      required this.time,
      required this.date,
      this.filter});

  @override
  _VehicleSelectScreenState createState() => _VehicleSelectScreenState();
}

class _VehicleSelectScreenState extends State<VehicleSelectScreen> {
  String? _selId, _selType, _selDriver;
  String? _activeFilter;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.filter;
  }

  Stream<List<Map<String, dynamic>>> _driversStream() {
    return FirebaseFirestore.instance
        .collection('drivers')
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              final vType = data['vehicleType'] ?? 'felucca';
              final isFelucca = vType.toLowerCase().replaceAll(' ', '_') == 'felucca';
              return {
                'id': data['vehicleId'] ?? d.id,
                'driverUid': d.id,
                'type': isFelucca ? 'Felucca' : 'Horse Carriage',
                'driver': data['name'] ?? 'Driver',
                'rating': () {
                    final r = data['rating'];
                    if (r == null) return '5.0';
                    if (r is num) return r.toStringAsFixed(1);
                    return r.toString();
                  }(),
                'eta': '5 min',
                'price': isFelucca ? 'EGP 50' : 'EGP 80',
                'label': isFelucca ? 'Nile Felucca Ride' : 'Hantour Carriage Ride',
                'gradientA': isFelucca ? Color(0xFF0D47A1) : Color(0xFFBF360C),
                'gradientB': isFelucca ? Color(0xFF42A5F5) : Color(0xFFFFB74D),
                'icon': isFelucca ? Icons.sailing : Icons.directions,
                'tag': isFelucca ? 'Felucca' : 'Hantour',
                'tagColor': isFelucca ? Color(0xFF1976D2) : Color(0xFF43A047),
              };
            }).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose Your Ride'),
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

          // Map mini view
          Container(
            height: 160,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(25.6872, 32.6396),
                initialZoom: 13.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                  userAgentPackageName: 'com.flutour.passenger',
                ),
                MarkerLayer(markers: [
                  Marker(
                    width: 36,
                    height: 36,
                    point: LatLng(25.6890, 32.6370),
                    child: Icon(Icons.trip_origin, color: Colors.green, size: 28),
                  ),
                  Marker(
                    width: 36,
                    height: 36,
                    point: LatLng(25.6840, 32.6450),
                    child: Icon(Icons.location_on, color: Colors.red, size: 28),
                  ),
                ]),
              ],
            ),
          ),

          // Active filter chip
          if (_activeFilter != null)
            Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _activeFilter == 'Felucca' ? Icons.sailing : Icons.directions,
                    size: 16,
                    color: _activeFilter == 'Felucca'
                        ? Colors.blue.shade700
                        : Colors.orange.shade700,
                  ),
                  SizedBox(width: 6),
                  Text('Showing: $_activeFilter only',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800)),
                  Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _activeFilter = null;
                      _selId = null;
                      _selType = null;
                      _selDriver = null;
                    }),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Text('Show all',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          SizedBox(width: 4),
                          Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_activeFilter != null) Divider(height: 1),

          // Vehicle list (real drivers from Firestore)
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _driversStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Error: ${snapshot.error}',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data ?? [];
                final displayed = _activeFilter != null
                    ? all.where((v) => v['type'] == _activeFilter).toList()
                    : all;
                if (displayed.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                        SizedBox(height: 12),
                        Text('No drivers available right now',
                            style: TextStyle(color: Colors.grey.shade600)),
                        SizedBox(height: 8),
                        Text('Total in DB: ${all.length}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.all(14),
                  itemCount: displayed.length,
                  itemBuilder: (context, i) => _buildVehicleCard(displayed[i]),
                );
              },
            ),
          ),

          // Proceed button (shows when selected)
          if (_selId != null)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(
                        vehicleId: _selId!,
                        type: _selType!,
                        driver: _selDriver!,
                        pickup: widget.pickup,
                        dropoff: widget.dropoff,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Proceed to Payment',
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

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final bool isSelected = _selId == v['id'];
    return GestureDetector(
      onTap: () => setState(() {
        _selId = v['id'];
        _selType = v['type'];
        _selDriver = v['driver'];
      }),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(14),
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
            // Vehicle type thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [v['gradientA'] as Color, v['gradientB'] as Color],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: Icon(v['icon'] as IconData, color: Colors.white54, size: 44)),
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        color: Colors.black38,
                        padding: EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: Text(v['id'],
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                    ),
                    Positioned(
                      top: 5, left: 5,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: v['tagColor'] as Color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(v['tag'],
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(v['label'],
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(v['type'],
                      style: TextStyle(
                          color: v['type'] == 'Felucca'
                              ? Colors.blue.shade600
                              : Colors.orange.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 3),
                  Text(v['driver'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.star, size: 13, color: Colors.amber),
                      SizedBox(width: 3),
                      Text(v['rating'],
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      SizedBox(width: 12),
                      Icon(Icons.access_time, size: 13, color: Colors.blue.shade400),
                      SizedBox(width: 3),
                      Text(v['eta'],
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ],
              ),
            ),
            // Price + select
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(v['price'],
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue.shade700)),
                SizedBox(height: 6),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade700 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isSelected ? '✓ Selected' : 'Select',
                    style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

double _fareForType(String type) => type == 'Felucca' ? 50.0 : 80.0;

// ===== 8. PAYMENT SCREEN =====
class PaymentScreen extends StatefulWidget {
  final String vehicleId;
  final String type;
  final String driver;
  final String pickup;
  final String dropoff;

  PaymentScreen({
    required this.vehicleId,
    required this.type,
    required this.driver,
    required this.pickup,
    required this.dropoff,
  });

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selected = 'Cash';

  final List<Map<String, dynamic>> _methods = [
    {'name': 'Cash', 'icon': Icons.money, 'desc': 'Pay at end of ride'},
    {'name': 'Credit Card', 'icon': Icons.credit_card, 'desc': 'Visa / Mastercard'},
    {'name': 'Mobile Wallet', 'icon': Icons.account_balance_wallet, 'desc': 'Vodafone, Orange...'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment'),
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
                        _summaryRow(Icons.trip_origin, 'From', widget.pickup),
                        _summaryRow(Icons.location_on, 'To', widget.dropoff),
                        Divider(height: 16),
                        Builder(builder: (context) {
                          final fare = _fareForType(widget.type);
                          final serviceFee = (fare * 0.10).roundToDouble();
                          final total = fare + serviceFee;
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

                  Text('Select Payment Method',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),

                  ..._methods.map((m) => GestureDetector(
                        onTap: () => setState(() => _selected = m['name']),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _selected == m['name']
                                ? Colors.blue.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selected == m['name']
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade200,
                              width: _selected == m['name'] ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: _selected == m['name']
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
                                  color: _selected == m['name']
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(m['icon'],
                                    color: _selected == m['name']
                                        ? Colors.blue.shade700
                                        : Colors.grey.shade600,
                                    size: 24),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m['name'],
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                    Text(m['desc'],
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (_selected == m['name'])
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
                        fare: _fareForType(widget.type),
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Confirm & Book · $_selected',
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
    return Scaffold(
      appBar: AppBar(
          title: Text('Cash Payment'),
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
            _row('From', widget.pickup),
            _row('To', widget.dropoff),
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
  BookingConfirmedScreen(
      {required this.vehicleId,
      required this.type,
      required this.driver,
      required this.pickup,
      required this.dropoff,
      required this.payment,
      this.tripId});

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

  final List<Map<String, dynamic>> _steps = [
    {'label': 'Booking Confirmed', 'icon': Icons.check_circle, 'color': Colors.green},
    {'label': 'Driver On the Way', 'icon': Icons.drive_eta, 'color': Colors.blue},
    {'label': 'Driver Arrived', 'icon': Icons.where_to_vote, 'color': Colors.orange},
    {'label': 'Ride in Progress', 'icon': Icons.sailing, 'color': Colors.teal},
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _scaleAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();

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
          _handleStatusUpdate(doc.data()?['status'] ?? '');
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
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => TripCompletionScreen(
                    driverName: widget.driver,
                    pickup: widget.pickup,
                    dropoff: widget.dropoff,
                    distanceKm: 2.0,
                    durationMin: 20,
                    fareTotal: _fareForType(widget.type),
                  )));
      return;
    }
    int step = _rideStep;
    if (status == 'accepted') step = 1;
    if (status == 'arrived') step = 2;
    if (status == 'in_progress') step = 3;
    setState(() => _rideStep = step);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tripSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_rideStep];
    final Color stepColor = step['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ride Status'),
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
                children: List.generate(_steps.length, (i) {
                  final done = i <= _rideStep;
                  final active = i == _rideStep;
                  return Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: done
                              ? (_steps[i]['color'] as Color)
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
                            Text(_steps[i]['label'] as String,
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

            // Driver & ride info
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
                  ]),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        radius: 26,
                        child: Text(widget.driver[0],
                            style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 20)),
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
                              Text('4.8',
                                  style: TextStyle(
                                      color: Colors.grey.shade600, fontSize: 12)),
                            ]),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Icon(Icons.phone, color: Colors.blue.shade700),
                          SizedBox(height: 4),
                          Text('Call', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  Divider(height: 20),
                  _infoRow(Icons.trip_origin, Colors.green, 'From', widget.pickup),
                  SizedBox(height: 6),
                  _infoRow(Icons.location_on, Colors.red, 'To', widget.dropoff),
                  Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payment: ${widget.payment}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      Text('EGP ${_fareForType(widget.type).toStringAsFixed(0)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                              fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),

            if (_rideStep == 3) ...[
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: Icon(Icons.home, color: Colors.white),
                  label: Text('Back to Home',
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
    return Scaffold(
      appBar: AppBar(title: Text('My Trips'), centerTitle: true),
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
                    child: Text('Retry'),
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
                          child: Text(f,
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
                            Text('No trips yet',
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

  void _rateDialog(BuildContext context, TripModel trip) {
    int tempRating = 5;
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await DatabaseService.instance.rateTrip(trip.id, tempRating);
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
class ProfileTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = AuthService.currentUserName;
    final phone = AuthService.currentUserPhone;
    return Scaffold(
      appBar: AppBar(title: Text('My Profile'), centerTitle: true),
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
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          name.isNotEmpty ? name[0] : 'P',
                          style: TextStyle(
                              fontSize: 36,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade700, shape: BoxShape.circle),
                          child: Icon(Icons.edit, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
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
              _action(Icons.person_outline, 'Edit Profile', Colors.blue, () {}),
              _action(Icons.lock_outline, 'Change Password', Colors.orange, () {}),
              _action(Icons.notifications_outlined, 'Notifications', Colors.purple, () {}),
            ]),
            SizedBox(height: 16),

            // Support section
            _section('Support', [
              _action(Icons.help_outline, 'Help & FAQ', Colors.teal, () {}),
              _action(Icons.support_agent, 'Contact Support', Colors.blue, () {}),
              _action(Icons.star_outline, 'Rate the App', Colors.amber, () {}),
            ]),
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
                label: Text('Logout',
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
  const SearchingDriverScreen({
    required this.pickup, required this.dropoff,
    required this.vehicleType, required this.driver,
    required this.payment, required this.fare,
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

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _createTripAndListen();
  }

  void _navigateToConfirmed(String? driverName) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _tripSub?.cancel();
    _pollTimer?.cancel();
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => BookingConfirmedScreen(
                  vehicleId: '',
                  type: widget.vehicleType,
                  driver: driverName ?? widget.driver,
                  pickup: widget.pickup,
                  dropoff: widget.dropoff,
                  payment: widget.payment,
                  tripId: _tripId,
                )));
  }

  Future<void> _createTripAndListen() async {
    try {
      final payMethod = widget.payment == 'Credit Card'
          ? PaymentMethod.creditCard
          : widget.payment == 'Mobile Wallet'
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
        fare: widget.fare,
        paymentMethod: payMethod,
      );
      _tripId = trip.id;

      // Real-time listener — primary mechanism
      _tripSub = FirebaseFirestore.instance
          .collection('trips')
          .doc(_tripId)
          .snapshots()
          .listen(
        (doc) {
          if (!mounted || _navigated) return;
          if (!doc.exists) return;
          final status = doc.data()?['status'] ?? '';
          final driverName = doc.data()?['driverName'] as String?;
          if (status == 'accepted' || status == 'in_progress') {
            _navigateToConfirmed(driverName);
          }
        },
        onError: (_) {
          // Listener failed (likely a Firestore permission error on status change).
          // The polling timer below will catch the acceptance instead.
        },
      );

      // Polling fallback — fires every 5 s in case the listener misses an update
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_tripId == null || _navigated || !mounted) return;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('trips')
              .doc(_tripId)
              .get();
          if (!doc.exists) return;
          final status = doc.data()?['status'] ?? '';
          final driverName = doc.data()?['driverName'] as String?;
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

  @override
  void dispose() {
    _pulse.dispose();
    _tripSub?.cancel();
    _pollTimer?.cancel();
    // If the passenger navigated away (back button) without a driver accepting,
    // cancel the trip so it doesn't accumulate as a stale 'requested' entry.
    if (_tripId != null && !_navigated) {
      DatabaseService.instance.cancelTrip(_tripId!).catchError((_) {});
    }
    super.dispose();
  }

  void _cancel() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancel Booking?'),
        content: Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('No')),
          ElevatedButton(
            onPressed: () async {
              if (_tripId != null) {
                await DatabaseService.instance.cancelTrip(_tripId!);
              }
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Booking cancelled')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF4F6FA),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Spacer(),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(
                scale: 0.92 + _pulse.value * 0.16,
                child: child,
              ),
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.4),
                      blurRadius: 30, spreadRadius: 8)],
                ),
                child: Icon(Icons.sailing, size: 60, color: Colors.white),
              ),
            ),
            SizedBox(height: 36),
            Text('Searching for driver...',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('This usually takes 30–60 seconds',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Colors.grey.shade200,
                color: Colors.blue.shade700,
              ),
            ),
            SizedBox(height: 16),
            Text('${widget.pickup} → ${widget.dropoff}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                textAlign: TextAlign.center),
            Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: TextButton(
                onPressed: _cancel,
                child: Text('Cancel Booking',
                    style: TextStyle(
                        color: Colors.red.shade600,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== WEEK 5: ACTIVE TRIP SCREEN =====
class ActiveTripScreen extends StatefulWidget {
  final String driverName, vehicleType, pickup, dropoff;
  final double rating, fareTotal;
  const ActiveTripScreen({
    required this.driverName, required this.vehicleType,
    required this.rating, required this.pickup,
    required this.dropoff, required this.fareTotal,
  });
  @override
  _ActiveTripScreenState createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  int _statusIdx = 0;
  final _statuses = ['Driver en route', 'Driver arrived', 'Trip in progress'];
  LatLng _driverPos = LatLng(25.6950, 32.6380);
  StreamSubscription<LatLngPoint>? _locSub;

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
      setState(() => _statusIdx++);
    } else {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => TripCompletionScreen(
                    driverName: widget.driverName,
                    pickup: widget.pickup,
                    dropoff: widget.dropoff,
                    distanceKm: 4.2,
                    durationMin: 14,
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
                      _iconBtn(Icons.phone, Colors.grey, () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Calling driver...')))),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Trip Complete'),
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
              Text('Trip Complete!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Thanks for riding with ${widget.driverName}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center),
              SizedBox(height: 24),
              // Summary card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Column(
                  children: [
                    _summaryRow(Icons.route, 'Distance', '${widget.distanceKm.toStringAsFixed(1)} km'),
                    Divider(height: 20),
                    _summaryRow(Icons.timer, 'Duration', '${widget.durationMin} min'),
                    Divider(height: 20),
                    _summaryRow(Icons.attach_money, 'Fare',
                        '${widget.fareTotal.toStringAsFixed(0)} EGP',
                        valueColor: Colors.teal.shade700),
                    Divider(height: 20),
                    _summaryRow(Icons.trip_origin, 'From', widget.pickup),
                    Divider(height: 12),
                    _summaryRow(Icons.location_on, 'To', widget.dropoff),
                  ],
                ),
              ),
              SizedBox(height: 24),
              // Star rating
              Text('Rate your driver',
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
                        child: Text('Submit Rating',
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
                child: Text('Skip',
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
