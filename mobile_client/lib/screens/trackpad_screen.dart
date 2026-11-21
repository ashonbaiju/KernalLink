import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';

enum KeyboardCategory { none, shortcuts, navigation, functionKeys }

class TrackpadScreen extends StatefulWidget {
  const TrackpadScreen({super.key});

  @override
  State<TrackpadScreen> createState() => _TrackpadScreenState();
}

class _TrackpadScreenState extends State<TrackpadScreen> {
  final ConnectionService _conn = ConnectionService();

  // Multi-touch tracking
  final Map<int, Offset> _activePointers = {};
  int _tapStartTime = 0;
  bool _hasMoved = false;

  // Pinch-to-zoom tracking
  double? _initialPinchDistance;
  double _lastPinchDistance = 0.0;
  int _lastZoomTime = 0;

  // Keyboard Visibility & Category Tab
  bool _showKeyboard = false;
  KeyboardCategory _activeCategory = KeyboardCategory.none;

  // Sticky Modifiers
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _shiftActive = false;
  bool _winActive = false;

  final TextEditingController _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // --- TOUCHPAD GESTURE HANDLERS ---
  void _onPointerDown(PointerDownEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_activePointers.length == 1) {
      _tapStartTime = DateTime.now().millisecondsSinceEpoch;
      _hasMoved = false;
      _initialPinchDistance = null;
    } else if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      _initialPinchDistance = (pts[0] - pts[1]).distance;
      _lastPinchDistance = _initialPinchDistance!;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_activePointers.containsKey(e.pointer)) {
      _activePointers[e.pointer] = e.localPosition;
    }

    if (_activePointers.length == 1) {
      // 1 Finger: Smooth cursor glide
      final dx = e.delta.dx;
      final dy = e.delta.dy;
      if (dx.abs() > 0.4 || dy.abs() > 0.4) {
        _hasMoved = true;
        _conn.sendMouseMove(dx, dy);
      }
    } else if (_activePointers.length == 2) {
      // 2 Fingers: Pinch-to-zoom vs 2-finger scroll
      final pts = _activePointers.values.toList();
      final currentDist = (pts[0] - pts[1]).distance;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (_initialPinchDistance != null) {
        final distDiff = currentDist - _lastPinchDistance;
        final totalDistDiff = (currentDist - _initialPinchDistance!).abs();

        if (totalDistDiff > 16) {
          if (distDiff.abs() > 14 && (now - _lastZoomTime > 50)) {
            _hasMoved = true;
            _lastZoomTime = now;
            if (distDiff > 0) {
              HapticFeedback.selectionClick();
              _conn.sendZoom('in');
            } else {
              HapticFeedback.selectionClick();
              _conn.sendZoom('out');
            }
            _lastPinchDistance = currentDist;
            return;
          }
        }
      }

      // Vertical 2-finger scroll
      final dy = e.delta.dy;
      if (dy.abs() > 0.8) {
        _hasMoved = true;
        _conn.sendMouseScroll((-dy * 16).toInt());
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final pointerCount = _activePointers.length;
    _activePointers.remove(e.pointer);
    _initialPinchDistance = null;

    final duration = DateTime.now().millisecondsSinceEpoch - _tapStartTime;
    if (!_hasMoved && duration < 250) {
      if (pointerCount == 1) {
        HapticFeedback.selectionClick();
        _conn.sendMouseClick('left');
      } else if (pointerCount == 2) {
        HapticFeedback.lightImpact();
        _conn.sendMouseClick('right');
      }
    }
  }

  // --- KEYBOARD ACTIONS ---
  void _sendKey(String key) {
    HapticFeedback.lightImpact();
    final List<String> activeMods = [];
    if (_ctrlActive) activeMods.add('ctrl');
    if (_altActive) activeMods.add('alt');
    if (_shiftActive) activeMods.add('shift');
    if (_winActive) activeMods.add('win');

    if (activeMods.isNotEmpty) {
      activeMods.add(key);
      _conn.sendCombo(activeMods);
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

  void _toggleCategory(KeyboardCategory cat) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeCategory = (_activeCategory == cat) ? KeyboardCategory.none : cat;
    });
  }

  // --- WIDGET BUILDERS: TOP BAR CONTROLS ---
  Widget _buildSegmentOption({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? Colors.black : const Color(0xFF9E9EAE),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.black : const Color(0xFFB0B0C0),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E28),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
    );
  }

  // --- WIDGET BUILDERS: KEYBOARD KEYS ---
  Widget _buildModifierBtn(String label, bool isActive, VoidCallback onToggle) {
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
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : const Color(0xFF14141C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive ? Colors.white : const Color(0xFF2E2E3E),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.black : const Color(0xFFDCDCE8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoreKey(String label, String keyName, {double flex = 1, bool isAction = false}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: InkWell(
          onTap: () => _sendKey(keyName),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: isAction ? const Color(0xFF222230) : const Color(0xFF14141C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isAction ? const Color(0xFF3E3E54) : const Color(0xFF282836),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required IconData icon,
    required KeyboardCategory category,
  }) {
    final bool isSelected = _activeCategory == category;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => _toggleCategory(category),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF282838) : const Color(0xFF121218),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.white : const Color(0xFF262634),
                width: isSelected ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? Colors.white : const Color(0xFF88889C),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF88889C),
                    fontSize: 9.5,
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

  Widget _buildComboBadge(String label, List<String> combo) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: InkWell(
        onTap: () => _sendCombo(combo),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF2C2C3E)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavKey(String label, String keyName, IconData icon) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () => _sendKey(keyName),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF161622),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2A2A3C)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- 1. MINIMAL HEADER BAR (Modern Segmented Switcher & Zoom) ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C10),
            border: Border(bottom: BorderSide(color: Color(0xFF1C1C26))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Segmented Switcher (Touchpad vs Keyboard)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF242432)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSegmentOption(
                      label: 'TOUCHPAD',
                      icon: Icons.touch_app_outlined,
                      isActive: !_showKeyboard,
                      onTap: () => setState(() => _showKeyboard = false),
                    ),
                    const SizedBox(width: 3),
                    _buildSegmentOption(
                      label: 'KEYBOARD',
                      icon: Icons.keyboard_outlined,
                      isActive: _showKeyboard,
                      onTap: () => setState(() => _showKeyboard = true),
                    ),
                  ],
                ),
              ),

              // Precision Zoom Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF242432)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildZoomBtn(Icons.zoom_out, () => _conn.sendZoom('out')),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        'ZOOM',
                        style: TextStyle(
                          color: Color(0xFF8E8EA2),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    _buildZoomBtn(Icons.zoom_in, () => _conn.sendZoom('in')),
                  ],
                ),
              ),
            ],
          ),
        ),

        // --- 2. MINIMALIST KEYBOARD DRAWER (Appears on Demand) ---
        if (_showKeyboard)
          Container(
            color: const Color(0xFF08080C),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Clean Input Capsule
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101016),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF262634)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note, color: Color(0xFF707084), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 11.5),
                          decoration: const InputDecoration(
                            hintText: 'Type text here to stream directly to PC...',
                            hintStyle: TextStyle(color: Color(0xFF505062), fontSize: 10.5),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: _onTextSubmitted,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _onTextSubmitted(_textCtrl.text),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // Sticky Modifiers Row
                Row(
                  children: [
                    _buildModifierBtn('CTRL', _ctrlActive, () => setState(() => _ctrlActive = !_ctrlActive)),
                    _buildModifierBtn('ALT', _altActive, () => setState(() => _altActive = !_altActive)),
                    _buildModifierBtn('SHIFT', _shiftActive, () => setState(() => _shiftActive = !_shiftActive)),
                    _buildModifierBtn('WIN', _winActive, () => setState(() => _winActive = !_winActive)),
                  ],
                ),

                const SizedBox(height: 6),

                // Core Primary Keys Row
                Row(
                  children: [
                    _buildCoreKey('ESC', 'escape', isAction: true),
                    _buildCoreKey('TAB', 'tab'),
                    _buildCoreKey('SPACE', 'space', flex: 1.8),
                    _buildCoreKey('BKSP', 'backspace', flex: 1.2, isAction: true),
                    _buildCoreKey('ENTER', 'enter', flex: 1.3, isAction: true),
                  ],
                ),

                const SizedBox(height: 6),

                // Clean Category Tab Selectors
                Row(
                  children: [
                    _buildCategoryPill(
                      label: 'SHORTCUTS',
                      icon: Icons.bolt,
                      category: KeyboardCategory.shortcuts,
                    ),
                    _buildCategoryPill(
                      label: 'ARROWS',
                      icon: Icons.navigation_outlined,
                      category: KeyboardCategory.navigation,
                    ),
                    _buildCategoryPill(
                      label: 'FUNCTION',
                      icon: Icons.grid_view_outlined,
                      category: KeyboardCategory.functionKeys,
                    ),
                  ],
                ),

                // Tab Content Panel (Collapsible)
                if (_activeCategory != KeyboardCategory.none) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101018),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF222232)),
                    ),
                    child: Column(
                      children: [
                        if (_activeCategory == KeyboardCategory.shortcuts)
                          Wrap(
                            children: [
                              _buildComboBadge('ALT + TAB', ['alt', 'tab']),
                              _buildComboBadge('WIN + TAB', ['win', 'tab']),
                              _buildComboBadge('WIN + D', ['win', 'd']),
                              _buildComboBadge('CTRL + C', ['ctrl', 'c']),
                              _buildComboBadge('CTRL + V', ['ctrl', 'v']),
                              _buildComboBadge('CTRL + Z', ['ctrl', 'z']),
                              _buildComboBadge('CTRL + Y', ['ctrl', 'y']),
                              _buildComboBadge('CTRL + A', ['ctrl', 'a']),
                              _buildComboBadge('CTRL + W', ['ctrl', 'w']),
                              _buildComboBadge('TASK MGR', ['ctrl', 'shift', 'esc']),
                              _buildComboBadge('ALT + F4', ['alt', 'f4']),
                            ],
                          ),

                        if (_activeCategory == KeyboardCategory.navigation)
                          Column(
                            children: [
                              Row(
                                children: [
                                  _buildNavKey('HOME', 'home', Icons.first_page),
                                  _buildNavKey('UP', 'up', Icons.arrow_upward),
                                  _buildNavKey('END', 'end', Icons.last_page),
                                  _buildNavKey('PG UP', 'pageup', Icons.vertical_align_top),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  _buildNavKey('LEFT', 'left', Icons.arrow_back),
                                  _buildNavKey('DOWN', 'down', Icons.arrow_downward),
                                  _buildNavKey('RIGHT', 'right', Icons.arrow_forward),
                                  _buildNavKey('PG DN', 'pagedown', Icons.vertical_align_bottom),
                                ],
                              ),
                            ],
                          ),

                        if (_activeCategory == KeyboardCategory.functionKeys)
                          Column(
                            children: [
                              Row(
                                children: [
                                  _buildCoreKey('F1', 'f1'),
                                  _buildCoreKey('F2', 'f2'),
                                  _buildCoreKey('F3', 'f3'),
                                  _buildCoreKey('F4', 'f4'),
                                  _buildCoreKey('F5', 'f5'),
                                  _buildCoreKey('F6', 'f6'),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  _buildCoreKey('F7', 'f7'),
                                  _buildCoreKey('F8', 'f8'),
                                  _buildCoreKey('F9', 'f9'),
                                  _buildCoreKey('F10', 'f10'),
                                  _buildCoreKey('F11', 'f11'),
                                  _buildCoreKey('F12', 'f12'),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

        if (_showKeyboard)
          const Divider(color: Color(0xFF1A1A24), height: 1),

        // --- 3. UNIBODY PRECISION TRACKPAD DECK ---
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF20202C)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: [
                  // Upper Interactive Touchpad Area
                  Expanded(
                    child: Row(
                      children: [
                        // Main Gesture Surface
                        Expanded(
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: (e) => _activePointers.remove(e.pointer),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF12121A),
                                          border: Border.all(color: const Color(0xFF222232)),
                                        ),
                                        child: const Icon(
                                          Icons.touch_app_outlined,
                                          color: Color(0xFF6E6E84),
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'PRECISION TOUCHPAD',
                                        style: TextStyle(
                                          color: Color(0xFF88889C),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      const Text(
                                        '1-Tap: Left Click   ·   2-Tap: Right Click   ·   Pinch: Zoom',
                                        style: TextStyle(
                                          color: Color(0xFF4C4C5E),
                                          fontSize: 9,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Integrated Sleek Vertical Scroll Channel
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerMove: (e) {
                            final dy = e.delta.dy;
                            if (dy.abs() > 0.4) {
                              _conn.sendMouseScroll((-dy * 18).toInt());
                            }
                          },
                          child: Container(
                            width: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F0F16),
                              border: Border(
                                left: BorderSide(color: Color(0xFF1E1E2A)),
                              ),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.swap_vert, color: Color(0xFF6E6E82), size: 18),
                                SizedBox(height: 4),
                                Text(
                                  'SCROLL',
                                  style: TextStyle(
                                    color: Color(0xFF5A5A6C),
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
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

                  // Integrated Bottom Physical Click Bar (Laptop Unibody Style)
                  Container(
                    height: 50,
                    decoration: const BoxDecoration(
                      color: Color(0xFF121218),
                      border: Border(
                        top: BorderSide(color: Color(0xFF222230)),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Click Zone (Wide)
                        Expanded(
                          flex: 10,
                          child: _UnibodyClickBtn(
                            label: 'LEFT CLICK',
                            button: 'left',
                            onDown: () {
                              HapticFeedback.lightImpact();
                              _conn.sendMouseClick('left', action: 'down');
                            },
                            onUp: () => _conn.sendMouseClick('left', action: 'up'),
                          ),
                        ),

                        // Center Divider with Middle Click Anchor
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _conn.sendMouseClick('middle');
                          },
                          child: Container(
                            width: 44,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFF161620),
                              border: Border.symmetric(
                                vertical: BorderSide(color: Color(0xFF262636)),
                              ),
                            ),
                            child: const Icon(
                              Icons.adjust,
                              color: Color(0xFF8E8EA2),
                              size: 16,
                            ),
                          ),
                        ),

                        // Right Click Zone (Wide)
                        Expanded(
                          flex: 10,
                          child: _UnibodyClickBtn(
                            label: 'RIGHT CLICK',
                            button: 'right',
                            onDown: () {
                              HapticFeedback.lightImpact();
                              _conn.sendMouseClick('right', action: 'down');
                            },
                            onUp: () => _conn.sendMouseClick('right', action: 'up'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Sleek unibody tactile button with instant inverted press illumination
class _UnibodyClickBtn extends StatefulWidget {
  final String label;
  final String button;
  final VoidCallback onDown;
  final VoidCallback onUp;

  const _UnibodyClickBtn({
    required this.label,
    required this.button,
    required this.onDown,
    required this.onUp,
  });

  @override
  State<_UnibodyClickBtn> createState() => _UnibodyClickBtnState();
}

class _UnibodyClickBtnState extends State<_UnibodyClickBtn> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() => _isDown = true);
        widget.onDown();
      },
      onPointerUp: (_) {
        setState(() => _isDown = false);
        widget.onUp();
      },
      onPointerCancel: (_) {
        setState(() => _isDown = false);
        widget.onUp();
      },
      child: Container(
        color: _isDown ? Colors.white : Colors.transparent,
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: _isDown ? Colors.black : const Color(0xFFCCCCCC),
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
