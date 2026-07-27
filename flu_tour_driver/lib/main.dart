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
  await DriverAuthService.loadSession();
  runApp(FluTourDriverApp());
}

class FluTourDriverApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluTour Driver',
      debugShowCheckedModeBanner: false,
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
  static String _tempVehicleId = '';
  static String _tempVehicleType = '';

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
  static String get currentDriverId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  static String get currentDriverName => _currentDriverName;
  static String get currentDriverPhone => _currentDriverPhone;
  static String get currentVehicleType => _currentVehicleType;

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDriverName = prefs.getString('driver_name') ?? '';
    _currentDriverPhone = prefs.getString('driver_phone') ?? '';
    final rawType = prefs.getString('driver_vehicle_type') ?? '';
    // Always normalize — old registrations stored 'Felucca'/'Horse Carriage', new ones store 'felucca'/'horse_carriage'
    _currentVehicleType = rawType.isEmpty ? '' : VehicleTypeX.fromString(rawType).value;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && (_currentDriverName.isEmpty || _currentVehicleType.isEmpty)) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('drivers').doc(user.uid).get();
        _currentDriverName = doc.data()?['name'] ?? '';
        _currentDriverPhone = doc.data()?['phone'] ?? '';
        _currentVehicleType = VehicleTypeX.fromString(doc.data()?['vehicleType'] ?? '').value;
        await prefs.setString('driver_name', _currentDriverName);
        await prefs.setString('driver_phone', _currentDriverPhone);
        await prefs.setString('driver_vehicle_type', _currentVehicleType);
      } catch (_) {}
    }
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

    Timer(Duration(seconds: 3), () {
      if (!mounted) return;
      // Navigation guard: skip login if already authenticated
      if (DriverAuthService.isLoggedIn) {
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
                          Text(
                            'FluTour Driver',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Your ride, your earnings',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
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
                    child: Text(
                      'Get Started',
                      style: TextStyle(
                        color: Color(0xFF004D40),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
        SnackBar(content: Text('Please enter phone number and password')),
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
                    Text('Driver Login',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('Sign in to start accepting rides',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 14)),
                  ],
                ),
              ),
              SizedBox(height: 40),
              Text('Phone Number',
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
              Text('Password',
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
                          'Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => DriverRegisterScreen())),
                  child: Text(
                    "New driver? Register here",
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Register as Driver'),
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
            Center(
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_add,
                    size: 50, color: Colors.teal.shade700),
              ),
            ),
            SizedBox(height: 24),
            _buildField('Full Name', 'Hassan Mahmoud', Icons.person,
                _nameController, TextInputType.name),
            SizedBox(height: 16),
            _buildField('Phone Number', '01XXXXXXXXX', Icons.phone,
                _phoneController, TextInputType.phone),
            SizedBox(height: 16),
            _buildField('Vehicle ID', 'e.g. F072 or H062', Icons.directions_boat,
                _vehicleController, TextInputType.text),
            SizedBox(height: 16),
            Text('Vehicle Type',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            Row(
              children: ['Felucca', 'Horse Carriage'].map((type) {
                final selected = _selectedType == type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: Container(
                      margin: EdgeInsets.only(
                          right: type == 'Felucca' ? 8 : 0),
                      padding: EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.teal.shade700
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected
                                ? Colors.teal.shade700
                                : Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            type == 'Felucca'
                                ? Icons.sailing
                                : Icons.directions,
                            color: selected ? Colors.white : Colors.grey,
                            size: 28,
                          ),
                          SizedBox(height: 6),
                          Text(type,
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
            ),
            SizedBox(height: 16),
            Text('Password',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: 'Create a password (min 6 characters)',
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
            Text('Confirm Password',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 8),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                hintText: 'Re-enter your password',
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
                            SnackBar(content: Text('Please fill in all fields')),
                          );
                          return;
                        }
                        if (password != confirmPassword) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Passwords do not match')),
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
                        setState(() => _isLoading = false);
                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)));
                        } else {
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
                      child: Text('Submit Registration',
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
              Text('Application Submitted!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: 12),
              Text(
                'Hi $name, your registration is under review.\n\nAdmin will approve your account within 1–2 business days. You\'ll be notified once approved.',
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
                      'Have your licence and insurance documents ready. Admin may contact you for verification.',
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
                  child: Text('Back to Login',
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
              icon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_active), label: 'Requests'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Trips'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet), label: 'Earnings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Profile'),
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
          .map((snap) => snap.docs.map((d) {
                final data = d.data();
                return {
                  'id': d.id,
                  'passenger': data['passengerName'] ?? 'Passenger',
                  'pickup': data['pickup'] ?? '',
                  'dropoff': data['dropoff'] ?? '',
                  'vehicleType': data['vehicleType'] ?? '',
                  'distance': '—',
                  'duration': '—',
                  'amount': (data['fare'] as num?)?.toDouble() ?? 0.0,
                  'payment': data['paymentMethod'] ?? 'cash',
                  'time': 'Just now',
                };
              }).toList());

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    // Show a SnackBar when a trip-request FCM notification arrives in the foreground
    _fcmSub = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      final type = message.data['type'] ?? '';
      if (type == 'trip_request' || message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification?.body ?? 'New trip request!'),
            backgroundColor: Colors.teal.shade700,
            duration: const Duration(seconds: 10),
          ),
        );
      }
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
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sailing, color: Colors.teal.shade700, size: 22),
            SizedBox(width: 8),
            Text('FluTour Driver'),
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
                        DriverAuthService.currentDriverId);
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
                      _isOnline ? 'You are ONLINE' : 'You are OFFLINE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _isOnline
                          ? 'Tap to go offline'
                          : 'Tap to start accepting rides',
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
                  Text("Today's Summary",
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
                              child: _buildStatCard('Trips Today', '$tripsToday',
                                  Icons.directions_boat, Colors.blue)),
                          SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard('Earned Today',
                                  'EGP ${earnedToday.toStringAsFixed(0)}',
                                  Icons.account_balance_wallet, Colors.teal)),
                          SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard('Rating',
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
                            Text('New Ride Request!',
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
                  Text('Your Location',
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
                  onPressed: () async {
                    try {
                      await DriverDatabaseService.instance.declineTrip(req['id']);
                    } catch (_) {}
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Decline'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await DriverDatabaseService.instance.acceptTrip(
                        req['id'],
                        DriverAuthService.currentDriverId,
                        DriverAuthService.currentDriverName,
                      );
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActiveRideScreen(request: req),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Accept failed: $e'),
                            duration: Duration(seconds: 10),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Accept',
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
  final Set<String> _declinedIds = {}; // trips declined by this driver (hidden locally)

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('trips')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .handleError((e) {
          if (mounted) setState(() => _streamError = e.toString());
        })
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return {
                'id': d.id,
                'passenger': data['passengerName'] ?? 'Passenger',
                'pickup': data['pickup'] ?? '',
                'dropoff': data['dropoff'] ?? '',
                'vehicleType': data['vehicleType'] ?? '',
                'distance': '—',
                'duration': '—',
                'amount': (data['fare'] as num?)?.toDouble() ?? 0.0,
                'payment': data['paymentMethod'] ?? 'cash',
                'time': 'Just now',
              };
            }).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ride Requests'), centerTitle: true),
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
                    Text('Could not load requests',
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
              .where((r) => !_declinedIds.contains(r['id'] as String))
              .toList();
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 60, color: Colors.grey.shade300),
                  SizedBox(height: 16),
                  Text('No ride requests right now',
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
                        '${req['vehicleType'] == 'felucca' ? 'Felucca' : 'Horse Carriage'} · ${req['payment']}',
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
                    Icons.trip_origin, Colors.green, 'From', req['pickup']),
                Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Container(
                    height: 20,
                    width: 1,
                    color: Colors.grey.shade300,
                  ),
                ),
                _locationRow(
                    Icons.location_on, Colors.red, 'To', req['dropoff']),
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
                    // Hide this trip from this driver's list (stays visible to other drivers)
                    setState(() => _declinedIds.add(req['id'] as String));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Decline', style: TextStyle(fontSize: 15)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _acceptingIds.contains(req['id'] as String)
                      ? null
                      : () async {
                          final tripId = req['id'] as String;
                          setState(() => _acceptingIds.add(tripId));
                          try {
                            await DriverDatabaseService.instance.acceptTrip(
                              tripId,
                              DriverAuthService.currentDriverId,
                              DriverAuthService.currentDriverName,
                            );
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ActiveRideScreen(request: req),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) setState(() => _acceptingIds.remove(tripId));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Accept failed: $e'),
                                  duration: Duration(seconds: 10),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _acceptingIds.contains(req['id'] as String)
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Accept',
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
  final List<String> _stepLabels = [
    'Heading to Pickup',
    'Arrived at Pickup',
    'Trip in Progress',
    'Trip Completed',
  ];

  final LatLng _luxor = LatLng(25.6872, 32.6396);
  LatLng? _driverPos;
  StreamSubscription<Position>? _posStream;
  final MapController _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  void _startTracking() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
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
    });
  }

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  Future<void> _nextStep() async {
    final tripId = widget.request['id'] as String? ?? '';
    try {
      if (_step == 0) {
        // Heading → Arrived: tell Firestore driver has arrived at pickup
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.arriveTrip(tripId);
        }
        setState(() => _step = 1);
      } else if (_step == 1) {
        // Arrived → Trip in Progress: start the ride
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.startTrip(tripId);
        }
        setState(() => _step = 2);
      } else if (_step == 2) {
        // In Progress → Complete: finish the trip
        if (tripId.isNotEmpty) {
          await DriverDatabaseService.instance.completeTrip(
              tripId,
              (widget.request['amount'] as num?)?.toDouble() ?? 0.0,
              DriverAuthService.currentDriverId);
        }
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
              Text('Trip Complete!'),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings for this trip:',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                SizedBox(height: 10),
                Text('${fare.toStringAsFixed(0)} EGP',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        color: Colors.teal.shade700)),
                SizedBox(height: 4),
                Text('Your share (85%): ${earning.toStringAsFixed(0)} EGP',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => DriverHomeScreen()),
                    (_) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700),
                child: Text('Back to Dashboard',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $e'), duration: Duration(seconds: 6)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Ride'),
        centerTitle: true,
        leading: _step == 0
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
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
                _stepLabels[_step],
                style: TextStyle(
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
          ),

          // Map
          Expanded(
            child: FlutterMap(
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
                      point: LatLng(25.6900, 32.6370),
                      child: Icon(Icons.trip_origin,
                          color: Colors.green, size: 32),
                    ),
                    Marker(
                      width: 36,
                      height: 36,
                      point: LatLng(25.6840, 32.6450),
                      child: Icon(Icons.location_on,
                          color: Colors.red, size: 32),
                    ),
                  ],
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
                SizedBox(height: 16),
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
                          ? 'Arrived at Pickup'
                          : _step == 1
                              ? 'Start Trip'
                              : _step == 2
                                  ? 'Complete Trip'
                                  : 'Done — Back to Home',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
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
    return Scaffold(
      appBar: AppBar(title: Text('Trip History'), centerTitle: true),
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
                  Text('Could not load trip history',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future =
                        DriverDatabaseService.instance
                            .getTripHistory(DriverAuthService.currentDriverId)),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final trips = snap.data ?? [];
          if (trips.isEmpty) {
            return Center(child: Text('No trips yet'));
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
    ]);
    return {'summary': results[0], 'profile': results[1]};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Earnings'), centerTitle: true),
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
                  Text('Could not load earnings',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _future = _loadData()),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final summary = snap.data?['summary'] as EarningsSummary? ??
              EarningsSummary(today: 0, thisWeek: 0, thisMonth: 0, tripsToday: 0, tripsThisWeek: 0);
          final profile = snap.data?['profile'] as DriverModel?;

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
                      Text('This Month',
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
                          _balanceStat('Total Trips', '${profile?.totalTrips ?? 0}'),
                          SizedBox(width: 24),
                          _balanceStat('Rating', '${(profile?.rating ?? 0.0).toStringAsFixed(1)} ★'),
                          SizedBox(width: 24),
                          _balanceStat('Vehicle', profile?.vehicleId ?? '—'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Text('This Period',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatBox('Today\nTrips', '${summary.tripsToday}', Colors.teal)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatBox('Today\nEarned', 'EGP ${summary.today.toStringAsFixed(0)}', Colors.green)),
                    SizedBox(width: 12),
                    Expanded(child: _buildStatBox('This Week', 'EGP ${summary.thisWeek.toStringAsFixed(0)}', Colors.orange)),
                  ],
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('Withdraw Earnings'),
                          content: Text(
                              'Withdrawal will be processed within 24 hours via Vodafone Cash or InstaPay.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700),
                              child: Text('Confirm',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.account_balance_wallet, color: Colors.white),
                    label: Text('Withdraw Earnings',
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

// ===== 10. PROFILE TAB =====
class DriverProfileTab extends StatefulWidget {
  @override
  _DriverProfileTabState createState() => _DriverProfileTabState();
}

class _DriverProfileTabState extends State<DriverProfileTab> {
  late Future<DriverModel> _future;

  @override
  void initState() {
    super.initState();
    _future = DriverDatabaseService.instance
        .getDriverProfile(DriverAuthService.currentDriverId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Profile'), centerTitle: true),
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
                  Text('Could not load profile',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future =
                        DriverDatabaseService.instance
                            .getDriverProfile(DriverAuthService.currentDriverId)),
                    child: Text('Retry'),
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
                      CircleAvatar(
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
                          Text('${rating.toStringAsFixed(1)} Rating',
                              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                          SizedBox(width: 16),
                          Icon(Icons.circle, color: Colors.green, size: 10),
                          SizedBox(width: 4),
                          Text('Approved Driver',
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
                _buildSection('Vehicle Information', [
                  _profileRow(Icons.directions_boat, 'Vehicle Type', vehicleType),
                  _profileRow(Icons.numbers, 'Vehicle ID', vehicleId),
                  _profileRow(Icons.route, 'Total Trips', '$totalTrips trips'),
                ]),
                SizedBox(height: 16),
                _buildSection('Account', [
                  _actionRow(Icons.lock, 'Change Password', Colors.blue, () {}),
                  _actionRow(Icons.support_agent, 'Contact Support', Colors.teal, () {}),
                  _actionRow(Icons.logout, 'Logout', Colors.red, () async {
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
        SnackBar(content: Text('Request timed out — auto declined')));
  }

  void _accept() async {
    _countdown?.cancel();
    try {
      await DriverDatabaseService.instance.acceptTrip(
        widget.request['id'],
        DriverAuthService.currentDriverId,
        DriverAuthService.currentDriverName,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept trip. Please try again.')));
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                DriverActiveTripScreen(request: widget.request)));
  }

  void _decline() {
    _countdown?.cancel();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request declined')));
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final bool urgent = _seconds < 10;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text('New Ride Request'),
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
              Text(urgent ? 'Expiring soon!' : 'Seconds remaining',
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
                        child: Text('Felucca',
                            style: TextStyle(color: Colors.teal.shade700,
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ]),
                    SizedBox(height: 14),
                    _reqRow(Icons.trip_origin, Colors.green, '${req['pickup']} → ${req['dropoff']}'),
                    SizedBox(height: 8),
                    _reqRow(Icons.route, Colors.blue, '${req['distance']} · ~\$${req['amount'].toStringAsFixed(0)} EGP · ${req['duration']}'),
                    SizedBox(height: 8),
                    _reqRow(Icons.access_time, Colors.grey, '${req['time']} · ${req['payment']}'),
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
                      child: Text('✗  Decline',
                          style: TextStyle(color: Colors.grey.shade700,
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _accept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text('✓  Accept',
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
  final _steps = ['Navigate to Passenger', 'Arrived at Pickup', 'Trip Started', 'Trip Completed'];
  final _stepColors = [Colors.blue, Colors.orange, Colors.teal, Colors.green];

  void _advance() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_steps[_step])));
    } else {
      _showComplete();
    }
  }

  void _showComplete() {
    final fare = widget.request['amount'] as double;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Trip Complete!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Earnings for this trip:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            SizedBox(height: 8),
            Text('${fare.toStringAsFixed(0)} EGP (fare)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal.shade700)),
            SizedBox(height: 4),
            Text('${(fare * 0.8).toStringAsFixed(0)} EGP (after 20% commission)',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => DriverHomeScreen()),
                  (_) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: Text('Back to Dashboard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Trip'),
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
                Row(children: List.generate(_steps.length, (i) => Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < _steps.length - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step ? _stepColors[_step] : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ))),
                SizedBox(height: 10),
                Text(_steps[_step],
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
                      _step < _steps.length - 1 ? _steps[_step + 1] : 'Complete Trip',
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
