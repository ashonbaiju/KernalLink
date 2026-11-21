import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/audio_service.dart';
import 'game_console_screen.dart';
import 'car_racing_screen.dart';
import 'trackpad_screen.dart';
import 'media_screen.dart';
import 'dual_monitor_screen.dart';
import 'audio_controller_screen.dart';
import 'connection_dialog.dart';
import 'settings_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ConnectionService _conn = ConnectionService();
  final AudioRelayService _audio = AudioRelayService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late TextEditingController _manualIpCtrl;

  @override
  void initState() {
    super.initState();
    // Allow both portrait and landscape on the Home Screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _manualIpCtrl = TextEditingController(text: _conn.address);

    _audio.addListener(_onAudioUpdated);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Trigger Wi-Fi discovery probe on launch
    _conn.sendDiscoveryProbe();
  }

  @override
  void dispose() {
    _audio.removeListener(_onAudioUpdated);
    _manualIpCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onAudioUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openConnectionDialog() {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
  }

  void _openSettingsDialog() {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  void _openScreen(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  // ===========================================================================
  // STATE A: DISCONNECTED / CONNECT PAGE
  // When not connected, the home screen acts as a dedicated, modern Connect Hub
  // ===========================================================================
  Widget _buildConnectPage(BuildContext context, bool isConnecting) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          // Header: Crown Logo & Title
          Center(
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF27272A), width: 1.2),
                  ),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 14),
                const Text(
                  'KERNALLINK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'LINK TO WINDOWS PC',
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Live Connecting Indicator (When connection in progress)
          if (isConnecting) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF3F3F46), width: 1.0),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, _) {
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color.lerp(const Color(0xFF71717A), Colors.white, _pulseAnimation.value),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: _pulseAnimation.value * 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'LINKING TO ${_conn.address}...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      _conn.disconnect();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: const Text(
                        'CANCEL ATTEMPT',
                        style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Auto-Discovered Wi-Fi PC Card (If server discovered on local network)
          if (_conn.hasDiscoveredServer && _conn.discoveredAddress != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi, color: Colors.white, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FOUND PC: ${_conn.discoveredHostname ?? "WINDOWS PC"}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_conn.discoveredAddress}  ·  Detected on Wi-Fi',
                          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      _conn.connect(_conn.discoveredAddress!);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'CONNECT',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 1-TAP DIRECT CONNECTION PRESETS
          const Text(
            'CHOOSE CONNECTION METHOD',
            style: TextStyle(
              color: Color(0xFF71717A),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          // 1. USB Cable (ADB Reverse - Recommended)
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _conn.connect('127.0.0.1:8889');
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF27272A), width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF222226)),
                    ),
                    child: const Icon(Icons.usb, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'USB Cable (ADB Reverse)',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '<0.5ms',
                              style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        SizedBox(height: 3),
                        Text(
                          '127.0.0.1:8889  ·  Ultra-low latency for gaming & 120Hz display',
                          style: TextStyle(color: Color(0xFF71717A), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFF52525B), size: 14),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 2. Wi-Fi Auto-Discovery Scan
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _conn.sendDiscoveryProbe();
              if (_conn.hasDiscoveredServer && _conn.discoveredAddress != null) {
                _conn.connect(_conn.discoveredAddress!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Scanning local network for PC server...'),
                    duration: Duration(seconds: 1),
                    backgroundColor: Color(0xFF18181B),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF27272A), width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF222226)),
                    ),
                    child: const Icon(Icons.wifi, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Local Wi-Fi Network',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _conn.hasDiscoveredServer ? 'FOUND' : 'SCAN',
                              style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _conn.hasDiscoveredServer
                              ? '${_conn.discoveredAddress}  ·  Tap to connect over Wi-Fi'
                              : 'Auto-scan local network for running KernalLink PC server',
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFF52525B), size: 14),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 3. USB Tethering
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _conn.connect('192.168.42.129:8889');
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF27272A), width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF222226)),
                    ),
                    child: const Icon(Icons.cable, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USB Tethering (RNDIS)',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '192.168.42.129:8889  ·  Direct USB hotspot network link',
                          style: TextStyle(color: Color(0xFF71717A), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFF52525B), size: 14),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // MANUAL CUSTOM IP INPUT
          const Text(
            'OR ENTER MANUAL PC IP',
            style: TextStyle(
              color: Color(0xFF71717A),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0C0F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _manualIpCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: '192.168.1.x:8889',
                      hintStyle: TextStyle(color: Color(0xFF52525B), fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (_manualIpCtrl.text.isNotEmpty) {
                    _conn.connect(_manualIpCtrl.text.trim());
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'CONNECT',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Footnote / Help tip
          const Center(
            child: Text(
              'Make sure KernalLink.exe or server.py is running on your PC',
              style: TextStyle(color: Color(0xFF52525B), fontSize: 10, letterSpacing: 0.4),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATE B: CONNECTED / DEVICE INFO & CONNECTIVITY HUB
  // When connected, shows live device info, host telemetry, & mode triggers
  // ===========================================================================
  Widget _buildConnectedHub(BuildContext context) {
    final String hostName = _conn.discoveredHostname ?? (_conn.address.startsWith('127.0.0.1') ? 'PC WORKSTATION' : 'WINDOWS PC');
    final String connType = _conn.address.startsWith('127.0.0.1') ? 'USB ADB CABLE' : 'WI-FI NETWORK';
    final String latencyText = _conn.address.startsWith('127.0.0.1') ? '<0.5ms Ping' : '${_conn.latencyMs}ms Ping';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Crown Logo & Settings
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF27272A), width: 1.0),
                    ),
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KERNALLINK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'DEVICE & STREAM HUB',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              InkWell(
                onTap: _openSettingsDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0C0E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF27272A), width: 1.0),
                  ),
                  child: const Icon(Icons.tune, color: Color(0xFFE4E4E7), size: 18),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // CONNECTED DEVICE INFO MODULE (Modern, Hairline, Zero Boxy Clutter)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF09090C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF27272A), width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Row with Breathing Glow Dot
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, _) {
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: _pulseAnimation.value * 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'LINK ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141418),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF27272A), width: 0.8),
                      ),
                      child: Text(
                        latencyText,
                        style: const TextStyle(
                          color: Color(0xFFE4E4E7),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Host Details
                Text(
                  hostName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_conn.address}  ·  $connType  ·  120Hz Ultra Ready',
                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 10.5),
                ),

                const SizedBox(height: 14),

                // Action Controls: Switch PC / Disconnect
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _openConnectionDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'SWITCH PC',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _conn.disconnect();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141418),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'DISCONNECT',
                          style: TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // AUDIO RELAY & VIRTUAL SPEAKER MODULE
          _buildAudioRelayCard(context),

          const SizedBox(height: 22),

          // CONTROLLER PROFILES SECTION
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONTROLLER MODES',
                style: TextStyle(
                  color: Color(0xFF71717A),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '6 ACTIVE',
                style: TextStyle(
                  color: Color(0xFF52525B),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 1. Audio Relay & Virtual Speaker Controller Mode
          _buildModeTile(
            title: 'AUDIO CONTROLLER',
            subtitle: 'Stream laptop audio to phone with zero lag, virtual speaker switcher & EQ mixer',
            badge: '48KHZ STEREO · VIRTUAL SPEAKER',
            icon: Icons.headphones_outlined,
            onTap: () => _openScreen(const AudioControllerScreen()),
          ),

          const SizedBox(height: 8),

          // 2. External Monitor (Display 2)
          _buildModeTile(
            title: 'EXTERNAL MONITOR',
            subtitle: '120Hz secondary Windows monitor with direct multi-touch controls',
            badge: '120HZ EXTENDED',
            icon: Icons.monitor_outlined,
            onTap: () => _openScreen(const DualMonitorScreen()),
          ),

          const SizedBox(height: 8),

          // 2. Modern Joystick Console Gamepad
          _buildModeTile(
            title: 'CONSOLE GAMEPAD',
            subtitle: 'Full-screen Xbox 360 controller with customizable sticks & haptics',
            badge: 'XINPUT · 360',
            icon: Icons.sports_esports_outlined,
            onTap: () => _openScreen(const GameConsoleScreen()),
          ),

          const SizedBox(height: 8),

          // 3. Car Racing Cockpit
          _buildModeTile(
            title: 'RACING COCKPIT',
            subtitle: 'Steering wheel, analog throttle, brake pedals & drift handbrake',
            badge: 'WHEEL & PEDALS',
            icon: Icons.sports_motorsports_outlined,
            onTap: () => _openScreen(const CarRacingScreen()),
          ),

          const SizedBox(height: 8),

          // 4. Precision Trackpad & Keyboard
          _buildModeTile(
            title: 'TRACKPAD & KEYBOARD',
            subtitle: 'Multi-touch gesture touchpad with pinch-to-zoom & full PC keyboard',
            badge: 'PRECISION MOUSE',
            icon: Icons.mouse_outlined,
            onTap: () => _openScreen(const _WrapperScreen(
              title: 'TRACKPAD & KEYBOARD',
              child: TrackpadScreen(),
            )),
          ),

          const SizedBox(height: 8),

          // 5. Media Remote Controller
          _buildModeTile(
            title: 'MEDIA REMOTE',
            subtitle: 'Volume control, 10s seek, play/pause, media navigation & fullscreen',
            badge: 'AUDIO / VIDEO',
            icon: Icons.play_circle_outline,
            onTap: () => _openScreen(const _WrapperScreen(
              title: 'MEDIA CONTROLLER',
              child: MediaScreen(),
            )),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAudioRelayCard(BuildContext context) {
    final bool isStreaming = _audio.isStreaming;
    final bool isSocketLive = _audio.socketConnected;
    final bool isVirtualActive = _audio.isVirtualSpeakerDefault;
    final bool isSwitching = _audio.isSwitching;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF09090C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isStreaming ? Colors.white : const Color(0xFF27272A),
          width: isStreaming ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141418),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF27272A), width: 0.8),
                    ),
                    child: Icon(
                      isStreaming ? Icons.graphic_eq : Icons.headphones_outlined,
                      color: isStreaming ? Colors.white : const Color(0xFFA1A1AA),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LAPTOP AUDIO SHARE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        !isStreaming
                            ? 'TAP STREAM TO PLAY ON PHONE'
                            : (isSocketLive
                                ? 'PLAYING ON THIS PHONE · 48KHZ STEREO'
                                : 'CONNECTING TO PORT 8891...'),
                        style: const TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isStreaming && isSocketLive) ? Colors.white : const Color(0xFF141418),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isStreaming ? Colors.white : const Color(0xFF27272A),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  !isStreaming ? 'STANDBY' : (isSocketLive ? 'LIVE PCM' : 'WAIT PC'),
                  style: TextStyle(
                    color: (isStreaming && isSocketLive) ? Colors.black : const Color(0xFFA1A1AA),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Output Status Info Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E1E24)),
            ),
            child: Row(
              children: [
                Icon(
                  isVirtualActive ? Icons.speaker_group_outlined : Icons.laptop_chromebook,
                  color: isVirtualActive ? Colors.white : const Color(0xFFA1A1AA),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVirtualActive
                            ? 'WINDOWS OUTPUT: KERNALLINK VIRTUAL SPEAKER'
                            : 'WINDOWS OUTPUT: ${_audio.activePcDevice.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isVirtualActive
                            ? 'Laptop sound streams exclusively to phone. Laptop is silent.'
                            : 'Laptop sound plays on laptop and streams to this phone.',
                        style: const TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action 1: Switch Windows Audio Device (Virtual vs Laptop) & Stream Toggle
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _audio.switchPcAudioDevice(isVirtualActive ? 'speakers' : 'virtual');
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141418),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isSwitching
                          ? 'SWITCHING OUTPUT...'
                          : (isVirtualActive ? 'SWITCH TO LAPTOP MIRROR' : 'SWITCH TO VIRTUAL SPEAKER'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Stream Start / Stop Toggle
              InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (isStreaming) {
                    _audio.stopStream();
                  } else {
                    _audio.startStream();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isStreaming ? const Color(0xFF18181D) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: isStreaming ? Border.all(color: const Color(0xFF3F3F46)) : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isStreaming ? 'STOP STREAM' : 'START STREAM',
                    style: TextStyle(
                      color: isStreaming ? const Color(0xFFA1A1AA) : Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Volume Slider & Mute Row
          if (isStreaming) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _audio.toggleMute();
                  },
                  icon: Icon(
                    _audio.isMuted ? Icons.volume_off : Icons.volume_up,
                    color: _audio.isMuted ? const Color(0xFF71717A) : Colors.white,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: const Color(0xFF27272A),
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _audio.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        _audio.setVolume(val);
                      },
                    ),
                  ),
                ),
                Text(
                  '${(_audio.volume * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _openScreen(const AudioControllerScreen());
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27272A), width: 0.8),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune, color: Color(0xFFA1A1AA), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'OPEN FULL AUDIO CONTROLLER MODE',
                    style: TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
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

  Widget _buildModeTile({
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF09090C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1C1C20), width: 1.0),
        ),
        child: Row(
          children: [
            // Minimal Icon Container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF121215),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF222226), width: 1.0),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),

            // Mode Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF27272A), width: 0.8),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Color(0xFFD4D4D8),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right, color: Color(0xFF52525B), size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _conn,
      builder: (context, _) {
        final bool isConn = _conn.isConnected;
        final bool isConnecting = _conn.state == ConnectionStateEnum.connecting;

        return Scaffold(
          backgroundColor: const Color(0xFF000000), // Pure AMOLED True Black
          body: SafeArea(
            child: isConn
                ? _buildConnectedHub(context)
                : _buildConnectPage(context, isConnecting),
          ),
        );
      },
    );
  }
}

// Minimal AMOLED wrapper scaffold for sub-screens with back button
class _WrapperScreen extends StatelessWidget {
  final String title;
  final Widget child;

  const _WrapperScreen({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Pure AMOLED True Black
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: child,
      ),
    );
  }
}
