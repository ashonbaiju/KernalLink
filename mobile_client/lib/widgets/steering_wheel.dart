import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SteeringWheel extends StatefulWidget {
  final double size;
  final ValueChanged<double> onAngleChanged; // Normalized -1.0 (Full Left) to +1.0 (Full Right)
  final double maxAngleDegrees; // e.g. 90.0 or 120.0

  const SteeringWheel({
    super.key,
    this.size = 220.0,
    required this.onAngleChanged,
    this.maxAngleDegrees = 90.0,
  });

  @override
  State<SteeringWheel> createState() => _SteeringWheelState();
}

class _SteeringWheelState extends State<SteeringWheel> with SingleTickerProviderStateMixin {
  double _currentAngleDeg = 0.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;
  double _lastTouchAngle = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _springAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    )..addListener(() {
        if (!_isDragging) {
          setState(() {
            _currentAngleDeg = _springAnimation.value;
          });
          _notifyAngle();
        }
      });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _notifyAngle() {
    // Clamped between -maxAngleDegrees and +maxAngleDegrees
    final norm = (_currentAngleDeg / widget.maxAngleDegrees).clamp(-1.0, 1.0);
    widget.onAngleChanged(norm);
  }

  void _onPointerDown(PointerDownEvent e) {
    _springController.stop();
    _isDragging = true;
    final center = Offset(widget.size / 2, widget.size / 2);
    final touch = e.localPosition - center;
    _lastTouchAngle = atan2(touch.dy, touch.dx);
    HapticFeedback.selectionClick();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_isDragging) return;
    final center = Offset(widget.size / 2, widget.size / 2);
    final touch = e.localPosition - center;
    final currentTouchAngle = atan2(touch.dy, touch.dx);

    double deltaAngle = currentTouchAngle - _lastTouchAngle;
    // Normalize delta between -pi and pi
    if (deltaAngle > pi) deltaAngle -= 2 * pi;
    if (deltaAngle < -pi) deltaAngle += 2 * pi;

    final degDelta = deltaAngle * (180.0 / pi);
    setState(() {
      _currentAngleDeg = (_currentAngleDeg + degDelta).clamp(-widget.maxAngleDegrees, widget.maxAngleDegrees);
      _lastTouchAngle = currentTouchAngle;
    });

    _notifyAngle();
  }

  void _onPointerUp(PointerUpEvent e) {
    _isDragging = false;
    // Animate smoothly back to center (0 degrees)
    _springAnimation = Tween<double>(begin: _currentAngleDeg, end: 0.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    _springController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Steering Angle Readout
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rotate_right, color: Color(0xFF888888), size: 14),
              const SizedBox(width: 4),
              Text(
                'STEER: ${_currentAngleDeg.toStringAsFixed(0)}°  (${(_currentAngleDeg / widget.maxAngleDegrees * 100).toInt()}%)',
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Interactive Wheel
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: (_) => _onPointerUp(const PointerUpEvent()),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Transform.rotate(
              angle: _currentAngleDeg * (pi / 180.0),
              child: CustomPaint(
                painter: _SteeringWheelPainter(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SteeringWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 4;
    final innerRadius = outerRadius - 22;

    // Outer Rim
    final rimPaint = Paint()
      ..color = const Color(0xFF0E0E0E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, rimPaint);

    final rimBorder = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, outerRadius, rimBorder);

    // Inner Rim Cutout
    final innerHole = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerHole);

    final innerBorder = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerRadius, innerBorder);

    // Top Center Alignment Marker (12 o'clock stripe)
    final markerPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final markerRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - outerRadius + 11),
      width: 14,
      height: 22,
    );
    canvas.drawRect(markerRect, markerPaint);

    // Spokes (Horizontal Left, Right, and Vertical Down)
    final spokePaint = Paint()
      ..color = const Color(0xFF1F1F1F)
      ..style = PaintingStyle.fill;
    final spokeBorder = Paint()
      ..color = const Color(0xFF444444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Left Spoke
    final leftSpoke = Rect.fromLTRB(center.dx - innerRadius, center.dy - 12, center.dx - 24, center.dy + 12);
    canvas.drawRect(leftSpoke, spokePaint);
    canvas.drawRect(leftSpoke, spokeBorder);

    // Right Spoke
    final rightSpoke = Rect.fromLTRB(center.dx + 24, center.dy - 12, center.dx + innerRadius, center.dy + 12);
    canvas.drawRect(rightSpoke, spokePaint);
    canvas.drawRect(rightSpoke, spokeBorder);

    // Bottom Spoke
    final bottomSpoke = Rect.fromLTRB(center.dx - 12, center.dy + 24, center.dx + 12, center.dy + innerRadius);
    canvas.drawRect(bottomSpoke, spokePaint);
    canvas.drawRect(bottomSpoke, spokeBorder);

    // Center Hub
    final hubFill = Paint()
      ..color = const Color(0xFF141414)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 28, hubFill);

    final hubBorder = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 28, hubBorder);

    // Center Icon / Emblem
    final emblemPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, emblemPaint);
  }

  @override
  bool shouldRepaint(covariant _SteeringWheelPainter oldDelegate) => false;
}
