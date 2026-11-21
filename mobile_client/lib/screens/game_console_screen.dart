import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connection_service.dart';

class ButtonLayout {
  double x; // Normalized 0.0 to 1.0 (relative to screen width)
  double y; // Normalized 0.0 to 1.0 (relative to screen height)
  double scale;

  ButtonLayout({required this.x, required this.y, this.scale = 1.0});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'scale': scale};

  factory ButtonLayout.fromJson(Map<String, dynamic> json) => ButtonLayout(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      );
}

class GameConsoleScreen extends StatefulWidget {
  const GameConsoleScreen({super.key});

  @override
  State<GameConsoleScreen> createState() => _GameConsoleScreenState();
}

class _GameConsoleScreenState extends State<GameConsoleScreen>
    with SingleTickerProviderStateMixin {
  final ConnectionService _conn = ConnectionService();

  bool _isEditMode = false;
  String? _selectedElementId;

  // Preset Mode:
  // 0 = Default Stick Preset (Left Analog Stick)
  // 1 = Arrow Buttons Preset (Discrete Left < and Right > Buttons)
  // 2 = Steering Wheel Preset (Multi-Turn Wheel with 720deg rotation)
  int _presetMode = 0;
  bool _isMonochromeTheme = false;
  bool _arrowLeftPressed = false;
  bool _arrowRightPressed = false;

  // Steering Wheel State (Preset 2)
  double _wheelAngleDeg = 0.0;
  static const double _maxWheelDeg = 720.0; // 2 full rotations left (-720°), 2 full rotations right (+720°)
  bool _isWheelTouched = false;
  double _lastWheelTouchAngle = 0.0;
  bool _wheelKeyLeftDown = false;
  bool _wheelKeyRightDown = false;
  late AnimationController _wheelAnimCtrl;
  late Animation<double> _wheelAnim;

  // Gamepad Inputs
  double _lx = 0.0;
  double _ly = 0.0;
  double _rx = 0.0;
  double _ry = 0.0;
  double _lt = 0.0;
  double _rt = 0.0;
  final Set<String> _pressedButtons = <String>{};

  // Customizable Element Layouts (Normalized 0.0 - 1.0)
  late Map<String, ButtonLayout> _layouts;

  @override
  void initState() {
    super.initState();
    // Immersive landscape mode: edge-to-edge full screen for console controller
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Steering wheel spring-back centering animation
    _wheelAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _wheelAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _wheelAnimCtrl, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (!_isWheelTouched && _presetMode == 2) {
          setState(() {
            _wheelAngleDeg = _wheelAnim.value;
            _lx = (_wheelAngleDeg / _maxWheelDeg).clamp(-1.0, 1.0);
          });
          _sendState();
        }
      });

    _initDefaultLayouts();
    _loadCustomLayouts();
    _loadPresetMode();
  }

  Future<void> _loadPresetMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getInt('console_preset_mode_v1') ?? 0;
      final m = prefs.getBool('console_mono_theme_v1') ?? false;
      setState(() {
        _presetMode = p.clamp(0, 2);
        _isMonochromeTheme = m;
      });
    } catch (_) {}
  }

  Future<void> _savePresetMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('console_preset_mode_v1', _presetMode);
      await prefs.setBool('console_mono_theme_v1', _isMonochromeTheme);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wheelAnimCtrl.dispose();
    // Restore normal system UI and portrait orientation on exit
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _initDefaultLayouts() {
    // Exact ergonomic placement matching reference screenshots (Images 3 & 4)
    _layouts = {
      'lt_trigger': ButtonLayout(x: 0.04, y: 0.42),
      'lb_bumper': ButtonLayout(x: 0.04, y: 0.62),
      'ls_btn': ButtonLayout(x: 0.05, y: 0.82),

      'dpad': ButtonLayout(x: 0.14, y: 0.16),
      'l_stick': ButtonLayout(x: 0.15, y: 0.62),
      'arrow_buttons': ButtonLayout(x: 0.14, y: 0.62),
      'wheel': ButtonLayout(x: 0.12, y: 0.52),

      'center_cluster': ButtonLayout(x: 0.39, y: 0.05),

      'r_stick': ButtonLayout(x: 0.68, y: 0.12),
      'abxy_cluster': ButtonLayout(x: 0.70, y: 0.52),

      'rt_trigger': ButtonLayout(x: 0.87, y: 0.38),
      'rb_bumper': ButtonLayout(x: 0.87, y: 0.58),
      'rs_btn': ButtonLayout(x: 0.90, y: 0.82),
    };
  }

  Future<void> _loadCustomLayouts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('custom_joystick_console_v4');
      if (jsonStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        setState(() {
          decoded.forEach((key, val) {
            if (_layouts.containsKey(key)) {
              _layouts[key] = ButtonLayout.fromJson(val);
            }
          });
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCustomLayouts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _layouts.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString('custom_joystick_console_v4', jsonEncode(data));
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void _resetDefaultLayout() {
    HapticFeedback.vibrate();
    setState(() {
      _initDefaultLayouts();
      _selectedElementId = null;
    });
    _saveCustomLayouts();
  }

  void _scaleSelected(double delta) {
    if (_selectedElementId == null) return;
    final layout = _layouts[_selectedElementId];
    if (layout != null) {
      HapticFeedback.selectionClick();
      setState(() {
        layout.scale = (layout.scale + delta).clamp(0.6, 2.0);
      });
    }
  }

  // --- INPUT SENSING ---
  void _sendState() {
    _conn.sendGamepad(
      lx: _lx,
      ly: _ly,
      rx: _rx,
      ry: _ry,
      lt: _lt,
      rt: _rt,
      buttons: _pressedButtons,
    );
  }

  void _setButton(String btn, bool isPressed) {
    if (isPressed) {
      if (_pressedButtons.add(btn)) {
        HapticFeedback.lightImpact();
        _sendState();
      }
    } else {
      if (_pressedButtons.remove(btn)) {
        _sendState();
      }
    }
  }

  // --- COMPONENT PLACER & DRAGGER ---
  Widget _buildElement({
    required String id,
    required String name,
    required Widget child,
    required double baseWidth,
    required double baseHeight,
    required double screenWidth,
    required double screenHeight,
  }) {
    final layout = _layouts[id] ?? ButtonLayout(x: 0.1, y: 0.1);
    final isSelected = _isEditMode && (_selectedElementId == id);

    // Compute pixel position from normalized coordinates
    final double pixelX = (layout.x * screenWidth).clamp(0.0, screenWidth - baseWidth * layout.scale);
    final double pixelY = (layout.y * screenHeight).clamp(0.0, screenHeight - baseHeight * layout.scale);

    return Positioned(
      left: pixelX,
      top: pixelY,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isEditMode
            ? () {
                HapticFeedback.selectionClick();
                setState(() => _selectedElementId = id);
              }
            : null,
        onPanUpdate: _isEditMode
            ? (details) {
                setState(() {
                  _selectedElementId = id;
                  // Update normalized position
                  layout.x = ((pixelX + details.delta.dx) / screenWidth).clamp(0.0, 0.95);
                  layout.y = ((pixelY + details.delta.dy) / screenHeight).clamp(0.0, 0.95);
                });
              }
            : null,
        child: Transform.scale(
          scale: layout.scale,
          alignment: Alignment.topLeft,
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withAlpha(80),
                        blurRadius: 10,
                      ),
                    ],
                  )
                : (_isEditMode
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24, width: 1.0),
                      )
                    : null),
            child: IgnorePointer(
              ignoring: _isEditMode,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  // --- MONOCHROME GAMEPAD WIDGETS (BLACK & WHITE THEME) ---

  // Ergonomic Shoulder Bumper / Trigger
  Widget _buildShoulderBtn({
    required String id,
    required String label,
    required bool isTrigger,
    double width = 76,
    double height = 44,
  }) {
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 1.0;
          if (id == 'RT') _rt = 1.0;
        }
        _setButton(id, true);
      },
      onPointerUp: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 0.0;
          if (id == 'RT') _rt = 0.0;
        }
        _setButton(id, false);
      },
      onPointerCancel: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 0.0;
          if (id == 'RT') _rt = 0.0;
        }
        _setButton(id, false);
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDown ? Colors.white : const Color(0xFF14141E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDown ? Colors.white : const Color(0xFF38384E),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDown ? Colors.white.withAlpha(120) : Colors.black.withAlpha(120),
              blurRadius: isDown ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? Colors.black : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  // Monochromatic Faceted D-Pad
  Widget _buildModernDPad({double size = 138}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // D-Pad Cross Background
          Container(
            width: size * 0.36,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Container(
            width: size,
            height: size * 0.36,
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Directional Arrows
          Positioned(top: 0, child: _buildDPadSegment('UP', Icons.keyboard_arrow_up, size)),
          Positioned(bottom: 0, child: _buildDPadSegment('DOWN', Icons.keyboard_arrow_down, size)),
          Positioned(left: 0, child: _buildDPadSegment('LEFT', Icons.keyboard_arrow_left, size)),
          Positioned(right: 0, child: _buildDPadSegment('RIGHT', Icons.keyboard_arrow_right, size)),

          // Center Smooth Hub
          Container(
            width: size * 0.32,
            height: size * 0.32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1C1C28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDPadSegment(String id, IconData icon, double totalSize) {
    final isDown = _pressedButtons.contains(id);
    final double segSize = totalSize * 0.36;
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: segSize,
        height: segSize,
        decoration: BoxDecoration(
          color: isDown ? Colors.white : const Color(0xFF222230),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDown ? Colors.white : const Color(0xFF38384E),
          ),
        ),
        child: Icon(
          icon,
          color: isDown ? Colors.black : Colors.white70,
          size: 22,
        ),
      ),
    );
  }

  // Authentic ABXY Face Buttons Cluster (Matching Reference Images 3 & 4)
  Widget _buildABXYCluster({double size = 150}) {
    final double btnSize = size * 0.32;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Y Button (Top - Amber / Yellow)
          Positioned(
            top: 0,
            child: _buildFaceBtn(
              id: 'Y',
              label: 'Y',
              size: btnSize,
              color: const Color(0xFFF59E0B),
            ),
          ),
          // X Button (Left - Blue)
          Positioned(
            left: 0,
            child: _buildFaceBtn(
              id: 'X',
              label: 'X',
              size: btnSize,
              color: const Color(0xFF3B82F6),
            ),
          ),
          // B Button (Right - Red)
          Positioned(
            right: 0,
            child: _buildFaceBtn(
              id: 'B',
              label: 'B',
              size: btnSize,
              color: const Color(0xFFEF4444),
            ),
          ),
          // A Button (Bottom - Green)
          Positioned(
            bottom: 0,
            child: _buildFaceBtn(
              id: 'A',
              label: 'A',
              size: btnSize,
              color: const Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  // Face Button (A, B, X, Y) with Sleek Halo Border
  Widget _buildFaceBtn({
    required String id,
    required String label,
    required double size,
    Color color = Colors.white,
  }) {
    final effectiveColor = _isMonochromeTheme ? Colors.white : color;
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDown ? effectiveColor : const Color(0xFF14141E),
          border: Border.all(
            color: isDown ? effectiveColor : effectiveColor.withAlpha(160),
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isDown ? effectiveColor.withAlpha(180) : effectiveColor.withAlpha(50),
              blurRadius: isDown ? 12 : 5,
              offset: isDown ? Offset.zero : const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? Colors.black : effectiveColor,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.44,
          ),
        ),
      ),
    );
  }

  // Thumb Stick Click (L3 / R3)
  Widget _buildThumbClickBtn(String id, String label, {double size = 46}) {
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDown ? Colors.white : const Color(0xFF1A1A26),
          border: Border.all(color: isDown ? Colors.white : const Color(0xFF38384E)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? Colors.black : const Color(0xFF9E9EAE),
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  // Concentric Modern Analog Joystick
  Widget _buildModernJoystick({required bool isLeft, double size = 142}) {
    return _ModernConcentricJoystick(
      size: size,
      deadzone: _conn.deadzone,
      sensitivity: _conn.sensitivity,
      onChanged: (offset) {
        if (isLeft) {
          _lx = offset.dx;
          _ly = offset.dy;
        } else {
          _rx = offset.dx;
          _ry = offset.dy;
        }
        _sendState();
      },
    );
  }

  // Two Arrow Movement Buttons (Preset 1: Left < and Right > replacing Left Joystick)
  Widget _buildMovementArrowButtons() {
    const double btnSize = 74.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Left Arrow Button (<)
        _buildMovementArrowBtn(
          isLeft: true,
          size: btnSize,
          isPressed: _arrowLeftPressed,
          onDown: () {
            HapticFeedback.lightImpact();
            setState(() {
              _arrowLeftPressed = true;
              _lx = -1.0;
            });
            _conn.sendKey('left', action: 'down');
            _sendState();
          },
          onUp: () {
            setState(() {
              _arrowLeftPressed = false;
              _lx = _arrowRightPressed ? 1.0 : 0.0;
            });
            _conn.sendKey('left', action: 'up');
            _sendState();
          },
        ),
        const SizedBox(width: 14),
        // Right Arrow Button (>)
        _buildMovementArrowBtn(
          isLeft: false,
          size: btnSize,
          isPressed: _arrowRightPressed,
          onDown: () {
            HapticFeedback.lightImpact();
            setState(() {
              _arrowRightPressed = true;
              _lx = 1.0;
            });
            _conn.sendKey('right', action: 'down');
            _sendState();
          },
          onUp: () {
            setState(() {
              _arrowRightPressed = false;
              _lx = _arrowLeftPressed ? -1.0 : 0.0;
            });
            _conn.sendKey('right', action: 'up');
            _sendState();
          },
        ),
      ],
    );
  }

  Widget _buildMovementArrowBtn({
    required bool isLeft,
    required double size,
    required bool isPressed,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPressed ? Colors.white : const Color(0xFF14141E),
          border: Border.all(
            color: isPressed ? Colors.white : const Color(0xFF38384E),
            width: isPressed ? 2.5 : 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isPressed ? Colors.white.withAlpha(120) : Colors.black.withAlpha(100),
              blurRadius: isPressed ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner concentric circle ring matching reference screenshot
            Container(
              width: size - 18,
              height: size - 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isPressed ? const Color(0xFF888899) : const Color(0xFF282838),
                  width: 1.2,
                ),
              ),
            ),
            Icon(
              isLeft ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
              color: isPressed ? Colors.black : Colors.white,
              size: size * 0.38,
            ),
          ],
        ),
      ),
    );
  }

  // Multi-Turn Steering Wheel Widget (Preset 2: Multi-turn 720deg Lock-to-Lock)
  Widget _buildSteeringWheelWidget({double size = 154}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _wheelAnimCtrl.stop();
        _isWheelTouched = true;
        final center = Offset(size / 2, size / 2);
        final touch = e.localPosition - center;
        _lastWheelTouchAngle = atan2(touch.dy, touch.dx);
        HapticFeedback.selectionClick();
      },
      onPointerMove: (e) {
        if (!_isWheelTouched) return;
        final center = Offset(size / 2, size / 2);
        final touch = e.localPosition - center;
        final currentTouchAngle = atan2(touch.dy, touch.dx);

        double delta = currentTouchAngle - _lastWheelTouchAngle;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;

        final degDelta = delta * (180.0 / pi);
        setState(() {
          _wheelAngleDeg = (_wheelAngleDeg + degDelta).clamp(-_maxWheelDeg, _maxWheelDeg);
          _lastWheelTouchAngle = currentTouchAngle;
          _lx = (_wheelAngleDeg / _maxWheelDeg).clamp(-1.0, 1.0);
        });
        _updateWheelKeyboard(_lx);
        _sendState();
      },
      onPointerUp: (_) => _releaseWheel(),
      onPointerCancel: (_) => _releaseWheel(),
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.rotate(
          angle: _wheelAngleDeg * (pi / 180.0),
          child: Image.asset(
            'assets/steering_wheel.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => CustomPaint(
              size: Size(size, size),
              painter: const _RealisticCarSteeringWheelPainter(),
            ),
          ),
        ),
      ),
    );
  }

  void _updateWheelKeyboard(double lx) {
    if (lx < -0.25) {
      if (!_wheelKeyLeftDown) {
        _wheelKeyLeftDown = true;
        _conn.sendKey('left', action: 'down');
      }
    } else {
      if (_wheelKeyLeftDown) {
        _wheelKeyLeftDown = false;
        _conn.sendKey('left', action: 'up');
      }
    }

    if (lx > 0.25) {
      if (!_wheelKeyRightDown) {
        _wheelKeyRightDown = true;
        _conn.sendKey('right', action: 'down');
      }
    } else {
      if (_wheelKeyRightDown) {
        _wheelKeyRightDown = false;
        _conn.sendKey('right', action: 'up');
      }
    }
  }

  void _releaseWheel() {
    _isWheelTouched = false;
    _updateWheelKeyboard(0.0);
    _wheelAnim = Tween<double>(begin: _wheelAngleDeg, end: 0.0).animate(
      CurvedAnimation(parent: _wheelAnimCtrl, curve: Curves.easeOutCubic),
    );
    _wheelAnimCtrl.forward(from: 0.0);
  }

  // Center Navigation Cluster (Back, Guide, Start)
  Widget _buildCenterCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF101018).withAlpha(200),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF262638)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSmallCenterBtn('BACK', Icons.arrow_back),
          const SizedBox(width: 14),
          _buildSmallCenterBtn('GUIDE', Icons.sports_esports_outlined),
          const SizedBox(width: 14),
          _buildSmallCenterBtn('START', Icons.play_arrow),
        ],
      ),
    );
  }

  Widget _buildSmallCenterBtn(String id, IconData icon) {
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDown ? Colors.white : const Color(0xFF20202E),
          border: Border.all(color: isDown ? Colors.white : const Color(0xFF38384E)),
        ),
        child: Icon(
          icon,
          color: isDown ? Colors.black : const Color(0xFFB0B0C4),
          size: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLinked = _conn.isConnected;
    final selectedLayout = _selectedElementId != null ? _layouts[_selectedElementId] : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenW = constraints.maxWidth;
          final double screenH = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Pure AMOLED Deep Dark Background
              Container(
                color: const Color(0xFF0B0B12),
              ),

              // ==================== LEFT CONTROLS ====================
              // 1. LT Trigger
              _buildElement(
                id: 'lt_trigger',
                name: 'LT Trigger',
                baseWidth: 76,
                baseHeight: 44,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildShoulderBtn(id: 'LT', label: 'LT', isTrigger: true),
              ),

              // 2. LB Bumper
              _buildElement(
                id: 'lb_bumper',
                name: 'LB Bumper',
                baseWidth: 76,
                baseHeight: 44,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildShoulderBtn(id: 'LB', label: 'LB', isTrigger: false),
              ),

              // 3. Left Movement:
              // Preset 0 = Default Left Analog Stick
              // Preset 1 = Discrete Left & Right Movement Arrows
              // Preset 2 = Multi-Turn Realistic Steering Wheel (720deg lock-to-lock)
              if (_presetMode == 0)
                _buildElement(
                  id: 'l_stick',
                  name: 'Left Stick',
                  baseWidth: 142,
                  baseHeight: 142,
                  screenWidth: screenW,
                  screenHeight: screenH,
                  child: _buildModernJoystick(isLeft: true),
                ),
              if (_presetMode == 1)
                _buildElement(
                  id: 'arrow_buttons',
                  name: 'Movement Arrows',
                  baseWidth: 168,
                  baseHeight: 76,
                  screenWidth: screenW,
                  screenHeight: screenH,
                  child: _buildMovementArrowButtons(),
                ),
              if (_presetMode == 2)
                _buildElement(
                  id: 'wheel',
                  name: 'Steering Wheel',
                  baseWidth: 154,
                  baseHeight: 154,
                  screenWidth: screenW,
                  screenHeight: screenH,
                  child: _buildSteeringWheelWidget(size: 154),
                ),

              // 4. Monochromatic Faceted D-Pad
              _buildElement(
                id: 'dpad',
                name: 'D-Pad',
                baseWidth: 138,
                baseHeight: 138,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildModernDPad(),
              ),

              // 5. LS (L3) Sprint Button
              _buildElement(
                id: 'ls_btn',
                name: 'LS Button',
                baseWidth: 46,
                baseHeight: 46,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildThumbClickBtn('THUMBL', 'LS'),
              ),

              // ==================== RIGHT CONTROLS ====================
              // 6. RT Trigger
              _buildElement(
                id: 'rt_trigger',
                name: 'RT Trigger',
                baseWidth: 76,
                baseHeight: 44,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildShoulderBtn(id: 'RT', label: 'RT', isTrigger: true),
              ),

              // 7. RB Bumper
              _buildElement(
                id: 'rb_bumper',
                name: 'RB Bumper',
                baseWidth: 76,
                baseHeight: 44,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildShoulderBtn(id: 'RB', label: 'RB', isTrigger: false),
              ),

              // 8. Monochromatic ABXY Face Buttons Cluster
              _buildElement(
                id: 'abxy_cluster',
                name: 'ABXY Cluster',
                baseWidth: 150,
                baseHeight: 150,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildABXYCluster(),
              ),

              // 9. Right Analog Joystick
              _buildElement(
                id: 'r_stick',
                name: 'Right Stick',
                baseWidth: 142,
                baseHeight: 142,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildModernJoystick(isLeft: false),
              ),

              // 10. RS (R3) Button
              _buildElement(
                id: 'rs_btn',
                name: 'RS Button',
                baseWidth: 46,
                baseHeight: 46,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildThumbClickBtn('THUMBR', 'RS'),
              ),

              // ==================== CENTER CONTROLS ====================
              // 11. Center Back / Guide / Start
              _buildElement(
                id: 'center_cluster',
                name: 'Center Buttons',
                baseWidth: 150,
                baseHeight: 40,
                screenWidth: screenW,
                screenHeight: screenH,
                child: _buildCenterCluster(),
              ),

              // ==================== TOP FLOATING OVERLAY HUD ====================
              // Minimal Floating Exit Bar (Top Left)
              if (!_isEditMode)
                Positioned(
                  top: 10,
                  left: 12,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF14141E).withAlpha(200),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF28283C)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back, color: Color(0xFFCCCCCC), size: 13),
                              SizedBox(width: 4),
                              Text(
                                'EXIT',
                                style: TextStyle(
                                  color: Color(0xFFCCCCCC),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Top Right Controls (Preset Switcher, Latency Status, Layout Customizer)
              if (!_isEditMode)
                Positioned(
                  top: 10,
                  right: 12,
                  child: Row(
                    children: [
                      // Monochromatic Preset Switcher (STICK -> ARROWS -> WHEEL)
                      InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _presetMode = (_presetMode + 1) % 3;
                            _lx = 0.0;
                            _arrowLeftPressed = false;
                            _arrowRightPressed = false;
                            _wheelAngleDeg = 0.0;
                            _wheelAnimCtrl.stop();
                          });
                          _savePresetMode();
                          _sendState();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF14141E).withAlpha(200),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF484860),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _presetMode == 0
                                    ? Icons.sports_esports
                                    : (_presetMode == 1 ? Icons.swap_horiz : Icons.album),
                                color: Colors.white,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _presetMode == 0
                                    ? 'PRESET: STICK'
                                    : (_presetMode == 1 ? 'PRESET: ARROWS' : 'PRESET: WHEEL'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Latency Status Pill (Matching Reference Images 3 & 4)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF091814),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isLinked ? const Color(0xFF10B981) : const Color(0xFF28283C),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isLinked ? const Color(0xFF10B981) : const Color(0xFF6E6E82),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isLinked ? '${_conn.latencyMs}ms' : 'OFFLINE',
                              style: TextStyle(
                                color: isLinked ? const Color(0xFF34D399) : const Color(0xFF88889C),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Layout Customize Button (Matching Reference Images 3 & 4)
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isEditMode = true);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08202A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF06B6D4),
                              width: 1.2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune, color: Color(0xFF22D3EE), size: 13),
                              SizedBox(width: 5),
                              Text(
                                'EDIT LAYOUT',
                                style: TextStyle(
                                  color: Color(0xFF22D3EE),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ==================== EDIT MODE FLOATING TOOLBAR ====================
              if (_isEditMode)
                Positioned(
                  top: 8,
                  left: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F16).withAlpha(240),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white38, width: 1.2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'LAYOUT EDITOR: DRAG BUTTONS TO MOVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),

                        Row(
                          children: [
                            if (selectedLayout != null) ...[
                              InkWell(
                                onTap: () => _scaleSelected(-0.1),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  color: const Color(0xFF1E1E2C),
                                  child: const Icon(Icons.remove, color: Colors.white, size: 14),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  'SIZE ${(selectedLayout.scale * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _scaleSelected(0.1),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  color: const Color(0xFF1E1E2C),
                                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],

                            // Preset Switcher in Edit Mode
                            InkWell(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _presetMode = (_presetMode + 1) % 3;
                                  _selectedElementId = null;
                                });
                                _savePresetMode();
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2C),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF484860)),
                                ),
                                child: Text(
                                  _presetMode == 0
                                      ? 'EDIT: STICK'
                                      : (_presetMode == 1 ? 'EDIT: ARROWS' : 'EDIT: WHEEL'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Color Theme Toggle (Xbox Accents vs Monochrome)
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _isMonochromeTheme = !_isMonochromeTheme;
                                });
                                _savePresetMode();
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2C),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _isMonochromeTheme ? const Color(0xFF71717A) : const Color(0xFFF59E0B),
                                  ),
                                ),
                                child: Text(
                                  _isMonochromeTheme ? 'THEME: MONO' : 'THEME: ACCENTS',
                                  style: TextStyle(
                                    color: _isMonochromeTheme ? Colors.white : const Color(0xFFF59E0B),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Reset
                            InkWell(
                              onTap: _resetDefaultLayout,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222230),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF484860)),
                                ),
                                child: const Text(
                                  'RESET',
                                  style: TextStyle(
                                    color: Color(0xFFD4D4D8),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Done & Save
                            InkWell(
                              onTap: () {
                                _saveCustomLayouts();
                                setState(() {
                                  _isEditMode = false;
                                  _selectedElementId = null;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.check, color: Colors.black, size: 13),
                                    SizedBox(width: 4),
                                    Text(
                                      'SAVE & LOCK',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// Modern concentric high-precision joystick widget
class _ModernConcentricJoystick extends StatefulWidget {
  final double size;
  final double deadzone;
  final double sensitivity;
  final ValueChanged<Offset> onChanged;

  const _ModernConcentricJoystick({
    required this.size,
    required this.deadzone,
    required this.sensitivity,
    required this.onChanged,
  });

  @override
  State<_ModernConcentricJoystick> createState() => _ModernConcentricJoystickState();
}

class _ModernConcentricJoystickState extends State<_ModernConcentricJoystick> {
  Offset _thumbPosition = Offset.zero;

  void _updateOffset(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = localPosition - center;
    final maxRadius = widget.size * 0.38;
    final distance = delta.distance;

    Offset clampedOffset;
    if (distance > maxRadius) {
      clampedOffset = Offset.fromDirection(delta.direction, maxRadius);
    } else {
      clampedOffset = delta;
    }

    setState(() {
      _thumbPosition = clampedOffset;
    });

    final double normX = (clampedOffset.dx / maxRadius).clamp(-1.0, 1.0);
    final double normY = (-clampedOffset.dy / maxRadius).clamp(-1.0, 1.0);

    final mag = sqrt(normX * normX + normY * normY);
    if (mag < widget.deadzone) {
      widget.onChanged(Offset.zero);
      return;
    }

    final scaledX = (normX * widget.sensitivity).clamp(-1.0, 1.0);
    final scaledY = (normY * widget.sensitivity).clamp(-1.0, 1.0);
    widget.onChanged(Offset(scaledX, scaledY));
  }

  void _reset() {
    setState(() => _thumbPosition = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final double thumbSize = widget.size * 0.44;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          HapticFeedback.selectionClick();
          _updateOffset(e.localPosition);
        },
        onPointerMove: (e) => _updateOffset(e.localPosition),
        onPointerUp: (_) => _reset(),
        onPointerCancel: (_) => _reset(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer Ring
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF12121C),
                border: Border.all(color: const Color(0xFF28283C), width: 1.5),
              ),
            ),
            // Middle Boundary Ring
            Container(
              width: widget.size * 0.72,
              height: widget.size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF181824),
                border: Border.all(color: const Color(0xFF2A2A3E), width: 1.0),
              ),
            ),
            // Floating Thumb Knob
            Transform.translate(
              offset: _thumbPosition,
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF262638),
                  border: Border.all(color: const Color(0xFF484864), width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(140),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Container(
                  width: thumbSize * 0.36,
                  height: thumbSize * 0.36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1A1A28),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Photorealistic Monochromatic 4-Spoke Car Steering Wheel Painter (Matching Reference)
class _RealisticCarSteeringWheelPainter extends CustomPainter {
  const _RealisticCarSteeringWheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 2;
    final innerRadius = outerRadius - 20;

    // 1. Outer Molded Steering Wheel Rim
    final rimPaint = Paint()
      ..color = const Color(0xFF1C1C24)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, rimPaint);

    final rimBorder = Paint()
      ..color = const Color(0xFF424254)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, outerRadius, rimBorder);

    // Inner rim hole (cutout to black background)
    final innerHole = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerHole);

    final innerBorder = Paint()
      ..color = const Color(0xFF2E2E3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerRadius, innerBorder);

    // Top 12 o'clock center alignment marker stripe (crisp silver)
    final stripePaint = Paint()
      ..color = const Color(0xFFD4D4D8)
      ..style = PaintingStyle.fill;
    final stripeRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - outerRadius + 10),
      width: 8,
      height: 20,
    );
    canvas.drawRect(stripeRect, stripePaint);

    // 2. Four Spokes Design (Horizontal Left/Right & Lower Angled Spokes)
    final spokePaint = Paint()
      ..color = const Color(0xFF262634)
      ..style = PaintingStyle.fill;
    final spokeBorderPaint = Paint()
      ..color = const Color(0xFF38384C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Spoke A: Left Horizontal Spoke
    final leftSpokeRect = Rect.fromLTRB(
      center.dx - innerRadius + 1,
      center.dy - 12,
      center.dx - 18,
      center.dy + 12,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(leftSpokeRect, const Radius.circular(3)), spokePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(leftSpokeRect, const Radius.circular(3)), spokeBorderPaint);

    // Left spoke button pad plate (multifunction controls)
    final leftPadPaint = Paint()
      ..color = const Color(0xFF161622)
      ..style = PaintingStyle.fill;
    final leftPadRect = Rect.fromLTRB(
      center.dx - innerRadius + 8,
      center.dy - 8,
      center.dx - 24,
      center.dy + 8,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(leftPadRect, const Radius.circular(2)), leftPadPaint);
    // Button details
    final buttonDotPaint = Paint()
      ..color = const Color(0xFF5E5E76)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - innerRadius + 15, center.dy - 3), 2.2, buttonDotPaint);
    canvas.drawCircle(Offset(center.dx - innerRadius + 15, center.dy + 3), 2.2, buttonDotPaint);

    // Spoke B: Right Horizontal Spoke
    final rightSpokeRect = Rect.fromLTRB(
      center.dx + 18,
      center.dy - 12,
      center.dx + innerRadius - 1,
      center.dy + 12,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rightSpokeRect, const Radius.circular(3)), spokePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rightSpokeRect, const Radius.circular(3)), spokeBorderPaint);

    // Right spoke button pad plate
    final rightPadRect = Rect.fromLTRB(
      center.dx + 24,
      center.dy - 8,
      center.dx + innerRadius - 8,
      center.dy + 8,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rightPadRect, const Radius.circular(2)), leftPadPaint);
    canvas.drawCircle(Offset(center.dx + innerRadius - 15, center.dy - 3), 2.2, buttonDotPaint);
    canvas.drawCircle(Offset(center.dx + innerRadius - 15, center.dy + 3), 2.2, buttonDotPaint);

    // Spoke C & D: Lower Angled Spokes (at ~60deg downwards left & right)
    final pathLowerLeft = Path()
      ..moveTo(center.dx - 14, center.dy + 16)
      ..lineTo(center.dx - 22, center.dy + 18)
      ..lineTo(center.dx - innerRadius * 0.65, center.dy + innerRadius * 0.74)
      ..lineTo(center.dx - innerRadius * 0.48, center.dy + innerRadius * 0.88)
      ..close();
    canvas.drawPath(pathLowerLeft, spokePaint);
    canvas.drawPath(pathLowerLeft, spokeBorderPaint);

    final pathLowerRight = Path()
      ..moveTo(center.dx + 14, center.dy + 16)
      ..lineTo(center.dx + 22, center.dy + 18)
      ..lineTo(center.dx + innerRadius * 0.65, center.dy + innerRadius * 0.74)
      ..lineTo(center.dx + innerRadius * 0.48, center.dy + innerRadius * 0.88)
      ..close();
    canvas.drawPath(pathLowerRight, spokePaint);
    canvas.drawPath(pathLowerRight, spokeBorderPaint);

    // 3. Central Airbag Hub & Horn Module
    final hubFill = Paint()
      ..color = const Color(0xFF14141E)
      ..style = PaintingStyle.fill;
    final hubBorder = Paint()
      ..color = const Color(0xFF4A4A60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, 25, hubFill);
    canvas.drawCircle(center, 25, hubBorder);

    // Central Emblem Horn Cap
    final capFill = Paint()
      ..color = const Color(0xFF20202E)
      ..style = PaintingStyle.fill;
    final capBorder = Paint()
      ..color = const Color(0xFF707088)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, 12, capFill);
    canvas.drawCircle(center, 12, capBorder);

    // Center Silver Dot
    final centerDotPaint = Paint()
      ..color = const Color(0xFFE4E4E7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _RealisticCarSteeringWheelPainter oldDelegate) => false;
}
