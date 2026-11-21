import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';

class XboxControllerScreen extends StatefulWidget {
  const XboxControllerScreen({super.key});

  @override
  State<XboxControllerScreen> createState() => _XboxControllerScreenState();
}

class _XboxControllerScreenState extends State<XboxControllerScreen> {
  final ConnectionService _conn = ConnectionService();

  double _lx = 0.0;
  double _ly = 0.0;
  double _rx = 0.0;
  double _ry = 0.0;
  double _lt = 0.0;
  double _rt = 0.0;
  final Set<String> _pressedButtons = <String>{};

  @override
  void initState() {
    super.initState();
    // Lock to landscape for optimal handheld gaming
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Re-enable portrait when exiting back to menu
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

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

  // Exact reference style circular button
  Widget _buildCircleBtn({
    required String id,
    required String label,
    double size = 48.0,
    bool isTrigger = false,
  }) {
    final isDown = _pressedButtons.contains(id);

    return Listener(
      onPointerDown: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 1.0;
          if (id == 'RT') _rt = 1.0;
        }
        _setButton(id, true);
        if (id == 'THUMBL') _setButton('LS', true);
        if (id == 'THUMBR') _setButton('RS', true);
      },
      onPointerUp: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 0.0;
          if (id == 'RT') _rt = 0.0;
        }
        _setButton(id, false);
        if (id == 'THUMBL') _setButton('LS', false);
        if (id == 'THUMBR') _setButton('RS', false);
      },
      onPointerCancel: (_) {
        if (isTrigger) {
          if (id == 'LT') _lt = 0.0;
          if (id == 'RT') _rt = 0.0;
        }
        _setButton(id, false);
        if (id == 'THUMBL') _setButton('LS', false);
        if (id == 'THUMBR') _setButton('RS', false);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDown ? const Color(0xFFCCCCCC) : const Color(0xFF525252),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? const Color(0xFF000000) : const Color(0xFF1E1E1E),
            fontWeight: FontWeight.w900,
            fontSize: size * 0.40,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // Exact reference style small center button (Back / Guide / Start)
  Widget _buildCenterRoundBtn({
    required String id,
    required Widget icon,
    double size = 38.0,
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
          shape: BoxShape.circle,
          color: isDown ? const Color(0xFFB0B0B0) : const Color(0xFF444444),
          border: Border.all(
            color: const Color(0xFF555555),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: icon,
      ),
    );
  }

  // Exact reference style Petal / Clover D-Pad
  Widget _buildCloverDPad() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // UP Petal
          Positioned(
            top: 0,
            child: _buildDPadPetal('UP', isVertical: true),
          ),
          // DOWN Petal
          Positioned(
            bottom: 0,
            child: _buildDPadPetal('DOWN', isVertical: true),
          ),
          // LEFT Petal
          Positioned(
            left: 0,
            child: _buildDPadPetal('LEFT', isVertical: false),
          ),
          // RIGHT Petal
          Positioned(
            right: 0,
            child: _buildDPadPetal('RIGHT', isVertical: false),
          ),
          // Center smooth hub
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF383838),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDPadPetal(String id, {required bool isVertical}) {
    final isDown = _pressedButtons.contains(id);
    return Listener(
      onPointerDown: (_) => _setButton(id, true),
      onPointerUp: (_) => _setButton(id, false),
      onPointerCancel: (_) => _setButton(id, false),
      child: Container(
        width: isVertical ? 46 : 52,
        height: isVertical ? 52 : 46,
        decoration: BoxDecoration(
          color: isDown ? const Color(0xFFCCCCCC) : const Color(0xFF555555),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  // Exact reference style concentric Joystick
  Widget _buildConcentricJoystick({
    required bool isLeft,
    required double size,
  }) {
    return _ReferenceJoystickWidget(
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _conn,
      builder: (context, _) {
        final bool isLinked = _conn.isConnected;

        return Scaffold(
          backgroundColor: const Color(0xFF1E1E1E),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Guaranteed zero overflow with FittedBox
                return FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 820,
                    height: 380,
                    child: Stack(
                      children: [
                        // Exit to Home button in top left corner
                        Positioned(
                          top: 10,
                          left: 10,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF444444)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back, color: Color(0xFF888888), size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'HOME',
                                    style: TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // TOP CENTER STATUS INDICATOR CIRCLES (exact like reference)
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Left double circle ◎
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF6E6E6E), width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF6E6E6E),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 38),

                              // Middle circle ○
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF6E6E6E), width: 1.5),
                                ),
                              ),
                              const SizedBox(width: 38),

                              // Right signal circle ((•))
                              const Icon(
                                Icons.wifi_tethering,
                                color: Color(0xFF6E6E6E),
                                size: 16,
                              ),
                            ],
                          ),
                        ),

                        // CENTER 3 ROUND BUTTONS (← , Rotate/Phone, ▶)
                        Positioned(
                          top: 115,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // BACK (Left Arrow ←)
                              _buildCenterRoundBtn(
                                id: 'BACK',
                                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E1E1E), size: 20),
                              ),
                              const SizedBox(width: 28),

                              // GUIDE / HOME (Phone with arrows icon)
                              _buildCenterRoundBtn(
                                id: 'GUIDE',
                                icon: const Icon(Icons.screen_rotation, color: Color(0xFF1E1E1E), size: 18),
                              ),
                              const SizedBox(width: 28),

                              // START (Play arrow ▶)
                              _buildCenterRoundBtn(
                                id: 'START',
                                icon: const Icon(Icons.play_arrow, color: Color(0xFF1E1E1E), size: 20),
                              ),
                            ],
                          ),
                        ),

                        // CENTER PILL BADGE ("Unlinked" / "Linked")
                        Positioned(
                          top: 175,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                              decoration: BoxDecoration(
                                color: isLinked ? const Color(0xFF555555) : const Color(0xFF444444),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isLinked ? 'Linked (${_conn.latencyMs}ms)' : 'Unlinked',
                                style: TextStyle(
                                  color: isLinked ? const Color(0xFFFFFFFF) : const Color(0xFF1E1E1E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ==================== LEFT SIDE ====================
                        // 1. Clover D-Pad (Top Left)
                        Positioned(
                          top: 40,
                          left: 90,
                          child: _buildCloverDPad(),
                        ),

                        // 2. "LS" Button (to the left of D-Pad)
                        Positioned(
                          top: 145,
                          left: 20,
                          child: _buildCircleBtn(id: 'THUMBL', label: 'LS', size: 48),
                        ),

                        // 3. Left Joystick (Bottom Left)
                        Positioned(
                          bottom: 25,
                          left: 55,
                          child: _buildConcentricJoystick(isLeft: true, size: 146),
                        ),

                        // 4. "LB" & "LT" Buttons (to the right of Left Joystick)
                        Positioned(
                          bottom: 120,
                          left: 215,
                          child: _buildCircleBtn(id: 'LB', label: 'LB', size: 48),
                        ),
                        Positioned(
                          bottom: 40,
                          left: 215,
                          child: _buildCircleBtn(id: 'LT', label: 'LT', size: 48, isTrigger: true),
                        ),

                        // ==================== RIGHT SIDE ====================
                        // 1. Right Joystick (Top Right)
                        Positioned(
                          top: 35,
                          right: 95,
                          child: _buildConcentricJoystick(isLeft: false, size: 146),
                        ),

                        // 2. "RS" Button (to the right of Right Joystick)
                        Positioned(
                          top: 145,
                          right: 20,
                          child: _buildCircleBtn(id: 'THUMBR', label: 'RS', size: 48),
                        ),

                        // 3. "RB" & "RT" Buttons (to the left of ABXY diamond)
                        Positioned(
                          bottom: 120,
                          right: 215,
                          child: _buildCircleBtn(id: 'RB', label: 'RB', size: 48),
                        ),
                        Positioned(
                          bottom: 40,
                          right: 215,
                          child: _buildCircleBtn(id: 'RT', label: 'RT', size: 48, isTrigger: true),
                        ),

                        // 4. ABXY Diamond Cluster (Bottom Right)
                        // "Y" (Top)
                        Positioned(
                          bottom: 140,
                          right: 98,
                          child: _buildCircleBtn(id: 'Y', label: 'Y', size: 46),
                        ),
                        // "X" (Left)
                        Positioned(
                          bottom: 85,
                          right: 148,
                          child: _buildCircleBtn(id: 'X', label: 'X', size: 46),
                        ),
                        // "B" (Right)
                        Positioned(
                          bottom: 85,
                          right: 48,
                          child: _buildCircleBtn(id: 'B', label: 'B', size: 46),
                        ),
                        // "A" (Bottom)
                        Positioned(
                          bottom: 30,
                          right: 98,
                          child: _buildCircleBtn(id: 'A', label: 'A', size: 46),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// Custom Concentric Joystick matching the exact reference image
class _ReferenceJoystickWidget extends StatefulWidget {
  final double size;
  final double deadzone;
  final double sensitivity;
  final ValueChanged<Offset> onChanged;

  const _ReferenceJoystickWidget({
    required this.size,
    required this.deadzone,
    required this.sensitivity,
    required this.onChanged,
  });

  @override
  State<_ReferenceJoystickWidget> createState() => _ReferenceJoystickWidgetState();
}

class _ReferenceJoystickWidgetState extends State<_ReferenceJoystickWidget> {
  Offset _dragOffset = Offset.zero;

  void _updateTouch(Offset localPos) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = localPos - center;
    final maxDist = widget.size * 0.38;

    Offset clampedDelta;
    if (delta.distance > maxDist) {
      clampedDelta = Offset.fromDirection(delta.direction, maxDist);
    } else {
      clampedDelta = delta;
    }

    setState(() {
      _dragOffset = clampedDelta;
    });

    double normX = clampedDelta.dx / maxDist;
    double normY = -clampedDelta.dy / maxDist; // UP is positive in controller Y

    final dist = sqrt(normX * normX + normY * normY);
    if (dist < widget.deadzone) {
      normX = 0.0;
      normY = 0.0;
    } else {
      final factor = (dist - widget.deadzone) / (1.0 - widget.deadzone);
      normX = (normX / dist) * factor * widget.sensitivity;
      normY = (normY / dist) * factor * widget.sensitivity;
      normX = normX.clamp(-1.0, 1.0);
      normY = normY.clamp(-1.0, 1.0);
    }

    widget.onChanged(Offset(normX, normY));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _updateTouch(e.localPosition),
      onPointerMove: (e) => _updateTouch(e.localPosition),
      onPointerUp: (_) {
        setState(() => _dragOffset = Offset.zero);
        widget.onChanged(Offset.zero);
      },
      onPointerCancel: (_) {
        setState(() => _dragOffset = Offset.zero);
        widget.onChanged(Offset.zero);
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _ReferenceJoystickPainter(dragOffset: _dragOffset),
        ),
      ),
    );
  }
}

class _ReferenceJoystickPainter extends CustomPainter {
  final Offset dragOffset;

  _ReferenceJoystickPainter({required this.dragOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    // Outer dark ring (concentric base from reference image)
    final outerRing = Paint()
      ..color = const Color(0xFF2E2E2E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, outerRing);

    final outerRingBorder = Paint()
      ..color = const Color(0xFF383838)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, baseRadius, outerRingBorder);

    // Inner base bed
    final innerBed = Paint()
      ..color = const Color(0xFF242424)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius * 0.75, innerBed);

    // Moving Knob (medium gray with center pit from reference image)
    final knobCenter = center + dragOffset;
    final knobRadius = baseRadius * 0.44;

    final knobPaint = Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);

    final knobBorder = Paint()
      ..color = const Color(0xFF666666)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(knobCenter, knobRadius, knobBorder);

    // Subtle concave thumb well in center of knob
    final pitPaint = Paint()
      ..color = const Color(0xFF444444)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, knobRadius * 0.55, pitPaint);
  }

  @override
  bool shouldRepaint(covariant _ReferenceJoystickPainter oldDelegate) {
    return oldDelegate.dragOffset != dragOffset;
  }
}
