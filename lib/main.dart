
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:math' as math;

void main() {
  runApp(const SomniApp());
}

/// ------------------------------------------------------------------
/// DATA MODELS & CORE REPOSITORY
/// ------------------------------------------------------------------
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

/// Core State Manager
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

/// ------------------------------------------------------------------
/// APP CONFIGURATION & DECLARATIVE ROUTING WRAPPER
/// ------------------------------------------------------------------
class SomniApp extends StatefulWidget {
  const SomniApp({super.key});

  @override
  State<SomniApp> createState() => _SomniAppState();
}

class _SomniAppState extends State<SomniApp> {
  int _appPhase = 0;
  String _capturedEmail = '';
  UserProfile? _masterProfile;
  final List<SavedNotebook> _masterVault = [];

  void _proceedToOnboarding(String email) {
    setState(() {
      _capturedEmail = email;
      _appPhase = 1;
    });
  }

  void _finalizeSystemBoot(UserProfile profile) {
    setState(() {
      _masterProfile = profile;
      _appPhase = 2;
    });
  }

  void _updateProfile(UserProfile newProfile) {
    setState(() => _masterProfile = newProfile);
  }

  void _saveToVault(SavedNotebook notebook) {
    setState(() => _masterVault.insert(0, notebook)); 
  }

  void _terminateSession() {
    setState(() {
      _appPhase = 0;
      _masterProfile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget currentInterface;

    if (_appPhase == 0) {
      currentInterface = AuthScreen(onAuthenticate: _proceedToOnboarding);
    } else if (_appPhase == 1) {
      currentInterface = OnboardingScreen(email: _capturedEmail, onCompile: _finalizeSystemBoot);
    } else {
      currentInterface = SomniSystemCore(
        profile: _masterProfile!,
        vault: _masterVault,
        updateProfile: _updateProfile,
        saveToVault: _saveToVault,
        child: MainNavigationTerminal(onLogout: _terminateSession),
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

/// ------------------------------------------------------------------
/// SCREEN 0: KINETIC AUTHENTICATION GATEWAY (Enhanced 3D)
/// ------------------------------------------------------------------
class AuthScreen extends StatefulWidget {
  final Function(String) onAuthenticate;
  const AuthScreen({super.key, required this.onAuthenticate});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _triggerAuth() {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identity uplink required (Email).'), backgroundColor: Color(0xFF1E2124)));
      return;
    }
    widget.onAuthenticate(_emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('AuthScreen'),
      backgroundColor: const Color(0xFF0D0D0D), // Darker background to pop the gold
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) => CustomPaint(painter: QuantumAuthPainter(animationValue: _bgController.value), size: Size.infinite),
          ),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFB59451).withValues(alpha: 0.3), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('S O M N I', style: GoogleFonts.playfairDisplay(fontSize: 42, color: Colors.white, letterSpacing: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('QUANTUM HEALTH SYSTEM', style: GoogleFonts.lato(fontSize: 10, letterSpacing: 5, color: const Color(0xFFB59451), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 48),
                      _buildField(_emailController, 'Encrypted Identity (Email)', Icons.fingerprint),
                      const SizedBox(height: 16),
                      _buildField(_passController, 'Biometric Passcode', Icons.lock_outline, obscure: true),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity, height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB59451), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: _triggerAuth,
                          child: Text('INITIALIZE SYSTEM', style: GoogleFonts.lato(fontSize: 12, letterSpacing: 3, color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: controller, obscureText: obscure,
      style: GoogleFonts.lato(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFB59451), size: 20),
        hintText: hint, hintStyle: GoogleFonts.lato(color: Colors.grey.shade500),
        filled: true, fillColor: Colors.black.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// SCREEN 1: ONBOARDING
/// ------------------------------------------------------------------
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
        title: g['title'], description: g['desc'], overallProgress: 0.15,
        metrics: [SubMetric("Adherence", 0.8), SubMetric("Biomarker Shift", 0.2), SubMetric("AI Confidence", 0.45)],
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

/// ------------------------------------------------------------------
/// MASTER LAYOUT (Bottom Nav + Drawer)
/// ------------------------------------------------------------------
class MainNavigationTerminal extends StatefulWidget {
  final VoidCallback onLogout;
  const MainNavigationTerminal({super.key, required this.onLogout});

  @override
  State<MainNavigationTerminal> createState() => _MainNavigationTerminalState();
}

class _MainNavigationTerminalState extends State<MainNavigationTerminal> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const AIConciergeScreen(),
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

/// ------------------------------------------------------------------
/// SIDEBAR (Drawer) - THE FIX IS HERE
/// ------------------------------------------------------------------
class EliteDrawer extends StatelessWidget {
  final VoidCallback onLogout;
  const EliteDrawer({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    // We capture the core data here, BEFORE pushing the new route.
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
            // DIRECT DATA PASSING: Fixes the "Unexpected null value" error perfectly.
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

/// ------------------------------------------------------------------
/// TAB 1: AI CONCIERGE & NEW COMPLEX NEURAL CORE
/// ------------------------------------------------------------------
class AIConciergeScreen extends StatefulWidget {
  const AIConciergeScreen({super.key});

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
    return Container(
      height: 180, width: double.infinity,
      color: const Color(0xFF0F0F0F),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (ctx, child) => CustomPaint(painter: NeuralCorePainter(animationValue: _pulseCtrl.value), size: Size.infinite),
          ),
          Positioned(
            top: 16, right: 16,
            child: IconButton(
              icon: const Icon(Icons.bookmark_add, color: Color(0xFFB59451)),
              tooltip: 'Save Chat to Vault', onPressed: _saveCurrentChat,
            ),
          ),
          Positioned(
            bottom: 24, left: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LIVE CORE TELEMETRY', style: GoogleFonts.lato(color: Colors.grey.shade400, fontSize: 10, letterSpacing: 4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniMetric('HR', '48', 'bpm'), const SizedBox(width: 16),
                    _miniMetric('HRV', '92', 'ms'), const SizedBox(width: 16),
                    _miniMetric('O2', '99', '%'),
                  ],
                )
              ],
            ),
          )
        ],
      ),
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

/// ------------------------------------------------------------------
/// TAB 2: DEEP GOAL TRACKER
/// ------------------------------------------------------------------
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
                    LinearProgressIndicator(value: goal.overallProgress + (i*0.1), backgroundColor: const Color(0xFFF4F3EF), color: const Color(0xFFB59451), minHeight: 4),
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
                Center(
                  child: SizedBox(
                    height: 250, width: 250,
                    child: CustomPaint(painter: RadarChartPainter(progress: goal.overallProgress + (index * 0.1))),
                  ),
                ),
                const SizedBox(height: 40),
                Text('SUB-METRIC VECTOR ANALYSIS', style: GoogleFonts.lato(color: Colors.grey.shade500, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 16),
                ...goal.metrics.map((m) => _buildSubMetricBar(m.name, m.value)),
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

/// ------------------------------------------------------------------
/// TAB 3: HIGHLY INTERACTIVE CALENDAR & ARCHIVES
/// ------------------------------------------------------------------
class ClinicalArchivesScreen extends StatelessWidget {
  const ClinicalArchivesScreen({super.key});

  void _openDayTelemetry(BuildContext context, int day, UserProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DailyTelemetrySheet(day: day, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = SomniSystemCore.of(context)!.profile;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Temporal Matrix', style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.bold)),
          Text('Historical biometrics & intervention logs.', style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: 31,
              itemBuilder: (ctx, i) {
                int day = i + 1;
                bool isPast = day <= DateTime.now().day; 
                
                // Create a heatmap effect based on day modulus
                double completionAlpha = isPast ? ((day % 5) * 0.2) + 0.2 : 0; 
                
                return GestureDetector(
                  onTap: isPast ? () => _openDayTelemetry(context, day, profile) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: isPast ? const Color(0xFFB59451).withValues(alpha: completionAlpha) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isPast ? Colors.transparent : Colors.grey.shade300),
                      boxShadow: isPast ? [BoxShadow(color: const Color(0xFFB59451).withValues(alpha: 0.2), blurRadius: 10)] : [],
                    ),
                    child: Center(
                      child: Text('$day', style: TextStyle(
                        color: isPast ? (completionAlpha > 0.5 ? Colors.white : Colors.black) : Colors.grey, 
                        fontWeight: isPast ? FontWeight.bold : FontWeight.normal
                      )),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

/// The Glassmorphic Detail Sheet when a day is clicked
class DailyTelemetrySheet extends StatelessWidget {
  final int day;
  final UserProfile profile;
  const DailyTelemetrySheet({super.key, required this.day, required this.profile});

  @override
  Widget build(BuildContext context) {
    // Generate mock data deterministic to the day
    int recovery = 70 + (day % 30);
    int strain = 40 + (day * 2 % 60);
    int sleep = 60 + (day * 3 % 40);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2124).withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: const Color(0xFFB59451).withValues(alpha: 0.5))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Day $day Analytics', style: GoogleFonts.playfairDisplay(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                const Icon(Icons.verified_user, color: Color(0xFFB59451)),
              ],
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRing('Recovery', recovery, const Color(0xFF4CAF50)),
                _buildRing('Strain', strain, const Color(0xFFB59451)),
                _buildRing('Sleep', sleep, const Color(0xFF2196F3)),
              ],
            ),
            const SizedBox(height: 48),
            Text('GOAL CONTRIBUTIONS', style: GoogleFonts.lato(color: Colors.grey.shade500, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: profile.goals.length,
                itemBuilder: (ctx, i) {
                  final goal = profile.goals[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_graph, color: Color(0xFFB59451), size: 20),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(goal.title, style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.bold)),
                              Text('+ 1.2% optimal trajectory achieved.', style: GoogleFonts.lato(color: Colors.grey.shade400, fontSize: 12)),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRing(String label, int value, Color color) {
    return Column(
      children: [
        SizedBox(
          height: 70, width: 70,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(value: value / 100, backgroundColor: Colors.white10, color: color, strokeWidth: 6),
              Center(child: Text('$value%', style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: GoogleFonts.lato(color: Colors.grey.shade400, fontSize: 12)),
      ],
    );
  }
}

/// ------------------------------------------------------------------
/// DRAWER SCREEN: COGNITIVE VAULT
/// ------------------------------------------------------------------
class CognitiveVaultScreen extends StatelessWidget {
  final List<SavedNotebook> vault; // Passed via constructor to avoid context issues!
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

/// ------------------------------------------------------------------
/// DRAWER SCREEN: PROFILE EDITOR
/// ------------------------------------------------------------------
class ProfileEditorScreen extends StatefulWidget {
  final UserProfile profile; // Passed directly from Drawer
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
    widget.onUpdateProfile(updated); // Safely execute callback
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

/// ------------------------------------------------------------------
/// COMPLEX CUSTOM PAINTERS (Upgraded 3D & Radar)
/// ------------------------------------------------------------------

/// Auth Screen: 3 Intersecting, Multi-Axis Rotating Spheres
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

    _drawSphere(canvas, center, radius, points, paint, t, t * 1.5, 0); // Sphere 1
    _drawSphere(canvas, center, radius * 0.75, points ~/ 1.5, paint..color = const Color(0xFFB59451).withValues(alpha: 0.4), -t, 0, t * 2); // Sphere 2
    _drawSphere(canvas, center, radius * 0.5, points ~/ 2, paint..color = Colors.white.withValues(alpha: 0.1), 0, -t * 2, -t); // Sphere 3
  }

  void _drawSphere(Canvas canvas, Offset center, double radius, int points, Paint paint, double angleX, double angleY, double angleZ) {
    for (int i = 0; i < points; i++) {
      double lat = math.pi * (-0.5 + (i / (points - 1)));
      for (int j = 0; j < points; j++) {
        double lon = 2 * math.pi * (j / (points - 1));
        
        // Base 3D Coordinates
        double x = radius * math.cos(lat) * math.cos(lon);
        double y = radius * math.cos(lat) * math.sin(lon);
        double z = radius * math.sin(lat);

        // X-Axis Rotation
        double y1 = y * math.cos(angleX) - z * math.sin(angleX);
        double z1 = y * math.sin(angleX) + z * math.cos(angleX);
        
        // Y-Axis Rotation
        double x2 = x * math.cos(angleY) + z1 * math.sin(angleY);
        double z2 = -x * math.sin(angleY) + z1 * math.cos(angleY);
        
        // Z-Axis Rotation
        double x3 = x2 * math.cos(angleZ) - y1 * math.sin(angleZ);
        double y3 = x2 * math.sin(angleZ) + y1 * math.cos(angleZ);

        canvas.drawCircle(Offset(center.dx + x3, center.dy + y3), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// AI Core: Pulsing Neural Helix
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
        double angle = progress * math.pi * 4 + t + offsetStrand; // Twist multiplier
        
        // Helix math mapping to 2D
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

class RadarChartPainter extends CustomPainter {
  final double progress;
  RadarChartPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    double radius = size.width / 2.2;
    int sides = 5;

    final gridPaint = Paint()..color = Colors.white.withValues(alpha: 0.1)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (int step = 1; step <= 4; step++) {
      Path path = Path();
      double r = radius * (step / 4);
      for (int i = 0; i < sides; i++) {
        double angle = (i * 2 * math.pi / sides) - (math.pi / 2);
        double x = center.dx + r * math.cos(angle);
        double y = center.dy + r * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    final dataPaint = Paint()..color = const Color(0xFFB59451).withValues(alpha: 0.4)..style = PaintingStyle.fill;
    final linePaint = Paint()..color = const Color(0xFFB59451)..style = PaintingStyle.stroke..strokeWidth = 2;
    Path dataPath = Path();
    
    List<double> mockData = [progress, progress*0.8, progress*1.1, progress*0.9, progress*1.2]; 

    for (int i = 0; i < sides; i++) {
      double angle = (i * 2 * math.pi / sides) - (math.pi / 2);
      double val = mockData[i].clamp(0.0, 1.0);
      double x = center.dx + (radius * val) * math.cos(angle);
      double y = center.dy + (radius * val) * math.sin(angle);
      if (i == 0) {
        dataPath.moveTo(x, y);
      } else {
        dataPath.lineTo(x, y);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, dataPaint);
    canvas.drawPath(dataPath, linePaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
