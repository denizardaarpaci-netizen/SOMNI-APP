
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Do not let a remembered browser/Firebase session bypass the login form.
  // A fresh email + password sign-in is required every time SOMNI starts.
  await FirebaseAuth.instance.signOut();

  runApp(const SomniApp());
}




class UserProfile {
  String name;
  String email;
  String age;
  String height;
  String weight;
  List<Goal> goals;

  UserProfile({
    required this.name,
    required this.email,
    required this.age,
    required this.height,
    required this.weight,
    required this.goals,
  });
}

class Goal {
  String title;
  String description;
  double overallProgress;
  List<SubMetric> metrics;

  Goal({required this.title, required this.description, required this.overallProgress, required this.metrics});
}

class SubMetric {
  String name;
  double value;
  SubMetric(this.name, this.value);
}

class SavedNotebook {
  final String title;
  final DateTime date;
  final List<Map<String, dynamic>> messages;
  SavedNotebook(this.title, this.date, this.messages);
}


class SomniSystemCore extends InheritedWidget {
  final UserProfile profile;
  final List<SavedNotebook> vault;
  final Function(UserProfile) updateProfile;
  final Function(SavedNotebook) saveToVault;

  const SomniSystemCore({
    super.key,
    required this.profile,
    required this.vault,
    required this.updateProfile,
    required this.saveToVault,
    required super.child,
  });

  static SomniSystemCore? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SomniSystemCore>();
  }

  @override
  bool updateShouldNotify(SomniSystemCore oldWidget) {
    return profile != oldWidget.profile || vault != oldWidget.vault;
  }
}




class SomniApp extends StatefulWidget {
  const SomniApp({super.key});

  @override
  State<SomniApp> createState() => _SomniAppState();
}

class _SomniAppState extends State<SomniApp> {
  // App phases: 0 = authentication, 1 = mandatory SOMNI link,
  // 2 = onboarding, 3 = dashboard.
  int _appPhase = 0;
  // Only a successful sign-in from this app launch can unlock the device gate.
  // Firebase's restored/cached user alone is never sufficient.
  bool _explicitlyAuthenticatedThisRun = false;
  String _capturedEmail = '';
  UserProfile? _masterProfile;
  final List<SavedNotebook> _masterVault = [];
  StreamSubscription<User?>? _authSubscription;
  final SomniBluetoothService _bluetooth = SomniBluetoothService();

  @override
  void initState() {
    super.initState();
    _bluetooth.addListener(_handleBluetoothState);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;

      // Never navigate forward merely because Firebase restored a saved user.
      // The login form must first complete signInWithEmailAndPassword during
      // this launch, and the account's mailbox must be verified.
      if (user == null || !user.emailVerified) {
        _explicitlyAuthenticatedThisRun = false;
        if (_appPhase != 0) {
          setState(() {
            _capturedEmail = '';
            _masterProfile = null;
            _appPhase = 0;
          });
        }
        return;
      }

      if (_explicitlyAuthenticatedThisRun && _appPhase == 0) {
        setState(() {
          _capturedEmail = user.email ?? '';
          _appPhase = 1;
        });
      }
    });
  }

  void _handleBluetoothState() {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (!_explicitlyAuthenticatedThisRun || user == null || !user.emailVerified) {
      if (_appPhase != 0) setState(() => _appPhase = 0);
      return;
    }

    // Never leave onboarding or the dashboard accessible without a live,
    // connected SOMNI GATT notification characteristic.
    if (_appPhase >= 2 && !_bluetooth.isReady) {
      setState(() => _appPhase = 1);
    } else if (_appPhase == 1 && _bluetooth.isReady) {
      setState(() => _appPhase = _masterProfile == null ? 2 : 3);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _bluetooth.removeListener(_handleBluetoothState);
    _bluetooth.dispose();
    super.dispose();
  }

  void _proceedToOnboarding(String email) {
    // Defense-in-depth: this callback may only be reached after Firebase
    // accepted the actual credentials and the user record was reloaded.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified ||
        (user.email ?? '').toLowerCase() != email.toLowerCase()) {
      FirebaseAuth.instance.signOut();
      return;
    }

    _explicitlyAuthenticatedThisRun = true;
    // Authentication only grants access to the mandatory device-link screen.
    setState(() {
      _capturedEmail = email;
      _appPhase = 1;
    });
  }

  void _finalizeSystemBoot(UserProfile profile) {
    final user = FirebaseAuth.instance.currentUser;
    if (!_explicitlyAuthenticatedThisRun || user == null || !user.emailVerified) {
      setState(() => _appPhase = 0);
      return;
    }
    if (!_bluetooth.isReady) {
      setState(() => _appPhase = 1);
      return;
    }
    setState(() {
      _masterProfile = profile;
      _appPhase = 3;
    });
  }

  void _updateProfile(UserProfile newProfile) {
    setState(() => _masterProfile = newProfile);
  }

  void _saveToVault(SavedNotebook notebook) {
    setState(() => _masterVault.insert(0, notebook));
  }

  Future<void> _terminateSession() async {
    try {
      await _bluetooth.stopScan();
      await _bluetooth.disconnect();
      await FirebaseAuth.instance.signOut();
      _explicitlyAuthenticatedThisRun = false;
      if (!mounted) return;
      setState(() {
        _appPhase = 0;
        _capturedEmail = '';
        _masterProfile = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget currentInterface;

    if (_appPhase == 0) {
      currentInterface = AuthScreen(onAuthenticate: _proceedToOnboarding);
    } else if (_appPhase == 1) {
      currentInterface = BluetoothConnectGate(
        key: const ValueKey('MandatoryBluetoothGate'),
        bluetooth: _bluetooth,
        onLogout: _terminateSession,
      );
    } else if (_appPhase == 2) {
      currentInterface = OnboardingScreen(
        email: _capturedEmail,
        onCompile: _finalizeSystemBoot,
      );
    } else {
      currentInterface = SomniSystemCore(
        profile: _masterProfile!,
        vault: _masterVault,
        updateProfile: _updateProfile,
        saveToVault: _saveToVault,
        child: MainNavigationTerminal(
          onLogout: _terminateSession,
          bluetooth: _bluetooth,
        ),
      );
    }

    return MaterialApp(
      title: 'Somni Quantum',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F3EF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFB59451),
          secondary: Color(0xFF1E2124),
          surface: Colors.white,
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1000),
        switchInCurve: Curves.easeOutExpo,
        switchOutCurve: Curves.easeInExpo,
        child: currentInterface,
      ),
    );
  }
}




class AuthScreen extends StatefulWidget {
  final Function(String) onAuthenticate;
  const AuthScreen({super.key, required this.onAuthenticate});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  bool _isCreatingAccount = false;
  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF1E2124),
        ),
      );
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email. Sign in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'verification-email-failed':
        return 'The account was created, but Firebase could not send the verification email. Try signing in to resend it.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase yet.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  bool _hasStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  Future<void> _triggerAuth() async {
    final email = _emailController.text.trim();
    final password = _passController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter both your email and password.');
      return;
    }
    if (email.length > 254 ||
        !RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$")
            .hasMatch(email)) {
      _showMessage('Enter a valid email address, such as name@example.com.');
      return;
    }
    if (_isCreatingAccount && !_hasStrongPassword(password)) {
      _showMessage(
        'Use at least 8 characters, including an uppercase letter, a lowercase letter, and a number.',
      );
      return;
    }
    if (!_isCreatingAccount && password.length < 6) {
      _showMessage('Enter the password for your Firebase account.');
      return;
    }
    if (_isCreatingAccount && password != _confirmPassController.text) {
      _showMessage('The passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isCreatingAccount) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final newUser = credential.user;
        if (newUser == null) {
          throw FirebaseAuthException(
            code: 'verification-email-failed',
            message: 'Firebase did not return the newly created user.',
          );
        }

        // Verify control of the mailbox before allowing access to SOMNI.
        try {
          await newUser.sendEmailVerification();
        } catch (_) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(code: 'verification-email-failed');
        }
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _isCreatingAccount = false;
          _passController.clear();
          _confirmPassController.clear();
        });
        _showMessage(
          'Account created. Open the verification link sent to $email, then sign in here.',
        );
        return;
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.reload();
      final signedInUser = FirebaseAuth.instance.currentUser;

      if (signedInUser == null) {
        _showMessage('Firebase could not confirm this sign-in. Please try again.');
        return;
      }

      if (!signedInUser.emailVerified) {
        var verificationSent = false;
        try {
          await signedInUser.sendEmailVerification();
          verificationSent = true;
        } catch (_) {
          // The account remains blocked; the error below tells the user to retry.
        }
        await FirebaseAuth.instance.signOut();
        _showMessage(
          verificationSent
              ? 'This email is not verified yet. We sent a new verification link. Verify it, then sign in again.'
              : 'This email is not verified yet. We could not resend the link; check your connection and try again.',
        );
        return;
      }

      if (!mounted) return;
      widget.onAuthenticate(signedInUser.email ?? email);
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error));
    } catch (_) {
      _showMessage('Could not connect to Firebase Authentication. Check your internet connection and Firebase setup.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.length > 254 ||
        !RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$")
            .hasMatch(email)) {
      _showMessage('Enter a valid email address before requesting a reset.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('If a SOMNI account exists for this email, Firebase has sent a password-reset link. Check your inbox and spam folder.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error));
    } catch (_) {
      _showMessage('Could not send the reset email. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = _isCreatingAccount;
    return Scaffold(
      key: const ValueKey('AuthScreen'),
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) => CustomPaint(
              painter: QuantumAuthPainter(
                animationValue: _bgController.value,
              ),
              size: Size.infinite,
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: math.min(
                      MediaQuery.of(context).size.width * 0.88,
                      470,
                    ).toDouble(),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFB59451).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'S O M N I',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 38,
                            color: Colors.white,
                            letterSpacing: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'QUANTUM HEALTH SYSTEM',
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            letterSpacing: 4,
                            color: const Color(0xFFB59451),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          creating ? 'CREATE YOUR ACCOUNT' : 'WELCOME BACK',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            letterSpacing: 3,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildField(
                          _emailController,
                          'Email address',
                          Icons.alternate_email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          _passController,
                          'Password',
                          Icons.lock_outline,
                          obscure: !_showPassword,
                        ),
                        if (creating) ...[
                          const SizedBox(height: 14),
                          _buildField(
                            _confirmPassController,
                            'Confirm password',
                            Icons.lock_reset,
                            obscure: !_showPassword,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _showPassword,
                              activeColor: const Color(0xFFB59451),
                              onChanged: _isLoading
                                  ? null
                                  : (value) => setState(
                                        () => _showPassword = value ?? false,
                                      ),
                            ),
                            Text(
                              'Show password',
                              style: GoogleFonts.lato(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            if (!creating)
                              TextButton(
                                onPressed: _isLoading ? null : _resetPassword,
                                child: Text(
                                  'Forgot password?',
                                  style: GoogleFonts.lato(
                                    color: const Color(0xFFB59451),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB59451),
                              disabledBackgroundColor:
                                  const Color(0xFF806B42),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isLoading ? null : _triggerAuth,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : Text(
                                    creating
                                        ? 'CREATE ACCOUNT'
                                        : 'SIGN IN',
                                    style: GoogleFonts.lato(
                                      fontSize: 12,
                                      letterSpacing: 3,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              creating
                                  ? 'Already have an account? '
                                  : 'New to SOMNI? ',
                              style: GoogleFonts.lato(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(() {
                                        _isCreatingAccount =
                                            !_isCreatingAccount;
                                        _passController.clear();
                                        _confirmPassController.clear();
                                      }),
                              child: Text(
                                creating ? 'Sign in' : 'Create account',
                                style: GoogleFonts.lato(
                                  color: const Color(0xFFB59451),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Firebase verifies your password and email before granting access.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      style: GoogleFonts.lato(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          color: const Color(0xFFB59451),
          size: 20,
        ),
        hintText: hint,
        hintStyle: GoogleFonts.lato(color: Colors.grey.shade500),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}


class BluetoothConnectGate extends StatefulWidget {
  final SomniBluetoothService bluetooth;
  final Future<void> Function() onLogout;

  const BluetoothConnectGate({
    super.key,
    required this.bluetooth,
    required this.onLogout,
  });

  @override
  State<BluetoothConnectGate> createState() => _BluetoothConnectGateState();
}

class _BluetoothConnectGateState extends State<BluetoothConnectGate> {
  bool _isSupportedHealthDevice(ScanResult result) =>
      SomniBluetoothService.isSupportedHealthScanResult(result);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('BluetoothConnectGate'),
      backgroundColor: const Color(0xFFF4F3EF),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: AnimatedBuilder(
                animation: widget.bluetooth,
                builder: (context, _) {
                  final bluetooth = widget.bluetooth;
                  final supportedResults = bluetooth.scanResults
                      .where(_isSupportedHealthDevice)
                      .toList(growable: false);
                  final connected = bluetooth.isReady;
                  final connectedButNotReady =
                      bluetooth.connectionState == BluetoothConnectionState.connected &&
                      !bluetooth.isReady;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'S O M N I',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                              color: const Color(0xFF1E2124),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () { widget.onLogout(); },
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('LOG OUT'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6C6C6C),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E2124),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB59451).withValues(alpha: 0.20),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                          color: const Color(0xFFB59451),
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        'DEVICE CONNECTION REQUIRED',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          fontSize: 11,
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFB59451),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        connected ? 'Health device connected' : 'Connect a health device',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E2124),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Connect SOMNI or a compatible health-monitoring device. Unrelated Bluetooth devices are not accepted. There is no demo mode or skip option.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          fontSize: 14,
                          height: 1.6,
                          color: const Color(0xFF777777),
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (connected)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFB59451)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF388E3C)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Connected to ${bluetooth.connectedDeviceName ?? 'SOMNI'}. Opening the app…',
                                  style: GoogleFonts.lato(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: bluetooth.isScanning ? null : bluetooth.startScan,
                            icon: Icon(
                              bluetooth.isScanning ? Icons.radar : Icons.bluetooth_searching,
                            ),
                            label: Text(
                              bluetooth.isScanning ? 'SEARCHING FOR HEALTH DEVICES…' : 'SCAN FOR HEALTH DEVICES',
                              style: GoogleFonts.lato(
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2124),
                              foregroundColor: const Color(0xFFB59451),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        if (bluetooth.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            bluetooth.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                        if (connectedButNotReady) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'The device connected but exposed no supported readable or live sensor characteristic. It cannot be used by SOMNI yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red, fontSize: 12, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          'AVAILABLE HEALTH DEVICES',
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF8A8A8A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: supportedResults.isEmpty
                              ? Center(
                                  child: Text(
                                    bluetooth.isScanning
                                        ? 'Scanning nearby Bluetooth devices…'
                                        : bluetooth.scanResults.isEmpty
                                            ? 'Tap Scan to find SOMNI or a compatible health device nearby.'
                                            : 'No compatible health device was found. Make sure its Bluetooth health service is enabled and nearby.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.lato(
                                      color: const Color(0xFF8A8A8A),
                                      height: 1.5,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: supportedResults.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final result = supportedResults[index];
                                    final device = result.device;
                                    final name = device.platformName.isNotEmpty
                                        ? device.platformName
                                        : result.advertisementData.advName;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE5E1D8)),
                                      ),
                                      child: ListTile(
                                        leading: const Icon(Icons.watch, color: Color(0xFFB59451)),
                                        title: Text(
                                          name.isEmpty ? 'SOMNI wearable' : name,
                                          style: GoogleFonts.lato(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          'Signal strength: ${result.rssi} dBm',
                                          style: GoogleFonts.lato(fontSize: 11),
                                        ),
                                        trailing: TextButton(
                                          onPressed: () => bluetooth.connect(
                                            device,
                                            advertisedName: result.advertisementData.advName,
                                          ),
                                          child: const Text('CONNECT'),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        kIsWeb
                            ? 'On Chrome, allow Bluetooth access when prompted. Use localhost or HTTPS for Web Bluetooth.'
                            : 'Keep your health device powered on and nearby. Bluetooth permission must be allowed.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(fontSize: 10, color: const Color(0xFF9A9A9A)),
                      ),
                      const Spacer(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class OnboardingScreen extends StatefulWidget {
  final String email;
  final Function(UserProfile) onCompile;
  const OnboardingScreen({super.key, required this.email, required this.onCompile});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  final List<Map<String, dynamic>> _goalsDB = [
    {"title": "Cellular Longevity", "desc": "Telomere preservation and deep cellular repair.", "selected": false},
    {"title": "Cognitive Apex", "desc": "Nootropic baseline shifts for extreme mental clarity.", "selected": false},
    {"title": "Cardio-Metabolic Peak", "desc": "Zone 5 expansion and mitochondrial density.", "selected": false},
    {"title": "Neuroplasticity", "desc": "Accelerated learning pathways and flow state triggers.", "selected": false},
  ];

  void _constructProfile() {
    List<Goal> chosenGoals = _goalsDB.where((g) => g['selected'] == true).map((g) {
      return Goal(
        title: g['title'], description: g['desc'], overallProgress: 0.0,
        metrics: [],
      );
    }).toList();

    if (chosenGoals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one protocol must be selected.', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF1E2124)));
      return;
    }

    widget.onCompile(UserProfile(
      name: _nameCtrl.text.isEmpty ? "Client" : _nameCtrl.text,
      email: widget.email,
      age: _ageCtrl.text, height: _heightCtrl.text, weight: _weightCtrl.text,
      goals: chosenGoals,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('OnboardingScreen'),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Biometric Intake', style: GoogleFonts.playfairDisplay(fontSize: 36, color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
            Text('Calibrate the AI to your physical architecture.', style: GoogleFonts.lato(fontSize: 14, color: const Color(0xFF8A8A8A))),
            const SizedBox(height: 32),
            _buildInput(_nameCtrl, 'Full Formal Name', false),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildInput(_ageCtrl, 'Age', true)),
                const SizedBox(width: 12),
                Expanded(child: _buildInput(_heightCtrl, 'Height (cm)', true)),
                const SizedBox(width: 12),
                Expanded(child: _buildInput(_weightCtrl, 'Weight (kg)', true)),
              ],
            ),
            const SizedBox(height: 48),
            Text('PROTOCOL SELECTION', style: GoogleFonts.lato(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 3, color: const Color(0xFFB59451))),
            const SizedBox(height: 16),
            ..._goalsDB.map((g) => _buildGoalCard(g)),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20)),
                onPressed: _constructProfile,
                child: Text('COMPILE ARCHITECTURE', style: GoogleFonts.lato(letterSpacing: 2, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, bool isNum) {
    return TextField(
      controller: ctrl, keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, labelStyle: GoogleFonts.lato(fontSize: 12, color: const Color(0xFF8A8A8A)),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
    );
  }

  Widget _buildGoalCard(Map<String, dynamic> goal) {
    return GestureDetector(
      onTap: () => setState(() => goal['selected'] = !goal['selected']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: goal['selected'] ? const Color(0xFF1E2124) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: goal['selected'] ? const Color(0xFF1E2124) : Colors.grey.shade300),
          boxShadow: goal['selected'] ? [BoxShadow(color: const Color(0xFFB59451).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))] : [],
        ),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: goal['selected'] ? const Color(0xFFB59451) : Colors.grey.shade400, width: 2)),
              child: goal['selected'] ? const Center(child: CircleAvatar(radius: 6, backgroundColor: Color(0xFFB59451))) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal['title'], style: GoogleFonts.playfairDisplay(fontSize: 18, color: goal['selected'] ? Colors.white : const Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(goal['desc'], style: GoogleFonts.lato(fontSize: 12, color: goal['selected'] ? Colors.grey.shade400 : const Color(0xFF8A8A8A))),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}







class SomniBluetoothService extends ChangeNotifier {
  final List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  bool isScanning = false;
  bool _hasNotifyCharacteristic = false;
  bool _isSomniHardware = false;
  bool _isSupportedHealthPeripheral = false;

  static const Set<String> _healthServiceShortUuids = {
    '1808', // Glucose
    '1809', // Health Thermometer
    '180d', // Heart Rate
    '1810', // Blood Pressure
    '1814', // Running Speed and Cadence
    '1816', // Cycling Speed and Cadence
    '181b', // Body Composition
    '181d', // Weight Scale
    '1822', // Pulse Oximeter
    '1826', // Fitness Machine
  };

  static String _normalizedUuid(Object uuid) =>
      uuid.toString().toLowerCase().replaceAll('-', '');

  static bool _hasHealthService(Iterable<Guid> uuids) => uuids.any((uuid) {
        final normalized = _normalizedUuid(uuid);
        return _healthServiceShortUuids.any(normalized.contains);
      });

  static bool _looksLikeHealthDeviceName(String name) {
    final n = name.toLowerCase();
    return n.contains('somni') ||
        n.contains('fitbit') || n.contains('garmin') ||
        n.contains('huawei') || n.contains('honor') ||
        n.contains('amazfit') || n.contains('mi band') ||
        n.contains('xiaomi') || n.contains('whoop') ||
        n.contains('polar') || n.contains('oura') ||
        n.contains('samsung') || n.contains('galaxy watch') ||
        n.contains('smart ring') || n.contains('ringconn') ||
        n.contains('ultrahuman') ||
        n.contains('fitness') || n.contains('heart rate') ||
        n.contains('health') || n.contains('smart band') ||
        n.contains('smartwatch');
  }

  static bool isSupportedHealthScanResult(ScanResult result) {
    final platformName = result.device.platformName.trim();
    final advertisedName = result.advertisementData.advName.trim();
    final name = platformName.isNotEmpty ? platformName : advertisedName;
    final advertisedHealthService = _hasHealthService(
      result.advertisementData.serviceUuids,
    );
    // Names are only a scan hint. A third-party device is accepted only after
    // its discovered GATT services prove that it exposes a standard health service.
    return name.toUpperCase().contains('SOMNI') ||
        advertisedHealthService || _looksLikeHealthDeviceName(name);
  }

  bool get isSomniHardware => _isSomniHardware;
  bool get isSupportedHealthPeripheral => _isSupportedHealthPeripheral;

  bool get isReady =>
      connectionState == BluetoothConnectionState.connected &&
      connectedDevice != null &&
      _hasNotifyCharacteristic;
  String latestData = 'No sensor data received yet.';
  String statusMessage = 'Bluetooth is ready.';
  String? errorMessage;
  String? connectedDeviceName;
  final Map<String, double> sensorMetrics = {};
  Timer? _sensorDataStaleTimer;

  bool get hasSensorData => sensorMetrics.isNotEmpty;

  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;
  BluetoothCharacteristic? _activeNotifyCharacteristic;

  void _clearSensorData() {
    _sensorDataStaleTimer?.cancel();
    _sensorDataStaleTimer = null;
    sensorMetrics.clear();
  }

  void _processStandardHeartRate(List<int> bytes) {
    if (bytes.length < 2) return;
    final flags = bytes[0];
    final is16Bit = (flags & 0x01) != 0;
    final bpm = is16Bit && bytes.length >= 3
        ? bytes[1] | (bytes[2] << 8)
        : bytes[1];
    if (bpm < 25 || bpm > 240) return;
    sensorMetrics['hr'] = bpm.toDouble();
    latestData = 'Heart rate: $bpm bpm (Bluetooth SIG Heart Rate Measurement)';
    statusMessage = 'Receiving heart-rate data from $connectedDeviceName.';
    _sensorDataStaleTimer?.cancel();
    _sensorDataStaleTimer = Timer(const Duration(seconds: 20), () {
      sensorMetrics.clear();
      statusMessage = 'Connected, but no recent sensor data is available.';
      notifyListeners();
    });
    notifyListeners();
  }

  void _processSensorPayload(String payload) {
    final Map<String, dynamic> fields = {};

    void collectFields(dynamic value) {
      if (value is Map) {
        value.forEach((key, nestedValue) {
          if (nestedValue is Map) {
            collectFields(nestedValue);
          } else {
            final normalizedKey = key
                .toString()
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '');
            fields[normalizedKey] = nestedValue;
          }
        });
      }
    }

    try {
      collectFields(jsonDecode(payload));
    } catch (_) {
      final pairs = RegExp(
        r'([A-Za-z][A-Za-z0-9_ ]*)\s*[:=]\s*(-?\d+(?:\.\d+)?)',
      ).allMatches(payload);
      for (final pair in pairs) {
        final key = pair.group(1)!
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        fields[key] = pair.group(2);
      }
    }

    double? readNumber(List<String> keys) {
      for (final key in keys) {
        final value = fields[key];
        if (value is num) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final incoming = <String, double>{};
    final heartRate = readNumber([
      'heartrate', 'heartratebpm', 'hr', 'hrbpm', 'bpm', 'pulse'
    ]);
    if (heartRate != null && heartRate >= 25 && heartRate <= 240) {
      incoming['hr'] = heartRate;
    }

    final hrv = readNumber([
      'hrv', 'heartratevariability', 'heartratevariabilityms'
    ]);
    if (hrv != null && hrv > 0 && hrv <= 300) {
      incoming['hrv'] = hrv;
    }

    final oxygen = readNumber([
      'spo2', 'spo2percent', 'oxygensaturation', 'bloodoxygen', 'oxygen'
    ]);
    if (oxygen != null && oxygen >= 50 && oxygen <= 100) {
      incoming['spo2'] = oxygen;
    }

    final steps = readNumber(['steps', 'stepcount']);
    if (steps != null && steps >= 0 && steps <= 200000) {
      incoming['steps'] = steps;
    }

    final temperature = readNumber([
      'temperature', 'temperaturec', 'tempc', 'bodytemperature'
    ]);
    if (temperature != null && temperature >= 20 && temperature <= 50) {
      incoming['temperature'] = temperature;
    }

    if (incoming.isEmpty) {
      statusMessage =
          'Connected. Received data, but no supported sensor fields were found.';
      notifyListeners();
      return;
    }

    sensorMetrics.addAll(incoming);
    statusMessage = 'Receiving sensor data from $connectedDeviceName.';
    _sensorDataStaleTimer?.cancel();
    _sensorDataStaleTimer = Timer(const Duration(seconds: 20), () {
      sensorMetrics.clear();
      statusMessage = 'Connected, but no recent sensor data is available.';
      notifyListeners();
    });
    notifyListeners();
  }

  SomniBluetoothService() {
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      scanResults
        ..clear()
        ..addAll(results);
      notifyListeners();
    });
    _scanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      isScanning = scanning;
      notifyListeners();
    });
  }

  Future<bool> _requestAndroidPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;

    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final modernPermissionsGranted =
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;
    final legacyLocationGranted =
        statuses[Permission.location]?.isGranted == true;



    return modernPermissionsGranted || legacyLocationGranted;
  }

  Future<void> startScan() async {
    try {
      errorMessage = null;
      statusMessage = 'Searching for nearby BLE devices...';
      scanResults.clear();
      notifyListeners();

      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        throw Exception('Bluetooth Low Energy is not supported on this phone.');
      }

      final permissionsGranted = await _requestAndroidPermissions();
      if (!permissionsGranted) {
        throw Exception('Bluetooth permission was not granted. Enable Nearby Devices/Bluetooth permission in phone settings.');
      }

      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first;

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );
      isScanning = true;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      statusMessage = 'Scan could not start.';
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {

    }
    isScanning = false;
    notifyListeners();
  }

  Future<void> connect(BluetoothDevice device, {String? advertisedName}) async {
    final deviceName = (device.platformName.trim().isNotEmpty
            ? device.platformName
            : (advertisedName ?? ''))
        .trim();
    final isSomni = deviceName.toUpperCase().contains('SOMNI');
    try {
      _hasNotifyCharacteristic = false;
      _isSomniHardware = isSomni;
      _isSupportedHealthPeripheral = false;
      errorMessage = null;
      statusMessage = 'Connecting to ${device.platformName.isEmpty ? device.remoteId.str : device.platformName}...';
      notifyListeners();

      await stopScan();

      if (connectedDevice != null) {
        await disconnect();
      }

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      connectedDevice = device;
      connectedDeviceName = device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.str;

      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        connectionState = state;
        if (state == BluetoothConnectionState.disconnected) {
          _hasNotifyCharacteristic = false;
          connectedDevice = null;
          connectedDeviceName = null;
          _dataSubscription?.cancel();
          _activeNotifyCharacteristic = null;
          _clearSensorData();
          latestData = 'No sensor data received yet.';
          statusMessage = 'Device disconnected.';
        } else {
          statusMessage = 'Connected to $connectedDeviceName.';
        }
        notifyListeners();
      });

      connectionState = BluetoothConnectionState.connected;
      statusMessage = 'Connected. Discovering sensor services...';
      notifyListeners();

      await _discoverAndListen(device, allowSomniByName: isSomni);
    } catch (e) {
      errorMessage = e.toString();
      statusMessage = 'Connection failed.';
      _hasNotifyCharacteristic = false;
      _isSupportedHealthPeripheral = false;
      _isSomniHardware = false;
      connectionState = BluetoothConnectionState.disconnected;
      connectedDevice = null;
      connectedDeviceName = null;
      _clearSensorData();
      notifyListeners();
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _discoverAndListen(
    BluetoothDevice device, {
    required bool allowSomniByName,
  }) async {
    final services = await device.discoverServices();
    final healthServiceFound = _hasHealthService(
      services.map((service) => service.serviceUuid),
    );
    if (!allowSomniByName && !healthServiceFound) {
      throw Exception(
        'This device does not expose a supported standard BLE health service. Proprietary fitness-band protocols need a manufacturer-specific integration.',
      );
    }

    final candidates = <BluetoothCharacteristic>[];
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final properties = characteristic.properties;
        if (properties.notify || properties.indicate || properties.read) {
          candidates.add(characteristic);
        }
      }
    }
    // Prefer the standard Heart Rate Measurement characteristic when present.
    candidates.sort((a, b) {
      final aHr = _normalizedUuid(a.uuid).contains('2a37') ? 0 : 1;
      final bHr = _normalizedUuid(b.uuid).contains('2a37') ? 0 : 1;
      if (aHr != bHr) return aHr.compareTo(bHr);
      final aLive = (a.properties.notify || a.properties.indicate) ? 0 : 1;
      final bLive = (b.properties.notify || b.properties.indicate) ? 0 : 1;
      return aLive.compareTo(bLive);
    });
    final notifyCharacteristic = candidates.isEmpty ? null : candidates.first;

    if (notifyCharacteristic == null) {
      _hasNotifyCharacteristic = false;
      statusMessage =
          'Connected, but no readable or live health measurement characteristic was found.';
      latestData =
          'The device must expose a readable or Notify/Indicate health measurement characteristic.';
      _clearSensorData();
      notifyListeners();
      return;
    }

    _activeNotifyCharacteristic = notifyCharacteristic;
    await _dataSubscription?.cancel();

    if (notifyCharacteristic.properties.notify ||
        notifyCharacteristic.properties.indicate) {
      await notifyCharacteristic.setNotifyValue(true);
      _dataSubscription = notifyCharacteristic.onValueReceived.listen((bytes) {
        if (bytes.isEmpty) return;
        final characteristicUuid = _normalizedUuid(notifyCharacteristic.uuid);
        if (characteristicUuid.contains('2a37')) {
          _processStandardHeartRate(bytes);
        } else {
          latestData = utf8.decode(bytes, allowMalformed: true).trim();
          _processSensorPayload(latestData);
        }
      });
    } else if (notifyCharacteristic.properties.read) {
      final bytes = await notifyCharacteristic.read();
      if (bytes.isNotEmpty) {
        latestData = utf8.decode(bytes, allowMalformed: true).trim();
        _processSensorPayload(latestData);
      }
    }

    _isSupportedHealthPeripheral = healthServiceFound;
    _hasNotifyCharacteristic = true;
    statusMessage = allowSomniByName
        ? 'Connected to SOMNI. Listening for sensor notifications.'
        : 'Connected to a compatible health device. Standard health services detected.';
    notifyListeners();
  }

  Future<void> disconnect() async {
    _hasNotifyCharacteristic = false;
    _isSomniHardware = false;
    _isSupportedHealthPeripheral = false;
    final device = connectedDevice;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _activeNotifyCharacteristic = null;

    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    connectedDevice = null;
    connectedDeviceName = null;
    connectionState = BluetoothConnectionState.disconnected;
    _clearSensorData();
    statusMessage = 'Device disconnected.';
    latestData = 'No sensor data received yet.';
    notifyListeners();
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _scanningSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _sensorDataStaleTimer?.cancel();
    FlutterBluePlus.stopScan();
    connectedDevice?.disconnect();
    super.dispose();
  }
}


class SomniBluetoothPanel extends StatelessWidget {
  final SomniBluetoothService bluetooth;

  const SomniBluetoothPanel({super.key, required this.bluetooth});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bluetooth,
      builder: (context, _) {
        final connected = bluetooth.isReady;
        final supportedResults = bluetooth.scanResults
            .where(SomniBluetoothService.isSupportedHealthScanResult)
            .toList(growable: false);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth, color: Color(0xFFB59451)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'HEALTH DEVICE LINK',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connected
                        ? 'CONNECTED • ${bluetooth.connectedDeviceName ?? "SOMNI"}'
                        : 'NOT CONNECTED',
                    style: GoogleFonts.lato(
                      color: connected
                          ? const Color(0xFF388E3C)
                          : Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    bluetooth.statusMessage,
                    style: GoogleFonts.lato(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  if (bluetooth.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      bluetooth.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (connected) ...[
                    Text(
                      'LIVE DEVICE DATA',
                      style: GoogleFonts.lato(
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB59451),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F3EF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        bluetooth.latestData,
                        style: GoogleFonts.robotoMono(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: bluetooth.disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('DISCONNECT DEVICE'),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E2124),
                          foregroundColor: const Color(0xFFB59451),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed:
                            bluetooth.isScanning ? null : bluetooth.startScan,
                        icon: Icon(
                          bluetooth.isScanning
                              ? Icons.radar
                              : Icons.bluetooth_searching,
                        ),
                        label: Text(
                          bluetooth.isScanning
                              ? 'SCANNING...'
                              : 'SCAN FOR HEALTH DEVICES',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: supportedResults.isEmpty
                          ? Center(
                              child: Text(
                                bluetooth.isScanning
                                    ? 'Searching for nearby BLE devices...'
                                    : 'No compatible health devices found yet. Tap scan to search.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.lato(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: supportedResults.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final result = supportedResults[index];
                                final device = result.device;
                                final name = device.platformName.isNotEmpty
                                    ? device.platformName
                                    : result.advertisementData.advName;

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.watch,
                                    color: Color(0xFFB59451),
                                  ),
                                  title: Text(
                                    name,
                                    style: GoogleFonts.lato(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${device.remoteId.str} • RSSI ${result.rssi} dBm',
                                    style: GoogleFonts.lato(fontSize: 10),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () => bluetooth.connect(
                                      device,
                                      advertisedName: result.advertisementData.advName,
                                    ),
                                    child: const Text('CONNECT'),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Keep the device nearby and make sure its Bluetooth advertising is enabled.',
                    style: GoogleFonts.lato(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}




class MainNavigationTerminal extends StatefulWidget {
  final VoidCallback onLogout;
  final SomniBluetoothService bluetooth;
  const MainNavigationTerminal({
    super.key,
    required this.onLogout,
    required this.bluetooth,
  });

  @override
  State<MainNavigationTerminal> createState() => _MainNavigationTerminalState();
}

class _MainNavigationTerminalState extends State<MainNavigationTerminal> {
  int _currentIndex = 0;
  late final SomniBluetoothService _bluetooth = widget.bluetooth;

  void _openBluetoothPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SomniBluetoothPanel(bluetooth: _bluetooth),
    );
  }

  List<Widget> get _screens => [
    AIConciergeScreen(
      bluetooth: _bluetooth,
      onConnectPressed: _openBluetoothPanel,
    ),
    const DeepGoalTrackerScreen(),
    const ClinicalArchivesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('MainTerminal'),
      drawer: EliteDrawer(onLogout: widget.onLogout),
      appBar: AppBar(
        title: Text('S O M N I', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, letterSpacing: 8, fontSize: 16)),
        centerTitle: true, backgroundColor: Colors.white, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          AnimatedBuilder(
            animation: _bluetooth,
            builder: (context, _) {
              final connected = _bluetooth.isReady;
              return IconButton(
                tooltip: connected ? 'Health device connected' : 'Connect health device',
                onPressed: _openBluetoothPanel,
                icon: Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: connected
                      ? const Color(0xFFB59451)
                      : const Color(0xFF1E2124),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navIcon(0, Icons.blur_on, "AI Core"),
              _navIcon(1, Icons.radar, "Trajectories"),
              _navIcon(2, Icons.calendar_month, "Archives"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(int index, IconData icon, String label) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E2124) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFFB59451) : const Color(0xFF8A8A8A), size: 20),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.lato(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ]
          ],
        ),
      ),
    );
  }
}




class EliteDrawer extends StatelessWidget {
  final VoidCallback onLogout;
  const EliteDrawer({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {

    final core = SomniSystemCore.of(context)!;
    
    return Drawer(
      backgroundColor: const Color(0xFFF4F3EF),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 60, left: 24, bottom: 24, right: 24),
            color: Colors.white,
            child: Row(
              children: [
                CircleAvatar(backgroundColor: const Color(0xFF1A1A1A), radius: 24, child: Text(core.profile.name[0], style: const TextStyle(color: Colors.white, fontSize: 20))),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(core.profile.name, style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(core.profile.email, style: GoogleFonts.lato(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('Tier I System Admin', style: GoogleFonts.lato(fontSize: 10, color: const Color(0xFFB59451), letterSpacing: 1)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          _drawerItem(context, Icons.manage_accounts, 'Identity & Biometrics', () {
            Navigator.pop(context);

            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditorScreen(
              profile: core.profile,
              onUpdateProfile: core.updateProfile,
            )));
          }),
          _drawerItem(context, Icons.folder_special, 'Cognitive Vault (Chats)', () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => CognitiveVaultScreen(
              vault: core.vault,
            )));
          }),
          const Spacer(),
          const Divider(),
          _drawerItem(context, Icons.power_settings_new, 'Terminate Session', onLogout),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1A1A1A)),
      title: Text(title, style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1A1A1A))),
      onTap: onTap,
    );
  }
}




class AIConciergeScreen extends StatefulWidget {
  final SomniBluetoothService bluetooth;
  final VoidCallback onConnectPressed;

  const AIConciergeScreen({
    super.key,
    required this.bluetooth,
    required this.onConnectPressed,
  });

  @override
  State<AIConciergeScreen> createState() => _AIConciergeScreenState();
}

class _AIConciergeScreenState extends State<AIConciergeScreen> with SingleTickerProviderStateMixin {
  final String _apiKey = 'As a user here ıs where you need to ınsert your own GEMINI API thats free and only needs a sımple copy paste, enjoy SOMNI :)';
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  late GenerativeModel _model;
  late ChatSession _chat;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      _initAI();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _initAI() {
    final profile = SomniSystemCore.of(context)!.profile;
    String goalStr = profile.goals.map((g) => g.title).join(", ");
    _model = GenerativeModel(
      model: 'gemini-3.5-flash', apiKey: _apiKey,
      systemInstruction: Content.text(
        'You are Somni, an ultra-advanced quantum health AI. Tone: Elegant, hyper-intelligent, clinical, "old money" aesthetic but futuristic. '
        'Client: ${profile.name}, Age: ${profile.age}, Height: ${profile.height}cm, Weight: ${profile.weight}kg. '
        'Core Objectives: $goalStr. '
        'Limit responses to 3 succinct, powerful sentences. Ground advice in cutting-edge biology.'
      ),
    );
    _chat = _model.startChat();
    _messages.add({'isUser': false, 'text': 'Neural handshake complete. Systems synchronized to objectives: $goalStr. How shall we optimize your biological architecture today, ${profile.name}?'});
  }

  void _saveCurrentChat() {
    if (_messages.length <= 1) return;
    String title = "Session Log - ${DateTime.now().hour}:${DateTime.now().minute}";
    final notebook = SavedNotebook(title, DateTime.now(), List.from(_messages));
    SomniSystemCore.of(context)!.saveToVault(notebook);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chat archived to Cognitive Vault.', style: GoogleFonts.lato()), backgroundColor: const Color(0xFF1E2124)));
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() { _messages.add({'isUser': true, 'text': text}); _isTyping = true; });
    _ctrl.clear(); _scrollDown();
    try {
      final res = await _chat.sendMessage(Content.text(text));
      setState(() { _messages.add({'isUser': false, 'text': res.text ?? "Error."}); _isTyping = false; });
    } catch (e) {
      setState(() { _messages.add({'isUser': false, 'text': 'Uplink severed: $e'}); _isTyping = false; });
    }
    _scrollDown();
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 100), () => _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _build3DTelemetryHeader(),
        Expanded(
          child: ListView.builder(
            controller: _scroll, padding: const EdgeInsets.all(24),
            itemCount: _messages.length,
            itemBuilder: (context, i) => _buildMessage(_messages[i]),
          ),
        ),
        if (_isTyping) const Padding(padding: EdgeInsets.only(left: 24, bottom: 8), child: Align(alignment: Alignment.centerLeft, child: Text('Synthesizing...', style: TextStyle(color: Color(0xFFB59451), fontStyle: FontStyle.italic)))),
        _buildInputBar(),
      ],
    );
  }

  Widget _build3DTelemetryHeader() {
    return AnimatedBuilder(
      animation: widget.bluetooth,
      builder: (context, _) {
        final connected = widget.bluetooth.connectionState ==
            BluetoothConnectionState.connected;
        final hasData = connected && widget.bluetooth.hasSensorData;

        String metricValue(String key) {
          final value = widget.bluetooth.sensorMetrics[key];
          if (value == null) return '--';
          return value == value.roundToDouble()
              ? value.toInt().toString()
              : value.toStringAsFixed(1);
        }

        return Container(
          height: 180,
          width: double.infinity,
          color: const Color(0xFF0F0F0F),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (ctx, child) => CustomPaint(
                  painter: NeuralCorePainter(animationValue: _pulseCtrl.value),
                  size: Size.infinite,
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.bookmark_add, color: Color(0xFFB59451)),
                  tooltip: 'Save Chat to Vault',
                  onPressed: _saveCurrentChat,
                ),
              ),
              Positioned(
                bottom: 18,
                left: 24,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !connected
                          ? 'NO SOMNI DEVICE CONNECTED'
                          : hasData
                              ? 'LIVE CORE TELEMETRY'
                              : 'DEVICE CONNECTED • WAITING FOR DATA',
                      style: GoogleFonts.lato(
                        color: Colors.grey.shade400,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!connected)
                      OutlinedButton.icon(
                        onPressed: widget.onConnectPressed,
                        icon: const Icon(Icons.bluetooth, size: 16),
                        label: const Text('CONNECT SOMNI DEVICE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB59451),
                          side: const BorderSide(color: Color(0xFFB59451)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          textStyle: GoogleFonts.lato(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          _miniMetric('HR', metricValue('hr'), 'bpm'),
                          const SizedBox(width: 16),
                          _miniMetric('HRV', metricValue('hrv'), 'ms'),
                          const SizedBox(width: 16),
                          _miniMetric('O2', metricValue('spo2'), '%'),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniMetric(String label, String val, String unit) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$label ', style: GoogleFonts.lato(color: const Color(0xFFB59451), fontSize: 10, fontWeight: FontWeight.bold)),
        Text(val, style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(unit, style: GoogleFonts.lato(color: Colors.grey.shade500, fontSize: 10)),
      ],
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    bool isU = msg['isUser'];
    return Align(
      alignment: isU ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isU ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Text(msg['text'], style: GoogleFonts.lato(color: isU ? Colors.white : Colors.black87, fontSize: 14, height: 1.5)),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(16), color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl, onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Transmit query...', filled: true, fillColor: const Color(0xFFF4F3EF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            backgroundColor: const Color(0xFF1E2124), elevation: 0,
            onPressed: () => _send(_ctrl.text), child: const Icon(Icons.graphic_eq, color: Color(0xFFB59451)),
          )
        ],
      ),
    );
  }
}




class DeepGoalTrackerScreen extends StatelessWidget {
  const DeepGoalTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = SomniSystemCore.of(context)!.profile.goals;
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: goals.length,
      itemBuilder: (ctx, i) {
        final goal = goals[i];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GoalDeepDiveScreen(goal: goal, index: i))),
          child: Hero(
            tag: 'goal_${goal.title}',
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)]),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(goal.title, style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
                        Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400)
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(goal.description, style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    Text(
                      'NO DEVICE-DERIVED PROGRESS RECORDED',
                      style: GoogleFonts.lato(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GoalDeepDiveScreen extends StatelessWidget {
  final Goal goal;
  final int index;
  const GoalDeepDiveScreen({super.key, required this.goal, required this.index});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2124), 
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: Hero(
        tag: 'goal_${goal.title}',
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PROTOCOL:', style: GoogleFonts.lato(color: const Color(0xFFB59451), fontSize: 12, letterSpacing: 3)),
                Text(goal.title, style: GoogleFonts.playfairDisplay(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.sensors_off,
                        color: Color(0xFFB59451),
                        size: 36,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'NO MEASURED DATA YET',
                        style: GoogleFonts.lato(
                          color: const Color(0xFFB59451),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect SOMNI and collect sensor readings to see measured progress here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubMetricBar(String label, double val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.lato(color: Colors.white, fontSize: 12)),
              Text('${(val*100).toInt()}%', style: GoogleFonts.lato(color: const Color(0xFFB59451), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: val, backgroundColor: Colors.white10, color: const Color(0xFFB59451)),
        ],
      ),
    );
  }
}




class ClinicalArchivesScreen extends StatelessWidget {
  const ClinicalArchivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temporal Matrix',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Historical biometrics & intervention logs.',
            style: GoogleFonts.lato(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 44,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'NO HISTORICAL DATA',
                  style: GoogleFonts.lato(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: const Color(0xFFB59451),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recorded sensor history will appear here once data logging is enabled.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}


class CognitiveVaultScreen extends StatelessWidget {
  final List<SavedNotebook> vault;
  const CognitiveVaultScreen({super.key, required this.vault});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('COGNITIVE VAULT', style: GoogleFonts.lato(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, elevation: 0),
      body: vault.isEmpty 
        ? Center(child: Text('Vault is empty. Save chats from the AI core.', style: GoogleFonts.lato(color: Colors.grey)))
        : ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: vault.length,
            itemBuilder: (ctx, i) {
              final note = vault[i];
              return Card(
                color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.menu_book, color: Color(0xFFB59451)),
                  title: Text(note.title, style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
                  subtitle: Text('${note.date.day}/${note.date.month}/${note.date.year} • ${note.messages.length} exchanges', style: GoogleFonts.lato(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward, size: 16),
                ),
              );
            },
          ),
    );
  }
}




class ProfileEditorScreen extends StatefulWidget {
  final UserProfile profile;
  final Function(UserProfile) onUpdateProfile;

  const ProfileEditorScreen({super.key, required this.profile, required this.onUpdateProfile});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late TextEditingController hCtrl, wCtrl, nCtrl;

  @override
  void initState() {
    super.initState();
    hCtrl = TextEditingController(text: widget.profile.height);
    wCtrl = TextEditingController(text: widget.profile.weight);
    nCtrl = TextEditingController(text: widget.profile.name);
  }

  void _save() {
    final updated = UserProfile(
      name: nCtrl.text, email: widget.profile.email, age: widget.profile.age, 
      height: hCtrl.text, weight: wCtrl.text, goals: widget.profile.goals,
    );
    widget.onUpdateProfile(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BIOMETRIC OVERRIDE', style: TextStyle(fontSize: 12, letterSpacing: 2)), backgroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            TextField(controller: nCtrl, decoration: const InputDecoration(labelText: 'Alias / Name')),
            const SizedBox(height: 16),
            TextField(controller: hCtrl, decoration: const InputDecoration(labelText: 'Height (cm)')),
            const SizedBox(height: 16),
            TextField(controller: wCtrl, decoration: const InputDecoration(labelText: 'Weight (kg)')),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2124), minimumSize: const Size.fromHeight(50)),
              onPressed: _save, child: const Text('UPDATE ARCHITECTURE', style: TextStyle(color: Colors.white, letterSpacing: 2)),
            )
          ],
        ),
      ),
    );
  }
}






class QuantumAuthPainter extends CustomPainter {
  final double animationValue;
  QuantumAuthPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0xFFB59451).withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    
    double t = animationValue * 2 * math.pi;
    double radius = size.width * 0.45;
    int points = 30;

    _drawSphere(canvas, center, radius, points, paint, t, t * 1.5, 0);
    _drawSphere(canvas, center, radius * 0.75, points ~/ 1.5, paint..color = const Color(0xFFB59451).withValues(alpha: 0.4), -t, 0, t * 2);
    _drawSphere(canvas, center, radius * 0.5, points ~/ 2, paint..color = Colors.white.withValues(alpha: 0.1), 0, -t * 2, -t);
  }

  void _drawSphere(Canvas canvas, Offset center, double radius, int points, Paint paint, double angleX, double angleY, double angleZ) {
    for (int i = 0; i < points; i++) {
      double lat = math.pi * (-0.5 + (i / (points - 1)));
      for (int j = 0; j < points; j++) {
        double lon = 2 * math.pi * (j / (points - 1));
        

        double x = radius * math.cos(lat) * math.cos(lon);
        double y = radius * math.cos(lat) * math.sin(lon);
        double z = radius * math.sin(lat);


        double y1 = y * math.cos(angleX) - z * math.sin(angleX);
        double z1 = y * math.sin(angleX) + z * math.cos(angleX);
        

        double x2 = x * math.cos(angleY) + z1 * math.sin(angleY);
        double z2 = -x * math.sin(angleY) + z1 * math.cos(angleY);
        

        double x3 = x2 * math.cos(angleZ) - y1 * math.sin(angleZ);
        double y3 = x2 * math.sin(angleZ) + y1 * math.cos(angleZ);

        canvas.drawCircle(Offset(center.dx + x3, center.dy + y3), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


class NeuralCorePainter extends CustomPainter {
  final double animationValue;
  NeuralCorePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0xFFB59451).withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    
    double t = animationValue * 2 * math.pi;
    int strands = 2;
    int nodes = 40;
    double radiusX = size.width * 0.3;
    double radiusY = size.height * 0.3;

    for (int s = 0; s < strands; s++) {
      Path path = Path();
      double offsetStrand = s * math.pi;
      
      for (int i = 0; i <= nodes; i++) {
        double progress = i / nodes;
        double angle = progress * math.pi * 4 + t + offsetStrand;
        

        double x = center.dx + math.sin(angle) * radiusX * (1 - progress.abs());
        double y = center.dy + (progress - 0.5) * radiusY * 2;
        
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = const Color(0xFFB59451).withValues(alpha: 0.8));
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
