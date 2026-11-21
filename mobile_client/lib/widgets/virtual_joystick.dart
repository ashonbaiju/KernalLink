import 'dart:math';
import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final double radius;
  final String label;
  final ValueChanged<Offset> onDirectionChanged;
  final VoidCallback? onStickClick;
  final double deadzone;
  final double sensitivity;

  const VirtualJoystick({
    super.key,
    this.radius = 65.0,
    required this.label,
    required this.onDirectionChanged,
    this.onStickClick,
    this.deadzone = 0.08,
    this.sensitivity = 1.0,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _dragPosition = Offset.zero;

  void _updatePosition(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = localPosition - center;
    final distance = delta.distance;
    final maxDist = widget.radius;

    Offset clampedDelta;
    if (distance > maxDist) {
      clampedDelta = Offset.fromDirection(delta.direction, maxDist);
    } else {
      clampedDelta = delta;
    }

    setState(() {
      _dragPosition = clampedDelta;
    });

    // Normalize: -1.0 to 1.0 (UP is positive Y in controller axes)
    double normX = clampedDelta.dx / maxDist;
    double normY = -clampedDelta.dy / maxDist;

    final normDist = sqrt(normX * normX + normY * normY);
    if (normDist < widget.deadzone) {
      normX = 0.0;
      normY = 0.0;
    } else {
      final factor = (normDist - widget.deadzone) / (1.0 - widget.deadzone);
      normX = (normX / normDist) * factor * widget.sensitivity;
      normY = (normY / normDist) * factor * widget.sensitivity;
      normX = normX.clamp(-1.0, 1.0);
      normY = normY.clamp(-1.0, 1.0);
    }

    widget.onDirectionChanged(Offset(normX, normY));
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    _updatePosition(event.localPosition, size);
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    _updatePosition(event.localPosition, size);
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _dragPosition = Offset.zero;
    });
    widget.onDirectionChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Listener(
            onPointerDown: (e) => _onPointerDown(e, Size(size, size)),
            onPointerMove: (e) => _onPointerMove(e, Size(size, size)),
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _onPointerUp(const PointerUpEvent()),
            child: CustomPaint(
              painter: _JoystickPainter(
                dragOffset: _dragPosition,
                radius: widget.radius,
                label: widget.label,
              ),
            ),
          ),
        ),
        if (widget.onStickClick != null) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: widget.onStickClick,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                border: Border.all(color: const Color(0xFF2E2E2E)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${widget.label} CLICK',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Color(0xFFCCCCCC),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset dragOffset;
  final double radius;
  final String label;

  _JoystickPainter({
    required this.dragOffset,
    required this.radius,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer base circle
    final basePaint = Paint()
      ..color = const Color(0xFF0A0A0A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, basePaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF262626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, borderPaint);

    // Center crosshairs
    final crosshairPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(center - Offset(radius * 0.7, 0), center + Offset(radius * 0.7, 0), crosshairPaint);
    canvas.drawLine(center - Offset(0, radius * 0.7), center + Offset(0, radius * 0.7), crosshairPaint);

    // Thumb stick knob
    final knobCenter = center + dragOffset;
    final knobRadius = radius * 0.42;

    final knobFill = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, knobRadius, knobFill);

    final knobBorder = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(knobCenter, knobRadius, knobBorder);

    // Inner knob dot
    final dotPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.dragOffset != dragOffset;
  }
}
