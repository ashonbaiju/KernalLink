import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../widgets/virtual_joystick.dart';
import '../widgets/steering_wheel.dart';

enum GamepadPreset {
  standard, // Classic Xbox 360 Controller
  racing,   // Steering Wheel + Gas/Brake Pedals for Car Games
  fps,      // Movement Stick + Swipe Aim + Trigger Buttons
  arcade,   // 8-Way D-Pad + 6-Button Grid
}

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  final ConnectionService _conn = ConnectionService();

  GamepadPreset _preset = GamepadPreset.standard;

  double _lx = 0.0;
  double _ly = 0.0;
  double _rx = 0.0;
  double _ry = 0.0;
  double _lt = 0.0;
  double _rt = 0.0;
  final Set<String> _pressedButtons = <String>{};

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

  // --- MINIMAL B&W WIDGET BUILDERS ---

  Widget _buildPresetTab(GamepadPreset preset, String label, IconData icon) {
    final isSel = _preset == preset;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _preset = preset;
          // Reset sticks on preset change
          _lx = 0.0;
          _ly = 0.0;
          _rx = 0.0;
          _ry = 0.0;
          _lt = 0.0;
          _rt = 0.0;
          _pressedButtons.clear();
        });
        _sendState();
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFFFFFFF) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSel ? const Color(0xFFFFFFFF) : const Color(0xFF262626),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSel ? const Color(0xFF000000) : const Color(0xFF888888),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSel ? const Color(0xFF000000) : const Color(0xFF888888),
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String id,
    required String label,
    double size = 46.0,
    bool isCircle = true,
  }) {
    final isDown = _pressedButtons.contains(id);

    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(6),
          color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF111111),
          border: Border.all(
            color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF333333),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
            fontWeight: FontWeight.bold,
            fontSize: size * 0.36,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTriggerButton({
    required String id,
    required String label,
    required bool isLeft,
  }) {
    final isDown = _pressedButtons.contains(id);

    return Listener(
      onPointerDown: (_) {
        setState(() {
          if (isLeft) {
            _lt = 1.0;
          } else {
            _rt = 1.0;
          }
        });
        _setButton(id, true);
      },
      onPointerUp: (_) {
        setState(() {
          if (isLeft) {
            _lt = 0.0;
          } else {
            _rt = 0.0;
          }
        });
        _setButton(id, false);
      },
      onPointerCancel: (_) {
        setState(() {
          if (isLeft) {
            _lt = 0.0;
          } else {
            _rt = 0.0;
          }
        });
        _setButton(id, false);
      },
      child: Container(
        width: 72,
        height: 38,
        decoration: BoxDecoration(
          color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF333333),
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 126,
      height: 126,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF222222)),
            ),
          ),
          Positioned(top: 0, child: _buildDPadBtn('UP', Icons.arrow_drop_up)),
          Positioned(bottom: 0, child: _buildDPadBtn('DOWN', Icons.arrow_drop_down)),
          Positioned(left: 0, child: _buildDPadBtn('LEFT', Icons.arrow_left)),
          Positioned(right: 0, child: _buildDPadBtn('RIGHT', Icons.arrow_right)),
        ],
      ),
    );
  }

  Widget _buildDPadBtn(String id, IconData icon) {
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isDown ? const Color(0xFFFFFFFF) : const Color(0xFF2E2E2E)),
        ),
        child: Icon(
          icon,
          color: isDown ? const Color(0xFF000000) : const Color(0xFFCCCCCC),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildABXYGroup() {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, child: _buildButton(id: 'Y', label: 'Y', size: 42)),
          Positioned(bottom: 0, child: _buildButton(id: 'A', label: 'A', size: 42)),
          Positioned(left: 0, child: _buildButton(id: 'X', label: 'X', size: 42)),
          Positioned(right: 0, child: _buildButton(id: 'B', label: 'B', size: 42)),
        ],
      ),
    );
  }

  // --- PRESET 1: STANDARD XBOX 360 CONTROLLER ---
  Widget _buildStandardXboxView() {
    return Column(
      children: [
        // Top Triggers & Bumpers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildTriggerButton(id: 'LT', label: 'LT', isLeft: true),
                  const SizedBox(width: 8),
                  _buildButton(id: 'LB', label: 'LB', size: 38, isCircle: false),
                ],
              ),
              Row(
                children: [
                  _buildButton(id: 'BACK', label: 'BACK', size: 36, isCircle: false),
                  const SizedBox(width: 8),
                  _buildButton(id: 'GUIDE', label: 'X', size: 38, isCircle: true),
                  const SizedBox(width: 8),
                  _buildButton(id: 'START', label: 'START', size: 36, isCircle: false),
                ],
              ),
              Row(
                children: [
                  _buildButton(id: 'RB', label: 'RB', size: 38, isCircle: false),
                  const SizedBox(width: 8),
                  _buildTriggerButton(id: 'RT', label: 'RT', isLeft: false),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // Main Controls: Left Stick & D-Pad on Left | Right Stick & ABXY on Right
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Column: Stick + D-Pad
                Row(
                  children: [
                    VirtualJoystick(
                      radius: 60,
                      label: 'LS',
                      deadzone: _conn.deadzone,
                      sensitivity: _conn.sensitivity,
                      onDirectionChanged: (offset) {
                        _lx = offset.dx;
                        _ly = offset.dy;
                        _sendState();
                      },
                      onStickClick: () {
                        HapticFeedback.mediumImpact();
                        _setButton('THUMBL', true);
                        Future.delayed(const Duration(milliseconds: 100), () => _setButton('THUMBL', false));
                      },
                    ),
                    const SizedBox(width: 16),
                    _buildDPad(),
                  ],
                ),

                // Right Column: ABXY + Right Stick
                Row(
                  children: [
                    _buildABXYGroup(),
                    const SizedBox(width: 16),
                    VirtualJoystick(
                      radius: 60,
                      label: 'RS',
                      deadzone: _conn.deadzone,
                      sensitivity: _conn.sensitivity,
                      onDirectionChanged: (offset) {
                        _rx = offset.dx;
                        _ry = offset.dy;
                        _sendState();
                      },
                      onStickClick: () {
                        HapticFeedback.mediumImpact();
                        _setButton('THUMBR', true);
                        Future.delayed(const Duration(milliseconds: 100), () => _setButton('THUMBR', false));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- PRESET 2: RACING WHEEL & PEDALS (CAR GAMES) ---
  Widget _buildRacingWheelView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Side: Interactive Steering Wheel + Paddle Shifter LB
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildButton(id: 'LB', label: 'GEAR -\n(LB)', size: 54, isCircle: false),
                  const SizedBox(height: 12),
                  _buildButton(id: 'BACK', label: 'RESET', size: 44, isCircle: false),
                ],
              ),
              const SizedBox(width: 14),
              SteeringWheel(
                size: 210,
                onAngleChanged: (normX) {
                  _lx = normX; // Direct steering mapping to Left Stick X
                  _sendState();
                },
              ),
              const SizedBox(width: 14),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildButton(id: 'RB', label: 'GEAR +\n(RB)', size: 54, isCircle: false),
                  const SizedBox(height: 12),
                  _buildButton(id: 'START', label: 'PAUSE', size: 44, isCircle: false),
                ],
              ),
            ],
          ),

          // Center/Right: Action Buttons (Boost, Handbrake, Camera)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildButton(id: 'Y', label: 'CAM\n(Y)', size: 48, isCircle: true),
              const SizedBox(height: 12),
              _buildButton(id: 'B', label: 'NITRO\n(B)', size: 54, isCircle: true),
              const SizedBox(height: 12),
              _buildButton(id: 'A', label: 'DRIFT\n(A)', size: 54, isCircle: false),
            ],
          ),

          // Right Side: Realistic Vertical Gas & Brake Pedals
          Row(
            children: [
              // Brake Pedal (LT)
              _buildPedal(
                label: 'BRAKE\nREVERSE',
                sublabel: 'LT',
                value: _lt,
                onChanged: (val) {
                  setState(() => _lt = val);
                  _sendState();
                },
              ),
              const SizedBox(width: 16),
              // Gas / Throttle Pedal (RT)
              _buildPedal(
                label: 'ACCEL\nGAS',
                sublabel: 'RT',
                value: _rt,
                isGas: true,
                onChanged: (val) {
                  setState(() => _rt = val);
                  _sendState();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPedal({
    required String label,
    required String sublabel,
    required double value,
    required ValueChanged<double> onChanged,
    bool isGas = false,
  }) {
    return Listener(
      onPointerDown: (e) {
        HapticFeedback.lightImpact();
        onChanged(1.0);
      },
      onPointerMove: (e) {
        // Drag up/down adjusts pedal percentage
        onChanged(1.0);
      },
      onPointerUp: (_) {
        onChanged(0.0);
      },
      onPointerCancel: (_) {
        onChanged(0.0);
      },
      child: Container(
        width: 74,
        height: 180,
        decoration: BoxDecoration(
          color: value > 0.05 ? const Color(0xFFFFFFFF) : const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value > 0.05 ? const Color(0xFFFFFFFF) : const Color(0xFF333333),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                sublabel,
                style: TextStyle(
                  color: value > 0.05 ? const Color(0xFF000000) : const Color(0xFF888888),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Pedal grip grooves
            Column(
              children: List.generate(
                4,
                (i) => Container(
                  width: 44,
                  height: 3,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: value > 0.05 ? const Color(0xFF000000) : const Color(0xFF333333),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: value > 0.05 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PRESET 3: FPS SHOOTER (AIM & FIRE) ---
  Widget _buildFpsView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Move Joystick & D-Pad & Sprint
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              VirtualJoystick(
                radius: 65,
                label: 'MOVE',
                deadzone: _conn.deadzone,
                sensitivity: _conn.sensitivity,
                onDirectionChanged: (offset) {
                  _lx = offset.dx;
                  _ly = offset.dy;
                  _sendState();
                },
                onStickClick: () {
                  HapticFeedback.mediumImpact();
                  _setButton('THUMBL', true);
                  Future.delayed(const Duration(milliseconds: 100), () => _setButton('THUMBL', false));
                },
              ),
              const SizedBox(height: 8),
              _buildButton(id: 'THUMBL', label: 'SPRINT (L3)', size: 40, isCircle: false),
            ],
          ),

          // Center: Quick Triggers & Actions
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  _buildTriggerButton(id: 'LT', label: 'AIM (LT)', isLeft: true),
                  const SizedBox(width: 14),
                  _buildTriggerButton(id: 'RT', label: 'FIRE (RT)', isLeft: false),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildButton(id: 'X', label: 'RELOAD\n(X)', size: 50, isCircle: false),
                  const SizedBox(width: 10),
                  _buildButton(id: 'A', label: 'JUMP\n(A)', size: 50, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'B', label: 'CROUCH\n(B)', size: 50, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'Y', label: 'WEAPON\n(Y)', size: 50, isCircle: false),
                ],
              ),
            ],
          ),

          // Right: Look / Camera Swipe Aim Trackpad + Melee
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFpsAimSurface(),
              const SizedBox(height: 8),
              _buildButton(id: 'THUMBR', label: 'MELEE (R3)', size: 40, isCircle: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFpsAimSurface() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (e) {
        // Direct conversion of touch delta to Right Stick Look
        final dx = (e.delta.dx * 0.08).clamp(-1.0, 1.0);
        final dy = (-e.delta.dy * 0.08).clamp(-1.0, 1.0);
        _rx = dx;
        _ry = dy;
        _sendState();
      },
      onPointerUp: (_) {
        _rx = 0.0;
        _ry = 0.0;
        _sendState();
      },
      child: Container(
        width: 150,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF090909),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E2E2E)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_fixed, color: Color(0xFF666666), size: 28),
              SizedBox(height: 6),
              Text(
                'SWIPE TO AIM / LOOK',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- PRESET 4: RETRO ARCADE ---
  Widget _buildArcadeView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Giant Tactile D-Pad
          _buildDPad(),

          // Center: Coin & Start
          Row(
            children: [
              _buildButton(id: 'BACK', label: 'SELECT\nCOIN', size: 52, isCircle: false),
              const SizedBox(width: 14),
              _buildButton(id: 'START', label: '1P\nSTART', size: 52, isCircle: false),
            ],
          ),

          // Right: 6-Button Arcade Layout (Punches & Kicks)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Top Row: Light, Medium, Heavy Punch
              Row(
                children: [
                  _buildButton(id: 'X', label: 'LP (X)', size: 48, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'Y', label: 'MP (Y)', size: 48, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'RB', label: 'HP (RB)', size: 48, isCircle: true),
                ],
              ),
              const SizedBox(height: 12),
              // Bottom Row: Light, Medium, Heavy Kick
              Row(
                children: [
                  _buildButton(id: 'A', label: 'LK (A)', size: 48, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'B', label: 'MK (B)', size: 48, isCircle: true),
                  const SizedBox(width: 10),
                  _buildButton(id: 'RT', label: 'HK (RT)', size: 48, isCircle: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Presets Selector Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: const Color(0xFF050505),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPresetTab(GamepadPreset.standard, 'XBOX 360', Icons.gamepad),
              const SizedBox(width: 6),
              _buildPresetTab(GamepadPreset.racing, 'STEERING WHEEL (CAR)', Icons.directions_car),
              const SizedBox(width: 6),
              _buildPresetTab(GamepadPreset.fps, 'FPS SHOOTER', Icons.my_location),
              const SizedBox(width: 6),
              _buildPresetTab(GamepadPreset.arcade, 'RETRO ARCADE', Icons.sports_esports),
            ],
          ),
        ),

        const Divider(color: Color(0xFF1E1E1E), height: 1),

        // Active Preset View
        Expanded(
          child: switch (_preset) {
            GamepadPreset.standard => _buildStandardXboxView(),
            GamepadPreset.racing => _buildRacingWheelView(),
            GamepadPreset.fps => _buildFpsView(),
            GamepadPreset.arcade => _buildArcadeView(),
          },
        ),
      ],
    );
  }
}
