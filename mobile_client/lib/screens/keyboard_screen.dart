import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';

class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final ConnectionService _conn = ConnectionService();
  final TextEditingController _textCtrl = TextEditingController();

  // Active sticky modifier states
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _shiftActive = false;
  bool _winActive = false;

  void _sendKey(String key) {
    HapticFeedback.lightImpact();

    // Check if any sticky modifier is active
    final List<String> activeMods = [];
    if (_ctrlActive) activeMods.add('ctrl');
    if (_altActive) activeMods.add('alt');
    if (_shiftActive) activeMods.add('shift');
    if (_winActive) activeMods.add('win');

    if (activeMods.isNotEmpty) {
      activeMods.add(key);
      _conn.sendCombo(activeMods);
      // Auto reset sticky modifiers after single use
      setState(() {
        _ctrlActive = false;
        _altActive = false;
        _shiftActive = false;
        _winActive = false;
      });
    } else {
      _conn.sendKey(key, action: 'press');
    }
  }

  void _sendCombo(List<String> keys) {
    HapticFeedback.mediumImpact();
    _conn.sendCombo(keys);
  }

  void _onTextSubmitted(String val) {
    if (val.isNotEmpty) {
      _conn.sendText(val);
      _textCtrl.clear();
    }
  }

  Widget _buildModifierBtn(String label, String id, bool isActive, VoidCallback onToggle) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onToggle();
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFFFFFF) : const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive ? const Color(0xFFFFFFFF) : const Color(0xFF2C2C2C),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isActive)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF000000),
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF000000) : const Color(0xFFCCCCCC),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComboBtn(String label, List<String> combo) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: InkWell(
        onTap: () => _sendCombo(combo),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2E2E2E)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String label, String keyName, {double flex = 1, bool isSpecial = false}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: InkWell(
          onTap: () => _sendKey(keyName),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: isSpecial ? const Color(0xFF222222) : const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSpecial ? const Color(0xFF444444) : const Color(0xFF262626),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isSpecial ? const Color(0xFFFFFFFF) : const Color(0xFFDDDDDD),
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text Input Box for Direct Typing
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: Row(
              children: [
                const Icon(Icons.keyboard, color: Color(0xFF777777), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Type text here to stream directly to PC...',
                      hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: _onTextSubmitted,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFFFFFFFF), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _onTextSubmitted(_textCtrl.text),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // STICKY MODIFIERS ROW
          Row(
            children: [
              _buildModifierBtn('CTRL', 'ctrl', _ctrlActive, () => setState(() => _ctrlActive = !_ctrlActive)),
              _buildModifierBtn('ALT', 'alt', _altActive, () => setState(() => _altActive = !_altActive)),
              _buildModifierBtn('SHIFT', 'shift', _shiftActive, () => setState(() => _shiftActive = !_shiftActive)),
              _buildModifierBtn('WIN', 'win', _winActive, () => setState(() => _winActive = !_winActive)),
            ],
          ),

          const SizedBox(height: 10),

          // SHORTCUT COMBOS (ALT+TAB, WIN+TAB, ETC.)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF080808),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E1E1E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MULTI-KEY SHORTCUT COMBOS',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    _buildComboBtn('ALT + TAB', ['alt', 'tab']),
                    _buildComboBtn('WIN + TAB', ['win', 'tab']),
                    _buildComboBtn('WIN + D', ['win', 'd']),
                    _buildComboBtn('CTRL + C', ['ctrl', 'c']),
                    _buildComboBtn('CTRL + V', ['ctrl', 'v']),
                    _buildComboBtn('CTRL + Z', ['ctrl', 'z']),
                    _buildComboBtn('CTRL + Y', ['ctrl', 'y']),
                    _buildComboBtn('CTRL + A', ['ctrl', 'a']),
                    _buildComboBtn('CTRL + W', ['ctrl', 'w']),
                    _buildComboBtn('TASK MGR', ['ctrl', 'shift', 'esc']),
                    _buildComboBtn('ALT + F4', ['alt', 'f4']),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Core Navigation / Control Keys Row 1
          Row(
            children: [
              _buildKeyBtn('ESC', 'escape', isSpecial: true),
              _buildKeyBtn('TAB', 'tab'),
              _buildKeyBtn('BKSP', 'backspace', flex: 1.4, isSpecial: true),
              _buildKeyBtn('DEL', 'delete'),
              _buildKeyBtn('ENTER', 'enter', flex: 1.5, isSpecial: true),
            ],
          ),

          // Row 2: Space & Utility
          Row(
            children: [
              _buildKeyBtn('HOME', 'home'),
              _buildKeyBtn('END', 'end'),
              _buildKeyBtn('SPACE', 'space', flex: 2.2),
              _buildKeyBtn('PG UP', 'pageup'),
              _buildKeyBtn('PG DN', 'pagedown'),
            ],
          ),

          const SizedBox(height: 10),

          // Arrow keys cross & Functional Navigation
          Center(
            child: SizedBox(
              width: 170,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildArrowBtn('up', Icons.arrow_upward),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildArrowBtn('left', Icons.arrow_back),
                      const SizedBox(width: 4),
                      _buildArrowBtn('down', Icons.arrow_downward),
                      const SizedBox(width: 4),
                      _buildArrowBtn('right', Icons.arrow_forward),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Function Keys F1-F12
          const Text(
            'FUNCTION KEYS (F1 - F12)',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildKeyBtn('F1', 'f1'),
              _buildKeyBtn('F2', 'f2'),
              _buildKeyBtn('F3', 'f3'),
              _buildKeyBtn('F4', 'f4'),
              _buildKeyBtn('F5', 'f5'),
              _buildKeyBtn('F6', 'f6'),
            ],
          ),
          Row(
            children: [
              _buildKeyBtn('F7', 'f7'),
              _buildKeyBtn('F8', 'f8'),
              _buildKeyBtn('F9', 'f9'),
              _buildKeyBtn('F10', 'f10'),
              _buildKeyBtn('F11', 'f11'),
              _buildKeyBtn('F12', 'f12'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArrowBtn(String keyName, IconData icon) {
    return SizedBox(
      width: 52,
      height: 40,
      child: InkWell(
        onTap: () => _sendKey(keyName),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2E2E2E)),
          ),
          child: Icon(icon, color: const Color(0xFFFFFFFF), size: 18),
        ),
      ),
    );
  }
}
