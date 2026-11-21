import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connection_service.dart';

enum RacingPreset {
  racingStick,    // Preset 1: Car Racing with Left Analog Joystick (Image 1)
  racingArrows,   // Preset 2: Custom Car Racing with Discrete < and > Arrows (Image 2)
  racingWheel,    // Preset 3: Interactive Steering Wheel Disc
  xboxFull,       // Preset 4: Full Standard Xbox 360 Controller
}

enum RacingInputMode { hybrid, keyboard, gamepad }

class CarRacingScreen extends StatefulWidget {
  const CarRacingScreen({super.key});

  @override
  State<CarRacingScreen> createState() => _CarRacingScreenState();
}

class _CarRacingScreenState extends State<CarRacingScreen> with SingleTickerProviderStateMixin {
  final ConnectionService _conn = ConnectionService();

  // Active Controller Preset & Input Mode
  RacingPreset _preset = RacingPreset.racingStick;
  RacingInputMode _inputMode = RacingInputMode.hybrid;

  // Custom Layout / Edit Mode
  bool _isEditMode = false;
  static const String _prefsLayoutKey = 'racing_custom_layout_v3';

  // Customizable Element Offsets (default coordinates on 840x390 virtual canvas matching Images 1 & 2)
  late Map<String, Offset> _positions;
  final Map<String, Offset> _defaultPositions = {
    'lb': const Offset(22, 16),
    'nitro': const Offset(22, 92),
    'steering': const Offset(22, 215),
    'clutch': const Offset(186, 260),
    'center_actions': const Offset(335, 110),
    'touchpad': const Offset(310, 185),
    'shifters': const Offset(565, 246),
    'brake': const Offset(626, 215),
    'gas': const Offset(732, 195),
    'handbrake': const Offset(748, 92),
    'rb': const Offset(748, 16),
    'q_menu': const Offset(230, 92),
    'zoom': const Offset(538, 92),
    'cam_view': const Offset(632, 92),
    // Full Xbox Preset Specific Positions
    'xbox_dpad': const Offset(36, 175),
    'xbox_rstick': const Offset(560, 195),
    'xbox_abxy': const Offset(685, 140),
  };

  bool _gyroEnabled = false;

  // Progressive Ramping Sensitivity (0.30 light tap -> 1.00 heavy hold over 380ms)
  static const double _initialIntensity = 0.30;
  static const double _rampDurationMs = 380.0;

  bool _steerLeftPressed = false;
  double _steerLeftIntensity = 0.0;

  bool _steerRightPressed = false;
  double _steerRightIntensity = 0.0;

  bool _gasPressed = false;
  double _gasIntensity = 0.0;

  bool _brakePressed = false;
  double _brakeIntensity = 0.0;

  bool _clutchPressed = false;
  bool _handbrakePressed = false;
  bool _nitroPressed = false;
  bool _handbrakeLocked = false;

  int _gear = 1;
  final Set<String> _gamepadButtons = <String>{};

  // Joystick state (Mode: racingStick & xboxFull)
  Offset _leftStickOffset = Offset.zero;
  Offset _rightStickOffset = Offset.zero;
  static const double _stickRadius = 45.0;

  // Wheel spring back (Mode: racingWheel)
  double _steeringAngleDeg = 0.0;
  final double _maxSteerDeg = 720.0; // 2 full rotations left (-720°), 2 full rotations right (+720°)
  late AnimationController _springAnimCtrl;
  late Animation<double> _springAnim;
  bool _isSteeringTouched = false;
  double _lastTouchAngle = 0.0;

  // Center Touchpad State (Mouse / Camera Look)
  bool _touchpadIsMouse = false; // false = Right Stick Camera Look, true = PC Mouse
  Offset _lastTouchpadPos = Offset.zero;
  int _touchpadStartTime = 0;

  // 60Hz Progressive Ramping Timer
  Timer? _rampTimer;

  @override
  void initState() {
    super.initState();
    _positions = Map<String, Offset>.from(_defaultPositions);
    _loadCustomLayout();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _springAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _springAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springAnimCtrl, curve: Curves.easeOutBack),
    )..addListener(() {
        if (!_isSteeringTouched && _preset == RacingPreset.racingWheel) {
          setState(() {
            _steeringAngleDeg = _springAnim.value;
          });
          _sendCarState();
        }
      });
  }

  @override
  void dispose() {
    _rampTimer?.cancel();
    _springAnimCtrl.dispose();
    _releaseAllActiveKeys();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Layout Persistence (SharedPreferences)
  // ---------------------------------------------------------------------------
  Future<void> _loadCustomLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsLayoutKey);
      if (raw != null) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        setState(() {
          decoded.forEach((key, val) {
            if (val is List && val.length >= 2) {
              final double dx = (val[0] as num).toDouble();
              final double dy = (val[1] as num).toDouble();
              _positions[key] = Offset(dx.clamp(0.0, 760.0), dy.clamp(0.0, 320.0));
            }
          });
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCustomLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, List<double>> data = {};
      _positions.forEach((k, v) {
        data[k] = [v.dx, v.dy];
      });
      await prefs.setString(_prefsLayoutKey, jsonEncode(data));
    } catch (_) {}
  }

  void _resetLayoutToDefaults() {
    HapticFeedback.mediumImpact();
    setState(() {
      _positions = Map<String, Offset>.from(_defaultPositions);
    });
    _saveCustomLayout();
  }

  void _releaseAllActiveKeys() {
    if (_conn.isConnected) {
      _conn.sendKey('left', action: 'up');
      _conn.sendKey('right', action: 'up');
      _conn.sendKey('up', action: 'up');
      _conn.sendKey('down', action: 'up');
      _conn.sendKey('space', action: 'up');
      _conn.sendKey('shift', action: 'up');
      _conn.sendKey('c', action: 'up');
      _conn.sendGamepad(lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0, buttons: {});
    }
  }

  // ---------------------------------------------------------------------------
  // Progressive Ramping Ticker (~60Hz)
  // ---------------------------------------------------------------------------
  void _checkStartRampTimer() {
    if (_rampTimer != null && _rampTimer!.isActive) return;
    _rampTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _onRampTick());
  }

  void _checkStopRampTimer() {
    if (!_steerLeftPressed && !_steerRightPressed && !_gasPressed && !_brakePressed) {
      _rampTimer?.cancel();
      _rampTimer = null;
    }
  }

  void _onRampTick() {
    bool changed = false;
    const double step = (1.0 - _initialIntensity) * (16.0 / _rampDurationMs);

    if (_steerLeftPressed && _steerLeftIntensity < 1.0) {
      _steerLeftIntensity = min(1.0, _steerLeftIntensity + step);
      changed = true;
    }
    if (_steerRightPressed && _steerRightIntensity < 1.0) {
      _steerRightIntensity = min(1.0, _steerRightIntensity + step);
      changed = true;
    }
    if (_gasPressed && _gasIntensity < 1.0) {
      _gasIntensity = min(1.0, _gasIntensity + step);
      changed = true;
    }
    if (_brakePressed && _brakeIntensity < 1.0) {
      _brakeIntensity = min(1.0, _brakeIntensity + step);
      changed = true;
    }

    if (changed) {
      if (mounted) setState(() {});
      _sendCarState();
    }
  }

  // ---------------------------------------------------------------------------
  // State Dispatcher (XInput Gamepad + PC Keyboard)
  // ---------------------------------------------------------------------------
  void _sendCarState() {
    if (!_conn.isConnected) return;

    double lx = 0.0;
    double ly = 0.0;
    double rx = 0.0;
    double ry = 0.0;

    if (_preset == RacingPreset.racingStick) {
      lx = (_leftStickOffset.dx / _stickRadius).clamp(-1.0, 1.0);
      ly = -(_leftStickOffset.dy / _stickRadius).clamp(-1.0, 1.0);
    } else if (_preset == RacingPreset.racingWheel) {
      lx = (_steeringAngleDeg / _maxSteerDeg).clamp(-1.0, 1.0);
    } else if (_preset == RacingPreset.racingArrows) {
      if (_steerLeftPressed && !_steerRightPressed) {
        lx = -_steerLeftIntensity;
      } else if (_steerRightPressed && !_steerLeftPressed) {
        lx = _steerRightIntensity;
      } else {
        lx = 0.0;
      }
    } else if (_preset == RacingPreset.xboxFull) {
      lx = (_leftStickOffset.dx / _stickRadius).clamp(-1.0, 1.0);
      ly = -(_leftStickOffset.dy / _stickRadius).clamp(-1.0, 1.0);
      rx = (_rightStickOffset.dx / _stickRadius).clamp(-1.0, 1.0);
      ry = -(_rightStickOffset.dy / _stickRadius).clamp(-1.0, 1.0);
    }

    final double rt = _gasPressed ? _gasIntensity : 0.0;
    final double lt = _brakePressed ? _brakeIntensity : 0.0;

    if (_inputMode == RacingInputMode.gamepad || _inputMode == RacingInputMode.hybrid) {
      final Set<String> btns = Set<String>.from(_gamepadButtons);
      if (_handbrakePressed || _handbrakeLocked) btns.add('A');
      if (_nitroPressed) btns.add('B');
      if (_clutchPressed) btns.add('X');

      _conn.sendGamepad(
        lx: lx,
        ly: ly,
        rx: rx,
        ry: ry,
        lt: lt,
        rt: rt,
        buttons: btns,
      );
    }

    // Keyboard mode left/right arrow simulation for joystick
    if ((_preset == RacingPreset.racingStick || _preset == RacingPreset.xboxFull) &&
        (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid)) {
      if (lx < -0.3 && !_steerLeftPressed) {
        _conn.sendKey('left', action: 'down');
      } else if (lx >= -0.3 && _steerLeftPressed) {
        _conn.sendKey('left', action: 'up');
      }
      if (lx > 0.3 && !_steerRightPressed) {
        _conn.sendKey('right', action: 'down');
      } else if (lx <= 0.3 && _steerRightPressed) {
        _conn.sendKey('right', action: 'up');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Input Handlers: Pedals, Steering, Shifters, Zoom, Camera
  // ---------------------------------------------------------------------------
  void _onLeftSteerDown() {
    HapticFeedback.lightImpact();
    setState(() {
      _steerLeftPressed = true;
      _steerLeftIntensity = _initialIntensity;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('left', action: 'down');
    }
    _checkStartRampTimer();
    _sendCarState();
  }

  void _onLeftSteerUp() {
    setState(() {
      _steerLeftPressed = false;
      _steerLeftIntensity = 0.0;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('left', action: 'up');
    }
    _checkStopRampTimer();
    _sendCarState();
  }

  void _onRightSteerDown() {
    HapticFeedback.lightImpact();
    setState(() {
      _steerRightPressed = true;
      _steerRightIntensity = _initialIntensity;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('right', action: 'down');
    }
    _checkStartRampTimer();
    _sendCarState();
  }

  void _onRightSteerUp() {
    setState(() {
      _steerRightPressed = false;
      _steerRightIntensity = 0.0;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('right', action: 'up');
    }
    _checkStopRampTimer();
    _sendCarState();
  }

  void _onGasDown() {
    HapticFeedback.lightImpact();
    setState(() {
      _gasPressed = true;
      _gasIntensity = _initialIntensity;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('up', action: 'down');
    }
    _checkStartRampTimer();
    _sendCarState();
  }

  void _onGasUp() {
    setState(() {
      _gasPressed = false;
      _gasIntensity = 0.0;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('up', action: 'up');
    }
    _checkStopRampTimer();
    _sendCarState();
  }

  void _onBrakeDown() {
    HapticFeedback.lightImpact();
    setState(() {
      _brakePressed = true;
      _brakeIntensity = _initialIntensity;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('down', action: 'down');
    }
    _checkStartRampTimer();
    _sendCarState();
  }

  void _onBrakeUp() {
    setState(() {
      _brakePressed = false;
      _brakeIntensity = 0.0;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('down', action: 'up');
    }
    _checkStopRampTimer();
    _sendCarState();
  }

  void _onHandbrakeDown() {
    HapticFeedback.mediumImpact();
    setState(() => _handbrakePressed = true);
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('space', action: 'down');
    }
    _sendCarState();
  }

  void _onHandbrakeUp() {
    setState(() => _handbrakePressed = false);
    if (!_handbrakeLocked) {
      if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
        _conn.sendKey('space', action: 'up');
      }
    }
    _sendCarState();
  }

  void _onNitroDown() {
    HapticFeedback.mediumImpact();
    setState(() => _nitroPressed = true);
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('shift', action: 'down');
    }
    _sendCarState();
  }

  void _onNitroUp() {
    setState(() => _nitroPressed = false);
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('shift', action: 'up');
    }
    _sendCarState();
  }

  void _onClutchDown() {
    HapticFeedback.lightImpact();
    setState(() => _clutchPressed = true);
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('c', action: 'down');
    }
    _sendCarState();
  }

  void _onClutchUp() {
    setState(() => _clutchPressed = false);
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('c', action: 'up');
    }
    _sendCarState();
  }

  void _shiftGear(bool up) {
    HapticFeedback.selectionClick();
    setState(() {
      if (up && _gear < 6) _gear++;
      if (!up && _gear > 1) _gear--;
    });
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey(up ? 'e' : 'q', action: 'press');
    }
    final btn = up ? 'RB' : 'LB';
    _gamepadButtons.add(btn);
    _sendCarState();
    Future.delayed(const Duration(milliseconds: 120), () {
      _gamepadButtons.remove(btn);
      _sendCarState();
    });
  }

  void _onShoulder(String btn, bool isDown) {
    if (isDown) {
      HapticFeedback.lightImpact();
      _gamepadButtons.add(btn);
      if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
        _conn.sendKey(btn == 'LB' ? 'q' : 'e', action: 'down');
      }
    } else {
      _gamepadButtons.remove(btn);
      if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
        _conn.sendKey(btn == 'LB' ? 'q' : 'e', action: 'up');
      }
    }
    _sendCarState();
    if (mounted) setState(() {});
  }

  // Camera Actions & Zoom
  void _onZoom(bool zoomIn) {
    HapticFeedback.selectionClick();
    _conn.sendZoom(zoomIn ? 'in' : 'out', amount: 120);
    _conn.sendMouseScroll(zoomIn ? 120 : -120);
  }

  void _onCameraViewCycle() {
    HapticFeedback.mediumImpact();
    if (_inputMode == RacingInputMode.keyboard || _inputMode == RacingInputMode.hybrid) {
      _conn.sendKey('c', action: 'press'); // Standard PC racing camera switch
    }
    _gamepadButtons.add('Y');
    _sendCarState();
    Future.delayed(const Duration(milliseconds: 120), () {
      _gamepadButtons.remove('Y');
      _sendCarState();
    });
  }

  void _onRearCamera() {
    HapticFeedback.mediumImpact();
    _conn.sendGamepad(
      lx: 0,
      ly: 0,
      rx: 0,
      ry: -1.0, // Look back
      lt: _brakeIntensity,
      rt: _gasIntensity,
      buttons: {'R3'},
    );
    Future.delayed(const Duration(milliseconds: 350), () {
      _sendCarState();
    });
  }

  // ---------------------------------------------------------------------------
  // Center Touchpad (Mouse Rub / 360 Camera Look)
  // ---------------------------------------------------------------------------
  void _onTouchpadPointerDown(PointerDownEvent e) {
    _lastTouchpadPos = e.localPosition;
    _touchpadStartTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _onTouchpadPointerMove(PointerMoveEvent e) {
    final delta = e.localPosition - _lastTouchpadPos;
    _lastTouchpadPos = e.localPosition;

    if (_touchpadIsMouse) {
      // Smooth PC Mouse Cursor
      _conn.sendMouseMove(delta.dx * 1.6, delta.dy * 1.6);
    } else {
      // Right Stick Camera Angle Rotation
      final rx = (delta.dx * 0.12).clamp(-1.0, 1.0);
      final ry = (-delta.dy * 0.12).clamp(-1.0, 1.0);
      _conn.sendGamepad(
        lx: (_preset == RacingPreset.racingStick)
            ? (_leftStickOffset.dx / _stickRadius).clamp(-1.0, 1.0)
            : (_steerLeftPressed ? -_steerLeftIntensity : (_steerRightPressed ? _steerRightIntensity : 0.0)),
        ly: 0.0,
        rx: rx,
        ry: ry,
        lt: _brakeIntensity,
        rt: _gasIntensity,
        buttons: _gamepadButtons,
      );
    }
  }

  void _onTouchpadPointerUp(PointerUpEvent e) {
    final duration = DateTime.now().millisecondsSinceEpoch - _touchpadStartTime;
    if (duration < 160) {
      if (_touchpadIsMouse) {
        _conn.sendMouseClick('left');
      }
    }
    if (!_touchpadIsMouse) {
      _sendCarState(); // Reset camera stick to center
    }
  }

  // ---------------------------------------------------------------------------
  // Quick Actions "Q" Radial / Options Menu
  // ---------------------------------------------------------------------------
  void _openQuickActionsMenu() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF09090B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF27272A), width: 1.5),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'VEHICLE & COCKPIT ACTIONS (Q)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: const Icon(Icons.close, color: Color(0xFF71717A), size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Actions Grid
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        _buildQuickActionTile(
                          icon: Icons.lightbulb,
                          label: 'HEADLIGHTS (L)',
                          onTap: () {
                            _conn.sendKey('l', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.volume_up,
                          label: 'HORN (H)',
                          onTap: () {
                            _conn.sendKey('h', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.replay,
                          label: 'RESET / FLIP (F)',
                          onTap: () {
                            _conn.sendKey('f', action: 'press');
                            _conn.sendKey('backspace', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.alt_route,
                          label: 'AWD / DIFF (V)',
                          onTap: () {
                            _conn.sendKey('v', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.lock,
                          label: _handbrakeLocked ? 'UNLOCK BRAKE' : 'LOCK BRAKE',
                          color: _handbrakeLocked ? const Color(0xFFEF4444) : null,
                          onTap: () {
                            setState(() {
                              _handbrakeLocked = !_handbrakeLocked;
                            });
                            setModalState(() {});
                            _sendCarState();
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.power_settings_new,
                          label: 'ENGINE (E)',
                          onTap: () {
                            _conn.sendKey('e', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.map,
                          label: 'TELEMETRY (M)',
                          onTap: () {
                            _conn.sendKey('m', action: 'press');
                            Navigator.of(ctx).pop();
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.zoom_in,
                          label: 'ZOOM IN (+)',
                          onTap: () {
                            _onZoom(true);
                          },
                        ),
                        _buildQuickActionTile(
                          icon: Icons.zoom_out,
                          label: 'ZOOM OUT (-)',
                          onTap: () {
                            _onZoom(false);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 116,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color ?? const Color(0xFF27272A), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? const Color(0xFF38BDF8), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD ROOT
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // AMOLED True Black
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: SizedBox(
                width: 840,
                height: 390,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // TOP BAR: Mode Selector, Input Mode Pill, Edit Layout Toggle, Latency
                    _buildTopHeader(),

                    // ================= DRAGGABLE / CUSTOMIZABLE ELEMENTS =================
                    // 1. Steering Cluster (Stick, Arrows, or Wheel)
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'steering',
                        child: _buildSteeringSection(),
                      ),

                    // 2. Clutch / Secondary Pedal
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'clutch',
                        child: _buildClutchPedalButton(),
                      ),

                    // 3. Nitro / Boost Lightning Button
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'nitro',
                        child: _buildRoundButton(
                          size: 60,
                          icon: Icons.bolt,
                          iconColor: _nitroPressed ? const Color(0xFF38BDF8) : const Color(0xFFD4D4D8),
                          isPressed: _nitroPressed,
                          glowColor: const Color(0xFF38BDF8),
                          onDown: _onNitroDown,
                          onUp: _onNitroUp,
                        ),
                      ),

                    // 4. LB Shoulder Button
                    _buildDraggableWidget(
                      keyId: 'lb',
                      child: _buildRoundButton(
                        size: 56,
                        label: 'LB',
                        isPressed: _gamepadButtons.contains('LB'),
                        onDown: () => _onShoulder('LB', true),
                        onUp: () => _onShoulder('LB', false),
                      ),
                    ),

                    // 5. RB Shoulder Button
                    _buildDraggableWidget(
                      keyId: 'rb',
                      child: _buildRoundButton(
                        size: 56,
                        label: 'RB',
                        isPressed: _gamepadButtons.contains('RB'),
                        onDown: () => _onShoulder('RB', true),
                        onUp: () => _onShoulder('RB', false),
                      ),
                    ),

                    // 6. Handbrake / Drift Lever Button
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'handbrake',
                        child: _buildHandbrakeButton(),
                      ),

                    // 7. Gear Shifters (Shift Up & Shift Down)
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'shifters',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMicroGearButton(icon: Icons.keyboard_arrow_up, onTap: () => _shiftGear(true)),
                            const SizedBox(height: 12),
                            _buildMicroGearButton(icon: Icons.keyboard_arrow_down, onTap: () => _shiftGear(false)),
                          ],
                        ),
                      ),

                    // 8. Progressive Brake Pedal
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'brake',
                        child: _buildProgressiveBrakePedal(),
                      ),

                    // 9. Progressive Accelerator / Gas Pedal
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'gas',
                        child: _buildProgressiveGasPedal(),
                      ),

                    // 10. Center Navigation & Gyro Action Buttons (Images 1 & 2)
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'center_actions',
                        child: _buildCenterActionButtons(),
                      ),

                    // 11. Center Touchpad (Mouse Rub / 360 Camera Look Surface)
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'touchpad',
                        child: _buildCenterTouchpad(),
                      ),

                    // 11. Quick Actions "Q" Button
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'q_menu',
                        child: _buildQuickMenuTrigger(),
                      ),

                    // 12. Camera Zoom Cluster (+ and -)
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'zoom',
                        child: _buildZoomCluster(),
                      ),

                    // 13. Camera Angle View Switcher (Y) & Rear Cam
                    if (_preset != RacingPreset.xboxFull)
                      _buildDraggableWidget(
                        keyId: 'cam_view',
                        child: _buildCameraAngleCluster(),
                      ),

                    // ================= FULL XBOX CONTROLLER PRESET ELEMENTS =================
                    if (_preset == RacingPreset.xboxFull) ...[
                      // Left Thumbstick
                      _buildDraggableWidget(
                        keyId: 'steering',
                        child: _buildXboxStick(isLeft: true),
                      ),
                      // D-Pad
                      _buildDraggableWidget(
                        keyId: 'xbox_dpad',
                        child: _buildXboxDpad(),
                      ),
                      // Right Thumbstick (Camera Look)
                      _buildDraggableWidget(
                        keyId: 'xbox_rstick',
                        child: _buildXboxStick(isLeft: false),
                      ),
                      // ABXY Cluster
                      _buildDraggableWidget(
                        keyId: 'xbox_abxy',
                        child: _buildXboxAbxyCluster(),
                      ),
                      // LT & RT Analog Trigger Buttons
                      _buildDraggableWidget(
                        keyId: 'brake',
                        child: _buildRoundButton(
                          size: 64,
                          label: 'LT',
                          isPressed: _brakePressed,
                          onDown: _onBrakeDown,
                          onUp: _onBrakeUp,
                        ),
                      ),
                      _buildDraggableWidget(
                        keyId: 'gas',
                        child: _buildRoundButton(
                          size: 64,
                          label: 'RT',
                          isPressed: _gasPressed,
                          onDown: _onGasDown,
                          onUp: _onGasUp,
                        ),
                      ),
                    ],

                    // Top Status HUD (Gear, Speed, Ramping Readout)
                    Positioned(
                      top: 48,
                      left: 270,
                      right: 270,
                      child: _buildCenterHud(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Header: Presets, Input Mode Pill, Edit Mode Toggle
  // ---------------------------------------------------------------------------
  Widget _buildTopHeader() {
    return Positioned(
      top: 10,
      left: 14,
      right: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Exit button
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, color: Color(0xFF71717A), size: 13),
                  SizedBox(width: 4),
                  Text(
                    'EXIT',
                    style: TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Center: Preset Dots (Stick, Wheel, Arrows) + Wi-Fi Broadcast Icon (Matching Images 1 & 2)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPresetDot(RacingPreset.racingStick, 'STICK (PRESET 1)'),
              const SizedBox(width: 26),
              _buildPresetDot(RacingPreset.racingWheel, 'WHEEL'),
              const SizedBox(width: 26),
              _buildPresetDot(RacingPreset.racingArrows, 'ARROWS (PRESET 2)'),
              const SizedBox(width: 26),
              // Wi-Fi Broadcast Icon ((•))
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                child: Icon(
                  Icons.wifi_tethering,
                  color: _conn.isConnected ? const Color(0xFFD4D4D8) : const Color(0xFF52525B),
                  size: 16,
                ),
              ),
            ],
          ),

          // Right Controls: Edit Layout Toggle & Input Mode Pill
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit Layout Mode Button
              InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _isEditMode = !_isEditMode;
                  });
                  if (!_isEditMode) {
                    _saveCustomLayout();
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isEditMode ? const Color(0xFF38BDF8).withAlpha(40) : const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isEditMode ? const Color(0xFF38BDF8) : const Color(0xFF27272A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isEditMode ? Icons.check : Icons.tune,
                        color: _isEditMode ? const Color(0xFF38BDF8) : const Color(0xFFA1A1AA),
                        size: 12,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isEditMode ? 'DONE (SAVE)' : 'EDIT LAYOUT',
                        style: TextStyle(
                          color: _isEditMode ? const Color(0xFF38BDF8) : const Color(0xFFD4D4D8),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_isEditMode) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: _resetLayoutToDefaults,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF221618),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF882222)),
                    ),
                    child: const Text(
                      'RESET',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(width: 10),

              // Input Mode Pill (HYBRID / PC KEYS / GAMEPAD)
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (_inputMode == RacingInputMode.hybrid) {
                      _inputMode = RacingInputMode.keyboard;
                    } else if (_inputMode == RacingInputMode.keyboard) {
                      _inputMode = RacingInputMode.gamepad;
                    } else {
                      _inputMode = RacingInputMode.hybrid;
                    }
                  });
                  _releaseAllActiveKeys();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _conn.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _inputMode == RacingInputMode.hybrid
                            ? 'HYBRID'
                            : _inputMode == RacingInputMode.keyboard
                                ? 'PC KEYS'
                                : 'GAMEPAD',
                        style: const TextStyle(
                          color: Color(0xFFE4E4E7),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
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
    );
  }

  Widget _buildPresetDot(RacingPreset p, String label) {
    final bool isActive = _preset == p;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _preset = p;
          _leftStickOffset = Offset.zero;
          _rightStickOffset = Offset.zero;
          _steeringAngleDeg = 0.0;
          _steerLeftPressed = false;
          _steerRightPressed = false;
          _steerLeftIntensity = 0.0;
          _steerRightIntensity = 0.0;
        });
        _releaseAllActiveKeys();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? Colors.white : const Color(0xFF71717A),
              width: 1.6,
            ),
          ),
          alignment: Alignment.center,
          child: isActive
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Draggable Customizable Widget Wrapper
  // ---------------------------------------------------------------------------
  Widget _buildDraggableWidget({
    required String keyId,
    required Widget child,
  }) {
    final offset = _positions[keyId] ?? _defaultPositions[keyId] ?? Offset.zero;

    if (!_isEditMode) {
      return Positioned(
        left: offset.dx,
        top: offset.dy,
        child: child,
      );
    }

    // Edit Mode: draggable container with accent bounding outline
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newX = (offset.dx + details.delta.dx).clamp(0.0, 780.0);
            final newY = (offset.dy + details.delta.dy).clamp(30.0, 320.0);
            _positions[keyId] = Offset(newX, newY);
          });
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF38BDF8).withAlpha(20),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFF38BDF8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.drag_indicator, color: Colors.black, size: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Center HUD (Cockpit display)
  // ---------------------------------------------------------------------------
  Widget _buildCenterHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E1E24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'GEAR: $_gear',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            _gasPressed
                ? 'THROTTLE: ${(_gasIntensity * 100).toInt()}%'
                : _brakePressed
                    ? 'BRAKE: ${(_brakeIntensity * 100).toInt()}%'
                    : _steerLeftPressed
                        ? 'STEER LEFT: ${(_steerLeftIntensity * 100).toInt()}%'
                        : _steerRightPressed
                            ? 'STEER RIGHT: ${(_steerRightIntensity * 100).toInt()}%'
                            : 'STANDBY',
            style: TextStyle(
              color: _gasPressed
                  ? const Color(0xFF10B981)
                  : _brakePressed
                      ? const Color(0xFFEF4444)
                      : (_steerLeftPressed || _steerRightPressed)
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF71717A),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            '${_conn.latencyMs}ms',
            style: const TextStyle(
              color: Color(0xFF71717A),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Steering Control Selector (Stick, Wheel, or Discrete Arrows)
  // ---------------------------------------------------------------------------
  Widget _buildSteeringSection() {
    if (_preset == RacingPreset.racingStick) {
      return _buildAnalogJoystick();
    } else if (_preset == RacingPreset.racingWheel) {
      return _buildInteractiveWheelDisc();
    } else {
      return _buildSteeringArrowButtons();
    }
  }

  // Analog Joystick Steering
  Widget _buildAnalogJoystick() {
    const double outerSize = 126.0;
    const double knobSize = 56.0;
    const center = Offset(outerSize / 2, outerSize / 2);

    return Listener(
      onPointerDown: (e) {
        HapticFeedback.selectionClick();
        _updateLeftStick(e.localPosition - center);
      },
      onPointerMove: (e) => _updateLeftStick(e.localPosition - center),
      onPointerUp: (_) {
        setState(() => _leftStickOffset = Offset.zero);
        _sendCarState();
      },
      onPointerCancel: (_) {
        setState(() => _leftStickOffset = Offset.zero);
        _sendCarState();
      },
      child: Container(
        width: outerSize,
        height: outerSize,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3F3F46), width: 3.0),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: outerSize - 32,
              height: outerSize - 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF27272A), width: 1.5),
              ),
            ),
            Transform.translate(
              offset: _leftStickOffset,
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF3F3F46),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF71717A), width: 2.0),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: knobSize * 0.45,
                  height: knobSize * 0.45,
                  decoration: const BoxDecoration(
                    color: Color(0xFF27272A),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateLeftStick(Offset rawDelta) {
    final dist = rawDelta.distance;
    final clamped = dist > _stickRadius ? rawDelta * (_stickRadius / dist) : rawDelta;
    setState(() => _leftStickOffset = clamped);
    _sendCarState();
  }

  // Interactive Wheel Disc
  Widget _buildInteractiveWheelDisc() {
    const double size = 126.0;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _springAnimCtrl.stop();
        _isSteeringTouched = true;
        final center = Offset(size / 2, size / 2);
        final touch = e.localPosition - center;
        _lastTouchAngle = atan2(touch.dy, touch.dx);
        HapticFeedback.selectionClick();
      },
      onPointerMove: (e) {
        if (!_isSteeringTouched) return;
        final center = Offset(size / 2, size / 2);
        final touch = e.localPosition - center;
        final currentTouchAngle = atan2(touch.dy, touch.dx);

        double delta = currentTouchAngle - _lastTouchAngle;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;

        final degDelta = delta * (180.0 / pi);
        setState(() {
          _steeringAngleDeg = (_steeringAngleDeg + degDelta).clamp(-_maxSteerDeg, _maxSteerDeg);
          _lastTouchAngle = currentTouchAngle;
        });
        _sendCarState();
      },
      onPointerUp: (_) {
        _isSteeringTouched = false;
        _springAnim = Tween<double>(begin: _steeringAngleDeg, end: 0.0).animate(
          CurvedAnimation(parent: _springAnimCtrl, curve: Curves.easeOutCubic),
        );
        _springAnimCtrl.forward(from: 0.0);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.rotate(
          angle: _steeringAngleDeg * (pi / 180.0),
          child: CustomPaint(
            painter: _RealisticSteeringWheelPainter(),
          ),
        ),
      ),
    );
  }

  // Dedicated Left & Right Arrow Buttons with Progressive Sensitivity
  Widget _buildSteeringArrowButtons() {
    const double btnSize = 74.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: (_) => _onLeftSteerDown(),
          onPointerUp: (_) => _onLeftSteerUp(),
          onPointerCancel: (_) => _onLeftSteerUp(),
          child: _buildProgressiveDirectionButton(
            size: btnSize,
            isLeft: true,
            isPressed: _steerLeftPressed,
            intensity: _steerLeftIntensity,
          ),
        ),
        const SizedBox(width: 14),
        Listener(
          onPointerDown: (_) => _onRightSteerDown(),
          onPointerUp: (_) => _onRightSteerUp(),
          onPointerCancel: (_) => _onRightSteerUp(),
          child: _buildProgressiveDirectionButton(
            size: btnSize,
            isLeft: false,
            isPressed: _steerRightPressed,
            intensity: _steerRightIntensity,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressiveDirectionButton({
    required double size,
    required bool isLeft,
    required bool isPressed,
    required double intensity,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPressed
            ? Color.lerp(const Color(0xFF27272A), const Color(0xFF3F3F46), intensity)
            : const Color(0xFF1C1C21),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPressed
              ? Color.lerp(const Color(0xFF71717A), Colors.white, intensity)!
              : const Color(0xFF3F3F46),
          width: isPressed ? 2.5 : 2.0,
        ),
        boxShadow: isPressed
            ? [
                BoxShadow(
                  color: Colors.white.withAlpha((intensity * 80).toInt()),
                  blurRadius: 10 + (intensity * 6),
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size - 18,
            height: size - 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isPressed ? const Color(0xFF52525B) : const Color(0xFF27272A),
                width: 1.2,
              ),
            ),
          ),
          Icon(
            isLeft ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
            size: size * 0.36,
            color: isPressed
                ? Color.lerp(const Color(0xFFE4E4E7), Colors.white, intensity)
                : const Color(0xFFA1A1AA),
          ),
          if (isPressed && intensity > 0.35)
            Positioned(
              bottom: 6,
              child: Text(
                '${(intensity * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Center Touchpad (Mouse Rub Area / 360 Camera Rotation Surface)
  // ---------------------------------------------------------------------------
  Widget _buildCenterTouchpad() {
    const double width = 190.0;
    const double height = 125.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27272A), width: 1.5),
      ),
      child: Stack(
        children: [
          // Touch surface listener
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onTouchpadPointerDown,
            onPointerMove: _onTouchpadPointerMove,
            onPointerUp: _onTouchpadPointerUp,
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: _TouchpadGridPainter(),
              ),
            ),
          ),

          // Header Mode Switcher (CAM LOOK vs MOUSE)
          Positioned(
            top: 4,
            left: 6,
            right: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _touchpadIsMouse = !_touchpadIsMouse;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C21),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3F3F46)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _touchpadIsMouse ? Icons.mouse : Icons.threed_rotation,
                          size: 10,
                          color: const Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _touchpadIsMouse ? 'MOUSE LOOK' : 'CAM LOOK (RS)',
                          style: const TextStyle(
                            color: Color(0xFFE4E4E7),
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text(
                  'RUB TO ROTATE',
                  style: TextStyle(
                    color: Color(0xFF52525B),
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Quick Actions "Q" Trigger Button
  // ---------------------------------------------------------------------------
  Widget _buildQuickMenuTrigger() {
    return InkWell(
      onTap: _openQuickActionsMenu,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF38BDF8), width: 2.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF38BDF8).withAlpha(60),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Q',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'MENU',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontWeight: FontWeight.bold,
                fontSize: 6.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera Zoom Cluster (+ and - buttons)
  // ---------------------------------------------------------------------------
  Widget _buildZoomCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _onZoom(true),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C21),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _onZoom(false),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C21),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.zoom_out, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera Angle Cluster (Cycle View Y & Rear Camera)
  // ---------------------------------------------------------------------------
  Widget _buildCameraAngleCluster() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Camera View Cycle (Y button / C key)
        InkWell(
          onTap: _onCameraViewCycle,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C21),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3F3F46), width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam, color: Color(0xFFE4E4E7), size: 16),
                Text(
                  'CAM (Y)',
                  style: TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 6.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Rear View Camera
        InkWell(
          onTap: _onRearCamera,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C21),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3F3F46), width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flip_camera_android, color: Color(0xFFE4E4E7), size: 16),
                Text(
                  'REAR',
                  style: TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 6.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pedals & Buttons (Clutch, Handbrake, Micro Shifters, Progressive Pedals)
  // ---------------------------------------------------------------------------
  Widget _buildClutchPedalButton() {
    const double size = 56.0;

    return Listener(
      onPointerDown: (_) => _onClutchDown(),
      onPointerUp: (_) => _onClutchUp(),
      onPointerCancel: (_) => _onClutchUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _clutchPressed ? const Color(0xFF3F3F46) : const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(
            color: _clutchPressed ? Colors.white : const Color(0xFF3F3F46),
            width: 2.0,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 3; i++)
              Container(
                width: 24,
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: _clutchPressed ? Colors.white : const Color(0xFF71717A),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandbrakeButton() {
    const double size = 64.0;
    final bool active = _handbrakePressed || _handbrakeLocked;

    return Listener(
      onPointerDown: (_) => _onHandbrakeDown(),
      onPointerUp: (_) => _onHandbrakeUp(),
      onPointerCancel: (_) => _onHandbrakeUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3F3F46) : const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? const Color(0xFFEF4444) : const Color(0xFF3F3F46),
            width: 2.0,
          ),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x66EF4444),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size(32, 32),
          painter: _HandbrakeIconPainter(
            color: active ? const Color(0xFFEF4444) : const Color(0xFFD4D4D8),
          ),
        ),
      ),
    );
  }

  Widget _buildMicroGearButton({required IconData icon, required VoidCallback onTap}) {
    const double size = 36.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3F3F46), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: const Color(0xFFD4D4D8), size: 20),
      ),
    );
  }

  Widget _buildProgressiveBrakePedal() {
    const double size = 88.0;

    return Listener(
      onPointerDown: (_) => _onBrakeDown(),
      onPointerUp: (_) => _onBrakeUp(),
      onPointerCancel: (_) => _onBrakeUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _brakePressed
              ? Color.lerp(const Color(0xFF27272A), const Color(0xFF3F3F46), _brakeIntensity)
              : const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(
            color: _brakePressed
                ? Color.lerp(const Color(0xFF71717A), const Color(0xFFEF4444), _brakeIntensity)!
                : const Color(0xFF3F3F46),
            width: _brakePressed ? 2.5 : 2.0,
          ),
          boxShadow: _brakePressed
              ? [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withAlpha((_brakeIntensity * 100).toInt()),
                    blurRadius: 10 + (_brakeIntensity * 6),
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size - 22,
              height: size - 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _brakePressed ? const Color(0xFF52525B) : const Color(0xFF27272A),
                  width: 1.2,
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 3; i++)
                  Container(
                    width: 38,
                    height: 5,
                    margin: const EdgeInsets.symmetric(vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _brakePressed
                          ? Color.lerp(const Color(0xFFA1A1AA), Colors.white, _brakeIntensity)
                          : const Color(0xFF71717A),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                if (_brakePressed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${(_brakeIntensity * 100).toInt()}%',
                      style: TextStyle(
                        color: _brakeIntensity > 0.8 ? const Color(0xFFEF4444) : Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressiveGasPedal() {
    const double width = 80.0;
    const double height = 114.0;

    return Listener(
      onPointerDown: (_) => _onGasDown(),
      onPointerUp: (_) => _onGasUp(),
      onPointerCancel: (_) => _onGasUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _gasPressed
              ? Color.lerp(const Color(0xFF27272A), const Color(0xFF3F3F46), _gasIntensity)
              : const Color(0xFF1C1C21),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(38),
            bottomLeft: Radius.circular(38),
            bottomRight: Radius.circular(38),
          ),
          border: Border.all(
            color: _gasPressed
                ? Color.lerp(const Color(0xFF71717A), const Color(0xFF10B981), _gasIntensity)!
                : const Color(0xFF3F3F46),
            width: _gasPressed ? 2.5 : 2.0,
          ),
          boxShadow: _gasPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withAlpha((_gasIntensity * 100).toInt()),
                    blurRadius: 10 + (_gasIntensity * 6),
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 5; i++)
              Container(
                width: 36,
                height: 4.5,
                margin: const EdgeInsets.symmetric(vertical: 2.5),
                decoration: BoxDecoration(
                  color: _gasPressed
                      ? Color.lerp(const Color(0xFFA1A1AA), Colors.white, _gasIntensity)
                      : const Color(0xFF71717A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            if (_gasPressed)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${(_gasIntensity * 100).toInt()}%',
                  style: TextStyle(
                    color: _gasIntensity > 0.8 ? const Color(0xFF10B981) : Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full Xbox Controller Specific Widgets
  // ---------------------------------------------------------------------------
  Widget _buildXboxStick({required bool isLeft}) {
    const double size = 110.0;
    const double knobSize = 50.0;
    const center = Offset(size / 2, size / 2);
    final offset = isLeft ? _leftStickOffset : _rightStickOffset;

    return Listener(
      onPointerDown: (e) {
        HapticFeedback.selectionClick();
        _updateXboxStick(isLeft, e.localPosition - center);
      },
      onPointerMove: (e) => _updateXboxStick(isLeft, e.localPosition - center),
      onPointerUp: (_) {
        setState(() {
          if (isLeft) {
            _leftStickOffset = Offset.zero;
          } else {
            _rightStickOffset = Offset.zero;
          }
        });
        _sendCarState();
      },
      onPointerCancel: (_) {
        setState(() {
          if (isLeft) {
            _leftStickOffset = Offset.zero;
          } else {
            _rightStickOffset = Offset.zero;
          }
        });
        _sendCarState();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3F3F46), width: 2.5),
        ),
        alignment: Alignment.center,
        child: Transform.translate(
          offset: offset,
          child: Container(
            width: knobSize,
            height: knobSize,
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF71717A), width: 2.0),
            ),
            alignment: Alignment.center,
            child: Text(
              isLeft ? 'LS' : 'RS',
              style: const TextStyle(
                color: Color(0xFFD4D4D8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateXboxStick(bool isLeft, Offset rawDelta) {
    final dist = rawDelta.distance;
    final clamped = dist > _stickRadius ? rawDelta * (_stickRadius / dist) : rawDelta;
    setState(() {
      if (isLeft) {
        _leftStickOffset = clamped;
      } else {
        _rightStickOffset = clamped;
      }
    });
    _sendCarState();
  }

  Widget _buildXboxDpad() {
    const double btnSize = 34.0;

    return SizedBox(
      width: btnSize * 3,
      height: btnSize * 3,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: btnSize,
            child: _buildDpadBtn('UP', Icons.arrow_drop_up, btnSize),
          ),
          Positioned(
            bottom: 0,
            left: btnSize,
            child: _buildDpadBtn('DOWN', Icons.arrow_drop_down, btnSize),
          ),
          Positioned(
            top: btnSize,
            left: 0,
            child: _buildDpadBtn('LEFT', Icons.arrow_left, btnSize),
          ),
          Positioned(
            top: btnSize,
            right: 0,
            child: _buildDpadBtn('RIGHT', Icons.arrow_right, btnSize),
          ),
        ],
      ),
    );
  }

  Widget _buildDpadBtn(String id, IconData icon, double size) {
    final isDown = _gamepadButtons.contains(id);

    return Listener(
      onPointerDown: (_) {
        HapticFeedback.selectionClick();
        _gamepadButtons.add(id);
        _sendCarState();
        setState(() {});
      },
      onPointerUp: (_) {
        _gamepadButtons.remove(id);
        _sendCarState();
        setState(() {});
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDown ? const Color(0xFF3F3F46) : const Color(0xFF1C1C21),
          border: Border.all(color: const Color(0xFF3F3F46)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildXboxAbxyCluster() {
    const double btnSize = 42.0;

    return SizedBox(
      width: btnSize * 3,
      height: btnSize * 3,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: btnSize,
            child: _buildAbxyBtn('Y', const Color(0xFFFBBF24), btnSize),
          ),
          Positioned(
            bottom: 0,
            left: btnSize,
            child: _buildAbxyBtn('A', const Color(0xFF10B981), btnSize),
          ),
          Positioned(
            top: btnSize,
            left: 0,
            child: _buildAbxyBtn('X', const Color(0xFF38BDF8), btnSize),
          ),
          Positioned(
            top: btnSize,
            right: 0,
            child: _buildAbxyBtn('B', const Color(0xFFEF4444), btnSize),
          ),
        ],
      ),
    );
  }

  Widget _buildAbxyBtn(String label, Color color, double size) {
    final isDown = _gamepadButtons.contains(label);

    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        _gamepadButtons.add(label);
        _sendCarState();
        setState(() {});
      },
      onPointerUp: (_) {
        _gamepadButtons.remove(label);
        _sendCarState();
        setState(() {});
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDown ? color : const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.0),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? Colors.black : color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // 3 Center Action Buttons (Matching Reference Images 1 & 2: Back, Gyro Toggle, Play/Start)
  Widget _buildCenterActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Rear View / Look Back
        _buildRoundButton(
          size: 46,
          icon: Icons.arrow_back,
          onDown: _onRearCamera,
          onUp: () {},
        ),
        const SizedBox(width: 18),

        // 2. Gyroscope / Tilt Steering Toggle
        _buildRoundButton(
          size: 46,
          icon: Icons.screen_rotation,
          isPressed: _gyroEnabled,
          onDown: () {
            HapticFeedback.mediumImpact();
            setState(() => _gyroEnabled = !_gyroEnabled);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_gyroEnabled ? 'Tilt Steering Enabled (Turn phone to steer)' : 'Touch Steering Enabled'),
                duration: const Duration(milliseconds: 900),
                backgroundColor: const Color(0xFF1E1E24),
              ),
            );
          },
          onUp: () {},
        ),
        const SizedBox(width: 18),

        // 3. Play / Pause / Start Button
        _buildRoundButton(
          size: 46,
          icon: Icons.play_arrow,
          onDown: () {
            HapticFeedback.lightImpact();
            _conn.sendGamepad(
              lx: 0,
              ly: 0,
              rx: 0,
              ry: 0,
              lt: _brakeIntensity,
              rt: _gasIntensity,
              buttons: {'START'},
            );
            _conn.sendKey('enter', action: 'press');
          },
          onUp: () {},
        ),
      ],
    );
  }

  Widget _buildRoundButton({
    required double size,
    String? label,
    IconData? icon,
    Color? iconColor,
    double? iconSize,
    bool isPressed = false,
    Color? glowColor,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isPressed ? const Color(0xFF3F3F46) : const Color(0xFF1C1C21),
          shape: BoxShape.circle,
          border: Border.all(
            color: isPressed ? (glowColor ?? Colors.white) : const Color(0xFF3F3F46),
            width: isPressed ? 2.5 : 2.0,
          ),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Text(
                label,
                style: TextStyle(
                  color: isPressed ? Colors.white : const Color(0xFFE4E4E7),
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.35,
                  letterSpacing: 0.5,
                ),
              )
            : Icon(
                icon,
                color: isPressed ? Colors.white : (iconColor ?? const Color(0xFFD4D4D8)),
                size: iconSize ?? (size * 0.44),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Painters (Touchpad Grid, Handbrake Silhouette, Realistic Steering Wheel)
// ---------------------------------------------------------------------------
class _TouchpadGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E1E24)
      ..strokeWidth = 1.0;

    // Subtle center crosshair
    final center = Offset(size.width / 2, size.height / 2 + 6);
    canvas.drawLine(Offset(center.dx - 12, center.dy), Offset(center.dx + 12, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 12), Offset(center.dx, center.dy + 12), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HandbrakeIconPainter extends CustomPainter {
  final Color color;
  const _HandbrakeIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawLine(Offset(size.width * 0.2, size.height * 0.8), Offset(size.width * 0.85, size.height * 0.8), paint);

    final pivotPath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.8)
      ..lineTo(size.width * 0.35, size.height * 0.6)
      ..lineTo(size.width * 0.45, size.height * 0.8)
      ..close();
    canvas.drawPath(pivotPath, fillPaint);

    canvas.drawLine(Offset(size.width * 0.35, size.height * 0.65), Offset(size.width * 0.72, size.height * 0.22), paint..strokeWidth = 3.2);

    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.34),
      Offset(size.width * 0.76, size.height * 0.17),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(Offset(size.width * 0.79, size.height * 0.13), 2.2, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _HandbrakeIconPainter oldDelegate) => oldDelegate.color != color;
}

class _RealisticSteeringWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 3;
    final innerRadius = outerRadius - 18;

    final rimPaint = Paint()
      ..color = const Color(0xFF18181B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, rimPaint);

    final rimBorder = Paint()
      ..color = const Color(0xFF3F3F46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, outerRadius, rimBorder);

    final innerHole = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerHole);

    final innerBorder = Paint()
      ..color = const Color(0xFF27272A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerRadius, innerBorder);

    final stripePaint = Paint()
      ..color = const Color(0xFFD4D4D8)
      ..style = PaintingStyle.fill;
    final stripeRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - outerRadius + 9),
      width: 10,
      height: 18,
    );
    canvas.drawRect(stripeRect, stripePaint);

    final spokePaint = Paint()
      ..color = const Color(0xFF27272A)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTRB(center.dx - innerRadius, center.dy - 8, center.dx - 18, center.dy + 8), spokePaint);
    canvas.drawRect(Rect.fromLTRB(center.dx + 18, center.dy - 8, center.dx + innerRadius, center.dy + 8), spokePaint);
    canvas.drawRect(Rect.fromLTRB(center.dx - 8, center.dy + 18, center.dx + 8, center.dy + innerRadius), spokePaint);

    final hubFill = Paint()
      ..color = const Color(0xFF18181B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 22, hubFill);

    final hubBorder = Paint()
      ..color = const Color(0xFF52525B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, 22, hubBorder);

    final emblemPaint = Paint()
      ..color = const Color(0xFFD4D4D8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, emblemPaint);
  }

  @override
  bool shouldRepaint(covariant _RealisticSteeringWheelPainter oldDelegate) => false;
}
