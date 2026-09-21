// lib/main.dart - FluTour Admin Panel
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models.dart';
import 'database_service.dart';
import 'location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase unavailable — app will show error states on each screen
  }
  // Load persisted login session before UI renders
  await AdminAuthService.loadSession();
  runApp(FluTourAdminApp());
}

class FluTourAdminApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluTour Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Color(0xFFF5F6FA),
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
      // Navigation guard: go straight to dashboard if session is active
      home: AdminAuthService.isLoggedIn ? AdminDashboardScreen() : AdminLoginScreen(),
    );
  }
}

// ===== ADMIN AUTH SERVICE =====
class AdminAuthService {
  static String _currentAdminEmail = '';
  static String _currentAdminRole = 'admin';

  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;
  static String get currentAdminEmail => _currentAdminEmail;
  static String get currentAdminRole => _currentAdminRole;

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _currentAdminEmail = prefs.getString('admin_email') ?? '';
    _currentAdminRole = prefs.getString('admin_role') ?? 'admin';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _currentAdminEmail.isEmpty) {
      _currentAdminEmail = user.email ?? '';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        _currentAdminRole = doc.data()?['role'] ?? 'admin';
        await prefs.setString('admin_email', _currentAdminEmail);
        await prefs.setString('admin_role', _currentAdminRole);
      } catch (_) {}
    }
  }

  static Future<String?> signIn(String email, String password) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(cred.user!.uid).get();
      final role = doc.data()?['role'] ?? '';
      if (role != 'admin' && role != 'super-admin') {
        await FirebaseAuth.instance.signOut();
        return 'Access denied: not an admin account';
      }
      _currentAdminEmail = email.trim();
      _currentAdminRole = role;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_email', _currentAdminEmail);
      await prefs.setString('admin_role', _currentAdminRole);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'Admin account not found';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') return 'Incorrect email or password';
      return e.message ?? 'Sign in failed';
    } catch (_) {
      return 'Service unavailable. Please check your connection.';
    }
  }

  static Future<void> signOut() async {
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    _currentAdminEmail = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_email');
    await prefs.remove('admin_role');
  }
}

// ===== 1. ADMIN LOGIN SCREEN =====
class AdminLoginScreen extends StatefulWidget {
  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }
    setState(() => _isLoading = true);
    final error = await AdminAuthService.signIn(
        _emailController.text.trim(), _passwordController.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AdminDashboardScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A2E),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade700,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.deepPurple.withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(Icons.admin_panel_settings,
                            size: 60, color: Colors.white),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'FluTour Admin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Control Panel',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 50),
                Text('Email',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'admin@flutour.com',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon:
                        Icon(Icons.email, color: Colors.deepPurple.shade300),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text('Password',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon:
                        Icon(Icons.lock, color: Colors.deepPurple.shade300),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white38,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                SizedBox(height: 36),
                _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: Colors.deepPurple.shade300))
                    : SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Login as Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                SizedBox(height: 20),
                Center(
                  child: Text(
                    'FluTour Admin v1.0 — Authorized access only',
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== 2. ADMIN DASHBOARD SCREEN =====
class AdminDashboardScreen extends StatefulWidget {
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    DashboardHomeTab(),
    PassengersScreen(),
    DriversScreen(),
    BookingsScreen(),
    LiveMapScreen(),
    AdminSettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        items: [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.people), label: 'Passengers'),
          BottomNavigationBarItem(
              icon: Icon(Icons.drive_eta), label: 'Drivers'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Live Map'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ===== 3. DASHBOARD HOME TAB =====
class DashboardHomeTab extends StatefulWidget {
  @override
  _DashboardHomeTabState createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends State<DashboardHomeTab> {
  late Future<Map<String, dynamic>> _future;
  StreamSubscription<QuerySnapshot>? _activeTripsSub;
  StreamSubscription<QuerySnapshot>? _pendingDriversSub;
  int _liveActiveTrips = 0;
  int _livePendingDrivers = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Real-time active trip counter
    _activeTripsSub = FirebaseFirestore.instance
        .collection('trips')
        .where('status', whereIn: ['accepted', 'in_progress', 'arrived'])
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _liveActiveTrips = snap.docs.length);
    });
    // Real-time pending driver counter
    _pendingDriversSub = FirebaseFirestore.instance
        .collection('drivers')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _livePendingDrivers = snap.docs.length);
    });
  }

  @override
  void dispose() {
    _activeTripsSub?.cancel();
    _pendingDriversSub?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final results = await Future.wait([
      AdminDatabaseService.instance.getDashboardStats(),
      AdminDatabaseService.instance.getTrips(),
    ]);
    return {'stats': results[0], 'trips': results[1]};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                  SizedBox(height: 12),
                  Text('Could not load dashboard',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final stats = snap.data!['stats'] as DashboardStats;
        // Override with real-time counters when available
        final activeTrips = _liveActiveTrips > 0 ? _liveActiveTrips : stats.activeTrips;
        final pendingDrivers = _livePendingDrivers > 0 ? _livePendingDrivers : stats.pendingDrivers;
        final liveStats = DashboardStats(
          totalPassengers: stats.totalPassengers,
          activeDrivers: stats.activeDrivers,
          pendingDrivers: pendingDrivers,
          activeTrips: activeTrips,
          revenueToday: stats.revenueToday,
          tripsToday: stats.tripsToday,
        );
        final recentTrips = (snap.data!['trips'] as List<TripModel>).take(3).toList();
        return _buildContent(context, liveStats, recentTrips);
      },
    );
  }

  Widget _buildContent(BuildContext context, DashboardStats stats, List<TripModel> recentTrips) {

    return Scaffold(
      body: Column(
        children: [
          // ── Blue gradient app bar ─────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.blue.shade600],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Good morning, Admin',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      SizedBox(height: 2),
                      Text('FluTour Dashboard',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    await AdminAuthService.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => AdminLoginScreen()));
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('⚙ Settings',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 4 stat cards in one row
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Passengers', '${stats.totalPassengers}', Icons.person, Colors.blue)),
                      SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Drivers', '${stats.activeDrivers}', Icons.drive_eta, Colors.green)),
                      SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Active Trips', '${stats.activeTrips}', Icons.circle, Colors.orange)),
                      SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Pending', '${stats.pendingDrivers}', Icons.pending_actions, Colors.red)),
                    ],
                  ),
                  SizedBox(height: 18),

                  // Pending alert
                  if (stats.pendingDrivers > 0) ...[
                    GestureDetector(
                      onTap: () {
                        final dashState = context.findAncestorStateOfType<_AdminDashboardScreenState>();
                        dashState?.setState(() => dashState._selectedIndex = 2);
                      },
                      child: Container(
                        padding: EdgeInsets.all(13),
                        margin: EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                          SizedBox(width: 10),
                          Expanded(child: Text('${stats.pendingDrivers} driver(s) pending approval — Tap to review',
                              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600, fontSize: 13))),
                          Icon(Icons.arrow_forward_ios, size: 13, color: Colors.orange.shade700),
                        ]),
                      ),
                    ),
                  ],

                  // Quick Actions 2x2 grid
                  Text('Quick Actions',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.0,
                    children: [
                      _buildActionCard('Live Map', '${stats.activeTrips} trips active', Icons.map, Colors.blue, () {
                        final dashState = context.findAncestorStateOfType<_AdminDashboardScreenState>();
                        dashState?.setState(() => dashState._selectedIndex = 4);
                      }),
                      _buildActionCard('Drivers', '${stats.pendingDrivers} pending approval', Icons.drive_eta, Colors.green, () {
                        final dashState = context.findAncestorStateOfType<_AdminDashboardScreenState>();
                        dashState?.setState(() => dashState._selectedIndex = 2);
                      }),
                      _buildActionCard('Passengers', '${stats.totalPassengers} registered', Icons.people, Colors.orange, () {
                        final dashState = context.findAncestorStateOfType<_AdminDashboardScreenState>();
                        dashState?.setState(() => dashState._selectedIndex = 1);
                      }),
                      _buildActionCard('All Trips', '${stats.activeTrips} active now', Icons.receipt_long, Colors.red, () {
                        final dashState = context.findAncestorStateOfType<_AdminDashboardScreenState>();
                        dashState?.setState(() => dashState._selectedIndex = 3);
                      }),
                    ],
                  ),
                  SizedBox(height: 18),

                  // Recent Trips
                  Text('Recent Trips',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  if (recentTrips.isEmpty)
                    Text('No trips yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                  else
                    ...recentTrips.map((t) => _buildRecentTripRow(t)),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.shade50, shape: BoxShape.circle),
            child: Icon(icon, color: color.shade600, size: 20),
          ),
          SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
          SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildActionCard(String name, String sub, IconData icon, MaterialColor color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.shade50, shape: BoxShape.circle),
              child: Icon(icon, color: color.shade600, size: 22),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTripRow(TripModel trip) {
    final Color statusColor = trip.status == TripStatus.completed
        ? Colors.green
        : trip.status == TripStatus.inProgress || trip.status == TripStatus.accepted
            ? Colors.orange
            : Colors.red;
    final bool isFelucca = trip.vehicleType == VehicleType.felucca;
    return Container(
      margin: EdgeInsets.only(bottom: 9),
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isFelucca ? Colors.blue.shade50 : Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(isFelucca ? Icons.sailing : Icons.directions_car,
                color: isFelucca ? Colors.blue.shade700 : Colors.orange.shade700, size: 18),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${trip.passengerName} · ${trip.vehicleType.label}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${trip.driverName} · ${trip.date.toLocal().toString().substring(0, 10)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${trip.fare.toStringAsFixed(0)} EGP',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade700)),
              SizedBox(height: 3),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(trip.status.label,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== 4. PASSENGERS SCREEN =====
class PassengersScreen extends StatefulWidget {
  @override
  _PassengersScreenState createState() => _PassengersScreenState();
}

class _PassengersScreenState extends State<PassengersScreen> {
  String _search = '';
  late Future<List<PassengerModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminDatabaseService.instance.getPassengers();
  }

  List<PassengerModel> _applySearch(List<PassengerModel> list) {
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.phone.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Passengers'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search passengers...',
                prefixIcon: Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Color(0xFFF5F6FA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<PassengerModel>>(
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
                  Text('Could not load passengers',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() =>
                        _future = AdminDatabaseService.instance.getPassengers()),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final all = snap.data ?? [];
          final filtered = _applySearch(all);
          final activeCount = all.where((p) => p.status == UserAccountStatus.active).length;
          final blockedCount = all.where((p) => p.status == UserAccountStatus.blocked).length;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildChip('Total: ${all.length}', Colors.blue),
                    SizedBox(width: 8),
                    _buildChip('Active: $activeCount', Colors.green),
                    SizedBox(width: 8),
                    _buildChip('Blocked: $blockedCount', Colors.red),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('No passengers found', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _buildPassengerCard(filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChip(String label, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Text(label,
          style: TextStyle(
              color: color.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildPassengerCard(PassengerModel passenger) {
    final bool isBlocked = passenger.status == UserAccountStatus.blocked;
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
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isBlocked ? Colors.red.shade100 : Colors.blue.shade100,
                child: Text(
                  passenger.name.isNotEmpty ? passenger.name[0] : '?',
                  style: TextStyle(
                    color: isBlocked ? Colors.red.shade700 : Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(passenger.name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(passenger.phone,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isBlocked ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isBlocked ? 'Blocked' : 'Active',
                  style: TextStyle(
                    color: isBlocked ? Colors.red : Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.directions_boat, size: 13, color: Colors.blue.shade400),
              SizedBox(width: 4),
              Text('${passenger.totalRides} rides',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              SizedBox(width: 12),
              Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade400),
              SizedBox(width: 4),
              Text('Joined ${passenger.joinedAt.year}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Spacer(),
              OutlinedButton(
                onPressed: () async {
                  final newStatus = isBlocked
                      ? UserAccountStatus.active
                      : UserAccountStatus.blocked;
                  await AdminDatabaseService.instance
                      .setPassengerStatus(passenger.uid, newStatus);
                  setState(() => _future =
                      AdminDatabaseService.instance.getPassengers());
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isBlocked ? Colors.green : Colors.red,
                  side: BorderSide(color: isBlocked ? Colors.green : Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size(0, 32),
                ),
                child: Text(isBlocked ? 'Unblock' : 'Block',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== 5. DRIVERS SCREEN =====
class DriversScreen extends StatefulWidget {
  @override
  _DriversScreenState createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final models = await AdminDatabaseService.instance.getDrivers();
      if (!mounted) return;
      setState(() {
        _drivers = models.map((m) => {
          'uid': m.uid,
          'id': m.uid.length > 6 ? m.uid.substring(0, 6).toUpperCase() : m.uid,
          'name': m.name,
          'phone': m.phone,
          'type': m.vehicleType.label,
          'vehicle': m.vehicleId,
          'rating': m.rating,
          'trips': m.totalTrips,
          'status': m.status == DriverAccountStatus.approved
              ? 'Active'
              : m.status == DriverAccountStatus.pending
                  ? 'Pending'
                  : 'Blocked',
          'approved': m.status == DriverAccountStatus.approved,
          'photoUrl': m.photoUrl,
          'vehiclePhotoUrl': m.vehiclePhotoUrl,
          'licensePhotoUrl': m.licensePhotoUrl,
        }).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFiltered(String statusFilter) {
    return _drivers
        .where((d) =>
            (statusFilter == 'All' || d['status'] == statusFilter) &&
            (d['name']
                    .toString()
                    .toLowerCase()
                    .contains(_search.toLowerCase()) ||
                d['id']
                    .toString()
                    .toLowerCase()
                    .contains(_search.toLowerCase())))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Drivers'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: [
            Tab(text: 'All (${_drivers.length})'),
            Tab(
                text:
                    'Active (${_drivers.where((d) => d['status'] == 'Active').length})'),
            Tab(
                text:
                    'Pending (${_drivers.where((d) => d['status'] == 'Pending').length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search drivers...',
                prefixIcon: Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDriverList('All'),
                _buildDriverList('Active'),
                _buildDriverList('Pending'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverList(String filter) {
    final list = _getFiltered(filter);
    if (list.isEmpty) {
      return Center(
          child: Text('No drivers found',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (context, i) => _buildDriverCard(list[i]),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final bool isPending = driver['status'] == 'Pending';
    final bool isBlocked = driver['status'] == 'Blocked';
    final bool isActive = driver['status'] == 'Active';
    final String photoUrl = driver['photoUrl'] ?? '';
    final String vehiclePhotoUrl = driver['vehiclePhotoUrl'] ?? '';
    final String licensePhotoUrl = driver['licensePhotoUrl'] ?? '';
    final bool hasLicense = licensePhotoUrl.isNotEmpty;

    Color statusColor = isPending
        ? Colors.orange
        : isBlocked
            ? Colors.red
            : Colors.green;

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: avatar + name + status badge
          Row(
            children: [
              photoUrl.isNotEmpty
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(photoUrl),
                    )
                  : CircleAvatar(
                      radius: 24,
                      backgroundColor: statusColor.withOpacity(0.15),
                      child: Text(driver['name'][0],
                          style: TextStyle(
                              color: statusColor, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver['name'],
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('${driver['type']} · ${driver['vehicle']}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    Text(driver['phone'] ?? '',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(driver['status'],
                    style: TextStyle(
                        color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          // Photo row: vehicle + license (tap to view full size)
          if (vehiclePhotoUrl.isNotEmpty || licensePhotoUrl.isNotEmpty) ...[
            SizedBox(height: 12),
            Row(
              children: [
                if (vehiclePhotoUrl.isNotEmpty)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showFullPhoto(context, vehiclePhotoUrl, 'Vehicle Photo'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vehicle', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(vehiclePhotoUrl,
                                height: 80, width: double.infinity, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    height: 80,
                                    color: Colors.grey.shade100,
                                    child: Icon(Icons.broken_image, color: Colors.grey))),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (vehiclePhotoUrl.isNotEmpty && licensePhotoUrl.isNotEmpty)
                  SizedBox(width: 10),
                if (licensePhotoUrl.isNotEmpty)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showFullPhoto(context, licensePhotoUrl, 'Driver License'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('License', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            SizedBox(width: 4),
                            Icon(Icons.verified, size: 12, color: Colors.green),
                          ]),
                          SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(licensePhotoUrl,
                                height: 80, width: double.infinity, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    height: 80,
                                    color: Colors.grey.shade100,
                                    child: Icon(Icons.broken_image, color: Colors.grey))),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],

          // Missing license warning for pending drivers
          if (isPending && !hasLicense) ...[
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade600),
                  SizedBox(width: 6),
                  Text('No license uploaded — verify before approving',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ],
              ),
            ),
          ],

          SizedBox(height: 12),
          // Stats + action buttons
          Row(
            children: [
              if (!isPending) ...[
                Icon(Icons.star, size: 14, color: Colors.amber),
                SizedBox(width: 3),
                Text('${driver['rating']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                SizedBox(width: 12),
              ],
              Icon(Icons.directions_boat, size: 13, color: Colors.blue.shade400),
              SizedBox(width: 3),
              Text('${driver['trips']} trips',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Spacer(),
              if (isPending) ...[
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      driver['status'] = 'Active';
                      driver['approved'] = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${driver['name']} approved!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    final uid = driver['uid'] as String?;
                    if (uid != null) {
                      try {
                        await AdminDatabaseService.instance.approveDriver(uid);
                      } catch (_) {}
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size(0, 32),
                  ),
                  child: Text('Approve', style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
                SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    setState(() => driver['status'] = 'Blocked');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${driver['name']} rejected'),
                          backgroundColor: Colors.red),
                    );
                    final uid = driver['uid'] as String?;
                    if (uid != null) {
                      try {
                        await AdminDatabaseService.instance.rejectDriver(uid);
                      } catch (_) {}
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size(0, 32),
                  ),
                  child: Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ] else ...[
                OutlinedButton(
                  onPressed: () async {
                    final newStatus = isActive ? 'Blocked' : 'Active';
                    setState(() => driver['status'] = newStatus);
                    final uid = driver['uid'] as String?;
                    if (uid != null) {
                      try {
                        if (newStatus == 'Blocked') {
                          await AdminDatabaseService.instance.suspendDriver(uid);
                        } else {
                          await AdminDatabaseService.instance.approveDriver(uid);
                        }
                      } catch (_) {}
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isActive ? Colors.red : Colors.green,
                    side: BorderSide(color: isActive ? Colors.red : Colors.green),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size(0, 32),
                  ),
                  child: Text(isActive ? 'Block' : 'Unblock',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showFullPhoto(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.black,
              title: Text(title, style: TextStyle(color: Colors.white)),
              iconTheme: IconThemeData(color: Colors.white),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Could not load image',
                          style: TextStyle(color: Colors.white)),
                    )),
          ],
        ),
      ),
    );
  }
}

// ===== 6. BOOKINGS SCREEN =====
class BookingsScreen extends StatefulWidget {
  @override
  _BookingsScreenState createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String _filter = 'All';
  final List<String> _filters = ['All', 'Active', 'Completed', 'Cancelled'];
  late Future<List<TripModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminDatabaseService.instance.getTrips();
  }

  List<TripModel> _applyFilter(List<TripModel> trips) {
    if (_filter == 'All') return trips;
    return trips.where((t) {
      if (_filter == 'Active') {
        return t.status == TripStatus.accepted || t.status == TripStatus.inProgress || t.status == TripStatus.requested;
      }
      if (_filter == 'Completed') return t.status == TripStatus.completed;
      if (_filter == 'Cancelled') return t.status == TripStatus.cancelled;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Bookings'), centerTitle: true),
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
                  Text('Could not load bookings',
                      style: TextStyle(color: Colors.grey.shade600)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() =>
                        _future = AdminDatabaseService.instance.getTrips()),
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final filtered = _applyFilter(snap.data ?? []);
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: _filters
                      .map((f) => GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: Container(
                              margin: EdgeInsets.only(right: 10),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _filter == f ? Colors.deepPurple : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _filter == f
                                      ? Colors.deepPurple
                                      : Colors.grey.shade300,
                                ),
                                boxShadow: [
                                  if (_filter == f)
                                    BoxShadow(
                                        color: Colors.deepPurple.withOpacity(0.3),
                                        blurRadius: 8)
                                ],
                              ),
                              child: Text(f,
                                  style: TextStyle(
                                    color: _filter == f
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  )),
                            ),
                          ))
                      .toList(),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${filtered.length} bookings',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
              SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('No bookings found', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _buildBookingCard(filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBookingCard(TripModel t) {
    final Color statusColor = t.status == TripStatus.completed
        ? Colors.green
        : t.status == TripStatus.cancelled
            ? Colors.red
            : Colors.orange;
    final bool isFelucca = t.vehicleType == VehicleType.felucca;

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.id.length > 8 ? t.id.substring(0, 8).toUpperCase() : t.id,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t.status.label,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ),
          SizedBox(height: 12),
          _bookingRow(Icons.person, 'Passenger', t.passengerName),
          _bookingRow(Icons.drive_eta, 'Driver', t.driverName.isNotEmpty ? t.driverName : '—'),
          _bookingRow(
              isFelucca ? Icons.sailing : Icons.directions,
              'Vehicle',
              '${t.vehicleId} (${t.vehicleType.label})'),
          _bookingRow(Icons.payment, 'Payment', t.paymentMethod.label),
          _bookingRow(Icons.calendar_today, 'Date',
              t.date.toLocal().toString().substring(0, 10)),
          Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Amount',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              Text(
                t.fare > 0 ? 'EGP ${t.fare.toStringAsFixed(0)}' : '—',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.deepPurple),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bookingRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 13)),
          Expanded(
            child: Text(value,
                style:
                    TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ===== 7. LIVE MAP SCREEN =====
class LiveMapScreen extends StatefulWidget {
  @override
  _LiveMapScreenState createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final LatLng _luxor = LatLng(25.6872, 32.6396);

  List<LiveDriverInfo> _liveDrivers = [];
  List<Map<String, dynamic>> _activeTrips = [];
  StreamSubscription<List<LiveDriverInfo>>? _driverSub;
  StreamSubscription<QuerySnapshot>? _tripsSub;

  @override
  void initState() {
    super.initState();
    _driverSub = AdminLocationService.watchOnlineDrivers().listen((drivers) {
      if (mounted) setState(() => _liveDrivers = drivers);
    });
    _tripsSub = FirebaseFirestore.instance
        .collection('trips')
        .where('status', whereIn: ['accepted', 'in_progress', 'arrived'])
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activeTrips = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    });
  }

  @override
  void dispose() {
    _driverSub?.cancel();
    _tripsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Map'),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 6),
                    Text(
                        '${_liveDrivers.length} Online · ${_activeTrips.length} Trips',
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _luxor,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=rqp9ddE9k50t0V3suet2',
                userAgentPackageName: 'com.flutour.admin',
              ),
              MarkerLayer(
                markers: [
                  ..._liveDrivers.map((d) => Marker(
                        width: 50,
                        height: 50,
                        point: LatLng(d.lat, d.lng),
                        child: Tooltip(
                          message: '${d.driverName}${d.isOnTrip ? ' — On Trip' : ' — Available'}',
                          child: Container(
                            decoration: BoxDecoration(
                              color: d.isOnTrip ? Colors.orange : Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                            ),
                            child: Icon(
                              d.isOnTrip ? Icons.directions_car : Icons.sailing,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      )),
                  ..._activeTrips.where((t) {
                    final lat = (t['pickupLat'] as num?)?.toDouble();
                    final lng = (t['pickupLng'] as num?)?.toDouble();
                    return lat != null && lng != null;
                  }).map((t) {
                    final lat = (t['pickupLat'] as num?)!.toDouble();
                    final lng = (t['pickupLng'] as num?)!.toDouble();
                    return Marker(
                      width: 36,
                      height: 36,
                      point: LatLng(lat, lng),
                      child: Tooltip(
                        message: 'Passenger: ${t['passengerName'] ?? '—'}\n${t['pickup'] ?? ''}',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Icon(Icons.person_pin, color: Colors.white, size: 18),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          // Bottom legend panel
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live Driver Locations',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 10),
                  if (_liveDrivers.isEmpty)
                    Text('No drivers online',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ..._liveDrivers.map((d) => Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: d.isOnTrip
                                    ? Colors.orange
                                    : Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                d.isOnTrip
                                    ? Icons.directions_car
                                    : Icons.sailing,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${d.driverName} · ${d.isOnTrip ? "On Trip" : "Available"}',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (_activeTrips.isNotEmpty) ...[
                    Divider(height: 12),
                    Text('Active Trips (${_activeTrips.length})',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    SizedBox(height: 6),
                    ..._activeTrips.take(3).map((t) => Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Icon(Icons.person_pin, color: Colors.green.shade600, size: 16),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${t['passengerName'] ?? '—'} → ${t['driverName'] ?? '—'}',
                                style: TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                (t['status'] as String? ?? '').replaceAll('_', ' '),
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]),
                        )),
                  ],
                  SizedBox(height: 4),
                  Row(
                    children: [
                      _legendDot(Colors.blue),
                      SizedBox(width: 6),
                      Text('Available',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      SizedBox(width: 12),
                      _legendDot(Colors.orange),
                      SizedBox(width: 6),
                      Text('On Trip',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      SizedBox(width: 12),
                      _legendDot(Colors.green.shade600),
                      SizedBox(width: 6),
                      Text('Passenger',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ===== ADMIN SETTINGS TAB (Surge Pricing + Revenue Reports) =====
class AdminSettingsTab extends StatefulWidget {
  @override
  _AdminSettingsTabState createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<AdminSettingsTab> {
  double _feluccaMultiplier = 1.0;
  double _horseMultiplier = 1.0;
  bool _loadingMultipliers = true;
  bool _savingMultipliers = false;
  late Future<List<double>> _revenueFuture;
  late Future<List<Map<String, dynamic>>> _payoutsFuture;
  late Future<double> _platformEarningsFuture;
  final _instapayCtrl = TextEditingController();
  bool _savingInstapay = false;

  @override
  void initState() {
    super.initState();
    _loadMultipliers();
    _revenueFuture = _loadRevenue();
    _payoutsFuture = AdminDatabaseService.instance.getWithdrawalRequests(status: 'pending');
    _platformEarningsFuture = AdminDatabaseService.instance.getPlatformEarnings();
    _loadAdminInstapay();
  }

  Future<void> _loadAdminInstapay() async {
    final phone = await AdminDatabaseService.instance.getAdminInstapay();
    if (mounted) setState(() => _instapayCtrl.text = phone);
  }

  @override
  void dispose() {
    _instapayCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMultipliers() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('surge').get();
      if (doc.exists) {
        setState(() {
          _feluccaMultiplier = (doc.data()?['felucca'] as num?)?.toDouble() ?? 1.0;
          _horseMultiplier = (doc.data()?['horseCarriage'] as num?)?.toDouble() ?? 1.0;
        });
      }
    } catch (_) {}
    setState(() => _loadingMultipliers = false);
  }

  Future<void> _saveMultipliers() async {
    setState(() => _savingMultipliers = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('surge').set({
        'felucca': _feluccaMultiplier,
        'horseCarriage': _horseMultiplier,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Surge pricing saved'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _savingMultipliers = false);
  }

  /// Returns daily revenue totals for the last 7 days.
  Future<List<double>> _loadRevenue() async {
    final now = DateTime.now();
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6));
    final snap = await FirebaseFirestore.instance
        .collection('trips')
        .where('status', isEqualTo: 'completed')
        .get();
    final daily = List<double>.filled(7, 0.0);
    for (final doc in snap.docs) {
      final dt = (doc.data()['completedAt'] as Timestamp?)?.toDate();
      if (dt == null || dt.isBefore(sevenDaysAgo)) continue;
      final dayIndex = dt.difference(sevenDaysAgo).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        daily[dayIndex] += (doc.data()['fare'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return daily;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings'), centerTitle: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Platform earnings summary ────────────────────────────────────
            FutureBuilder<double>(
              future: _platformEarningsFuture,
              builder: (ctx, snap) {
                final total = snap.data ?? 0.0;
                return Container(
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance, color: Colors.white, size: 36),
                      SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Platform Earnings (15%)',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('EGP ${total.toStringAsFixed(0)}',
                              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                          Text('Total from all completed trips',
                              style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.refresh, color: Colors.white70),
                        onPressed: () => setState(() =>
                            _platformEarningsFuture = AdminDatabaseService.instance.getPlatformEarnings()),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── Pending withdrawal requests ──────────────────────────────────
            Text('Pending Withdrawals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Drivers requesting InstaPay payout. Send the amount, then tap Mark as Paid.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _payoutsFuture,
              builder: (ctx, snap) {
                if (!snap.hasData) return Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                final requests = snap.data!;
                if (requests.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(16),
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline, color: Colors.green.shade400, size: 20),
                      SizedBox(width: 10),
                      Text('No pending withdrawal requests', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ]),
                  );
                }
                return Column(
                  children: requests.map((req) {
                    final amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
                    final instapay = req['instapayPhone'] as String? ?? '—';
                    final driverName = req['driverName'] as String? ?? '—';
                    final driverId = req['driverId'] as String? ?? '';
                    final reqId = req['id'] as String;
                    final ts = (req['requestedAt'] as Timestamp?)?.toDate();
                    final dateStr = ts != null ? ts.toLocal().toString().substring(0, 10) : '—';
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.deepPurple.shade50,
                                child: Text(driverName.isNotEmpty ? driverName[0] : '?',
                                    style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold)),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(driverName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Text('Requested $dateStr', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Text('EGP ${amount.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                            ],
                          ),
                          SizedBox(height: 10),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: Row(children: [
                              Icon(Icons.phone, color: Colors.teal.shade700, size: 16),
                              SizedBox(width: 8),
                              Text('Send via InstaPay to: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              Text(instapay, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
                            ]),
                          ),
                          SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text('Mark as Paid?'),
                                    content: Text('Confirm you have sent EGP ${amount.toStringAsFixed(0)} to $driverName via InstaPay ($instapay).'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                        child: Text('Yes, Paid', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                try {
                                  await AdminDatabaseService.instance
                                      .markWithdrawalPaid(reqId, driverId, amount);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                        content: Text('Marked as paid — driver balance updated'),
                                        backgroundColor: Colors.green));
                                    setState(() => _payoutsFuture =
                                        AdminDatabaseService.instance.getWithdrawalRequests(status: 'pending'));
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                        content: Text('Error: $e'), backgroundColor: Colors.red));
                                  }
                                }
                              },
                              icon: Icon(Icons.check_circle, color: Colors.white),
                              label: Text('Mark as Paid', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Refresh Requests'),
                onPressed: () => setState(() =>
                    _payoutsFuture = AdminDatabaseService.instance.getWithdrawalRequests(status: 'pending')),
              ),
            ),
            SizedBox(height: 20),

            // ── Admin InstaPay number ────────────────────────────────────────
            Text('Admin InstaPay Number',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Drivers see this number to send cash trip commissions (15%). Keep it updated.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _instapayCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '01XXXXXXXXX',
                      prefixIcon: Icon(Icons.phone, color: Colors.deepPurple.shade400),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _savingInstapay ? null : () async {
                    setState(() => _savingInstapay = true);
                    try {
                      await AdminDatabaseService.instance.setAdminInstapay(_instapayCtrl.text.trim());
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Admin InstaPay saved'), backgroundColor: Colors.green));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
                    } finally {
                      if (mounted) setState(() => _savingInstapay = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  child: _savingInstapay
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 32),

            // ── Surge pricing ───────────────────────────────────────────────
            Text('Surge Pricing',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Multiplier applied to base fares in real time.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            SizedBox(height: 16),
            if (_loadingMultipliers)
              Center(child: CircularProgressIndicator())
            else ...[
              _multiplierRow('Felucca', _feluccaMultiplier, (v) => setState(() => _feluccaMultiplier = v)),
              SizedBox(height: 12),
              _multiplierRow('Horse Carriage', _horseMultiplier, (v) => setState(() => _horseMultiplier = v)),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _savingMultipliers ? null : _saveMultipliers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _savingMultipliers
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save Surge Multipliers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            SizedBox(height: 32),

            // ── Revenue report ──────────────────────────────────────────────
            Text('Revenue — Last 7 Days',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            FutureBuilder<List<double>>(
              future: _revenueFuture,
              builder: (ctx, snap) {
                if (!snap.hasData) return Center(child: CircularProgressIndicator());
                final daily = snap.data!;
                final total = daily.fold<double>(0, (s, v) => s + v);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.payments, color: Colors.white, size: 32),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Revenue (7 days)',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('EGP ${total.toStringAsFixed(0)}',
                                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    _RevenueBarChart(daily: daily),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: Icon(Icons.refresh),
                        label: Text('Refresh'),
                        onPressed: () => setState(() => _revenueFuture = _loadRevenue()),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Promo code management ───────────────────────────────────────
            SizedBox(height: 32),
            Text('Promo Codes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            _PromoCodeManager(),
          ],
        ),
      ),
    );
  }

  Widget _multiplierRow(String label, double value, ValueChanged<double> onChanged) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: value > 1.0 ? Colors.orange.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)}x',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: value > 1.0 ? Colors.orange.shade800 : Colors.green.shade800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 1.0,
            max: 3.0,
            divisions: 20,
            activeColor: value > 1.5 ? Colors.orange : Colors.blue,
            label: '${value.toStringAsFixed(1)}x',
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1.0x (Normal)', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('3.0x (High demand)', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevenueBarChart extends StatelessWidget {
  final List<double> daily;
  const _RevenueBarChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final maxVal = daily.fold<double>(0, (m, v) => v > m ? v : m);
    final days = ['6d', '5d', '4d', '3d', '2d', 'Yest', 'Today'];
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
                    Text('${val.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 9, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 600),
                    height: (100 * ratio).clamp(4, 100).toDouble(),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.blue.shade700 : Colors.blue.shade200,
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

class _PromoCodeManager extends StatefulWidget {
  @override
  _PromoCodeManagerState createState() => _PromoCodeManagerState();
}

class _PromoCodeManagerState extends State<_PromoCodeManager> {
  final _codeCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  late Future<QuerySnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance.collection('promoCodes').get();
  }

  Future<void> _addPromo() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final pct = double.tryParse(_discountCtrl.text.trim());
    if (code.isEmpty || pct == null || pct <= 0 || pct > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid code and discount %')));
      return;
    }
    await FirebaseFirestore.instance.collection('promoCodes').add({
      'code': code,
      'discountPercent': pct,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _codeCtrl.clear();
    _discountCtrl.clear();
    setState(() => _future = FirebaseFirestore.instance.collection('promoCodes').get());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add new promo
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Code',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _discountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '% Off',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addPromo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              child: Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        SizedBox(height: 12),
        // List existing promos
        FutureBuilder<QuerySnapshot>(
          future: _future,
          builder: (ctx, snap) {
            if (!snap.hasData) return Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return Text('No promo codes yet.', style: TextStyle(color: Colors.grey));
            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final active = data['active'] as bool? ?? false;
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
                      Icon(Icons.local_offer,
                          color: active ? Colors.green.shade600 : Colors.grey, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['code'] ?? '',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('${data['discountPercent']}% off',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                      ),
                      Switch(
                        value: active,
                        activeColor: Colors.green,
                        onChanged: (val) async {
                          await doc.reference.update({'active': val});
                          setState(() => _future =
                              FirebaseFirestore.instance.collection('promoCodes').get());
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
