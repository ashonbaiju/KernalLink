import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final ConnectionService _conn = ConnectionService();
  late double _sensitivity;
  late double _deadzone;

  @override
  void initState() {
    super.initState();
    _sensitivity = _conn.sensitivity;
    _deadzone = _conn.deadzone;
  }

  void _save() {
    _conn.sensitivity = _sensitivity;
    _conn.deadzone = _deadzone;
    _conn.saveSettings();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2E2E2E), width: 1.2),
      ),
      child: Container(
        width: 350,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONTROLS TUNING',
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF888888), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Trackpad & Stick Sensitivity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Motion Sensitivity',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                ),
                Text(
                  '${_sensitivity.toStringAsFixed(1)}x',
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFFFFFFF),
                inactiveTrackColor: const Color(0xFF262626),
                thumbColor: const Color(0xFFFFFFFF),
                overlayColor: const Color(0x33FFFFFF),
                trackHeight: 2.5,
              ),
              child: Slider(
                value: _sensitivity,
                min: 0.2,
                max: 3.0,
                divisions: 28,
                onChanged: (val) => setState(() => _sensitivity = val),
              ),
            ),

            const SizedBox(height: 12),

            // Stick Deadzone Filter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Joystick Deadzone',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                ),
                Text(
                  '${(_deadzone * 100).toInt()}%',
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFFFFFFF),
                inactiveTrackColor: const Color(0xFF262626),
                thumbColor: const Color(0xFFFFFFFF),
                overlayColor: const Color(0x33FFFFFF),
                trackHeight: 2.5,
              ),
              child: Slider(
                value: _deadzone,
                min: 0.0,
                max: 0.3,
                divisions: 30,
                onChanged: (val) => setState(() => _deadzone = val),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFFFFF),
                foregroundColor: const Color(0xFF000000),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
              ),
              child: const Text(
                'APPLY SETTINGS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
