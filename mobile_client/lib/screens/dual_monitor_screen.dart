import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import 'connection_dialog.dart';

class DualMonitorScreen extends StatefulWidget {
  const DualMonitorScreen({super.key});

  @override
  State<DualMonitorScreen> createState() => _DualMonitorScreenState();
}

class _DualMonitorScreenState extends State<DualMonitorScreen> {
  final ConnectionService _conn = ConnectionService();

  int _selectedMonitorIndex = 0;
  int _fps = 60;
  int _quality = 80;
  double _scale = 1.0;
  BoxFit _boxFit = BoxFit.fill; // Default: Fill 100% of phone screen edge-to-edge (no black side bars)
  bool _directTouch = true;
  bool _zoomEnabled = false;
  bool _showControls = true;
  bool _showKeyboard = false;

  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  final TransformationController _transformCtrl = TransformationController();

  // Ultra-low latency GPU frame buffer
  ui.Image? _decodedImage;
  bool _isDecoding = false;
  Uint8List? _pendingFrame;

  @override
  void initState() {
    super.initState();

    _conn.addListener(_onConnChanged);
    _conn.monitorsNotifier.addListener(_onMonitorsChanged);
    _conn.vddStatusNotifier.addListener(_onVddChanged);
    _conn.screenFrameNotifier.addListener(_onFrameReceived);
    _conn.streamConfigNotifier.addListener(_onStreamConfigChanged);

    // Force landscape-only — PC monitor is always wider than tall
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Immersive full-screen (hide status/nav bars)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Strictly On-Demand: Query PC monitors & VDD status, but do NOT auto-start streaming
    if (_conn.isConnected) {
      _conn.requestMonitors();
    }
  }

  void _onFrameReceived() {
    final frame = _conn.screenFrameNotifier.value;
    if (frame == null) {
      if (_decodedImage != null) {
        _decodedImage?.dispose();
        _decodedImage = null;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_isDecoding) {
      // Keep only freshest frame, drop any stale queued frame
      _pendingFrame = frame;
      return;
    }
    _decodeFrame(frame);
  }

  void _decodeFrame(Uint8List frame) async {
    _isDecoding = true;
    try {
      final codec = await ui.instantiateImageCodec(frame);
      final frameInfo = await codec.getNextFrame();
      final old = _decodedImage;
      if (mounted) {
        setState(() {
          _decodedImage = frameInfo.image;
        });
      } else {
        frameInfo.image.dispose();
      }
      old?.dispose(); // Reclaim GPU texture memory instantly
    } catch (_) {
    } finally {
      _isDecoding = false;
      if (_pendingFrame != null) {
        final next = _pendingFrame!;
        _pendingFrame = null;
        _decodeFrame(next);
      }
    }
  }

  void _onConnChanged() {
    if (_conn.isConnected) {
      _conn.requestMonitors();
    }
    if (mounted) setState(() {});
  }

  void _onVddChanged() {
    if (mounted) setState(() {});
  }

  void _onMonitorsChanged() {
    final monitors = _conn.monitorsNotifier.value;
    if (monitors.length > 1) {
      // Auto-select extended screen (non-primary) if on primary
      final extMon = monitors.firstWhere((m) => m['primary'] == false, orElse: () => monitors[0]);
      final extIdx = extMon['index'] ?? 0;
      if (_selectedMonitorIndex == 0 && extIdx != 0) {
        setState(() {
          _selectedMonitorIndex = extIdx;
        });
        _applyStreamSettings();
      }
    } else if (monitors.length <= 1 && _selectedMonitorIndex != 0) {
      // Extended monitor removed on PC -> revert to primary monitor
      setState(() {
        _selectedMonitorIndex = 0;
      });
      _applyStreamSettings();
    }
    if (mounted) setState(() {});
  }

  void _onStreamConfigChanged() {
    final cfg = _conn.streamConfigNotifier.value;
    if (cfg.isEmpty) return;
    bool changed = false;
    if (cfg.containsKey('fps') && cfg['fps'] != null) {
      final int newFps = (cfg['fps'] as num).toInt();
      if (newFps != _fps) {
        _fps = newFps;
        changed = true;
      }
    }
    if (cfg.containsKey('quality') && cfg['quality'] != null) {
      final int newQ = (cfg['quality'] as num).toInt();
      if (newQ != _quality) {
        _quality = newQ;
        changed = true;
      }
    }
    if (cfg.containsKey('scale') && cfg['scale'] != null) {
      final double newScale = (cfg['scale'] as num).toDouble();
      if ((newScale - _scale).abs() > 0.05) {
        _scale = newScale;
        changed = true;
      }
    }
    if (cfg.containsKey('monitor') && cfg['monitor'] != null) {
      final int newMon = (cfg['monitor'] as num).toInt();
      if (newMon != _selectedMonitorIndex) {
        _selectedMonitorIndex = newMon;
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PC Mode: $_fps Hz · Q$_quality · Display ${_selectedMonitorIndex + 1}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  @override
  void dispose() {
    _conn.removeListener(_onConnChanged);
    _conn.monitorsNotifier.removeListener(_onMonitorsChanged);
    _conn.vddStatusNotifier.removeListener(_onVddChanged);
    _conn.screenFrameNotifier.removeListener(_onFrameReceived);
    _conn.streamConfigNotifier.removeListener(_onStreamConfigChanged);
    _decodedImage?.dispose();
    _decodedImage = null;

    // CRUCIAL: Immediately stop screen capture and streaming on PC when exiting
    _conn.stopScreenStream();

    // Restore portrait and landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _textCtrl.dispose();
    _textFocus.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _startStream() {
    _conn.startScreenStream(
      monitor: _selectedMonitorIndex,
      quality: _quality,
      fps: _fps,
      scale: _scale,
    );
  }

  void _applyStreamSettings() {
    if (_conn.isConnected) {
      _startStream();
    }
  }

  // Maps touch position on widget to normalized 0.0 - 1.0 image coordinates with exact alignment
  void _handleTouch(Offset globalPos, String action, BuildContext imgContext, {String button = 'left', int deltaY = 0}) {
    final RenderBox? box = imgContext.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(globalPos);
    final widgetSize = box.size;

    if (widgetSize.width <= 0 || widgetSize.height <= 0) return;

    // Use exact dimensions from live decoded hardware image or active monitor
    final monitors = _conn.monitorsNotifier.value;
    double imgW = _decodedImage?.width.toDouble() ?? 1600.0;
    double imgH = _decodedImage?.height.toDouble() ?? 720.0;
    if (_decodedImage == null && _selectedMonitorIndex < monitors.length) {
      imgW = (monitors[_selectedMonitorIndex]['width'] as num?)?.toDouble() ?? 1600.0;
      imgH = (monitors[_selectedMonitorIndex]['height'] as num?)?.toDouble() ?? 720.0;
    }

    final fittedSizes = applyBoxFit(_boxFit, Size(imgW, imgH), widgetSize);
    final destSize = fittedSizes.destination;
    final dxOffset = (widgetSize.width - destSize.width) / 2.0;
    final dyOffset = (widgetSize.height - destSize.height) / 2.0;

    final normX = ((localPos.dx - dxOffset) / destSize.width).clamp(0.0, 1.0);
    final normY = ((localPos.dy - dyOffset) / destSize.height).clamp(0.0, 1.0);

    _conn.sendScreenTouch(
      action: action,
      normX: normX,
      normY: normY,
      monitor: _selectedMonitorIndex,
      button: button,
      deltaY: deltaY,
    );
  }

  void _showDualMonitorHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181824),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333348)),
        ),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 20),
            SizedBox(width: 10),
            Text(
              'Why is Win + P Mirroring?',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Windows Operating System Requirement:',
                style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
              SizedBox(height: 4),
              Text(
                'In Windows 10 & 11, pressing Win + P to "Extend" requires at least TWO active displays detected by your graphics card. If only your laptop screen is detected, Windows cannot extend into thin air, so it automatically duplicates (mirrors).',
                style: TextStyle(color: Color(0xFFC8C8DC), fontSize: 11, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'How to activate true Extend (Dual Screen):',
                style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
              SizedBox(height: 6),
              Text(
                '1. Connect Spacedesk App Once:\n'
                '   Open the Spacedesk Viewer app on your phone. Connecting to your PC creates a virtual Display 2 in Windows. Once created, Windows Extend works!\n\n'
                '2. Install Virtual Display Driver (VDD):\n'
                '   Add an open-source virtual monitor driver (IddCx) to give Windows a permanent 2nd display.\n\n'
                '3. Once Windows sees 2 displays, this app will automatically switch to your 2nd screen!',
                style: TextStyle(color: Color(0xFFE0E0EE), fontSize: 10.5, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _conn.controlVirtualDisplay('install');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Look at PC screen and click "Yes" on Windows prompt!'),
                  backgroundColor: Color(0xFF1E3A2E),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.black),
            child: const Text('CREATE DISPLAY 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _conn.controlSpacedesk('open_display_settings');
            },
            child: const Text('WIN DISPLAY SETTINGS', style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE', style: TextStyle(color: Color(0xFF9E9EAE), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _openSpacedeskConsoleSheet() {
    _conn.requestMonitors();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final monitors = _conn.monitorsNotifier.value;
            final spacedesk = _conn.spacedeskStatusNotifier.value;
            final bool sdRunning = spacedesk['running'] == true;
            final bool sdInstalled = spacedesk['installed'] == true;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF282836),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.settings_input_composite, color: Color(0xFF60A5FA), size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'SPACEDESK DRIVER CONSOLE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF888899), size: 18),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Spacedesk Service Status Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E28),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sdRunning ? const Color(0xFF10B981).withAlpha(100) : const Color(0xFF323244),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: sdRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sdRunning ? 'Spacedesk Service: ACTIVE' : (sdInstalled ? 'Spacedesk Service: STOPPED' : 'Spacedesk Driver: NOT FOUND'),
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sdRunning
                                        ? 'Port 28252 Listening · Virtual Display IDD Ready'
                                        : (sdInstalled ? 'Tap START to activate secondary virtual display' : 'Install Spacedesk Driver on PC for extended display'),
                                    style: const TextStyle(color: Color(0xFF88889A), fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            if (sdInstalled)
                              ElevatedButton(
                                onPressed: () {
                                  _conn.controlSpacedesk(sdRunning ? 'stop' : 'start');
                                  Future.delayed(const Duration(milliseconds: 900), () {
                                    setSheetState(() {});
                                    setState(() {});
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: sdRunning ? const Color(0xFF3F1D1D) : const Color(0xFF064E3B),
                                  foregroundColor: sdRunning ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(sdRunning ? 'STOP' : 'START', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Single Monitor Warning Banner
                      if (monitors.length <= 1)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF261E14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD97706).withAlpha(120)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Only 1 Display Detected (Mirroring Mode)',
                                      style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Windows requires a 2nd display adapter to activate Extend mode (Win + P). Tap below to create virtual Display 2 on your PC:',
                                      style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 9.5),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        _conn.controlVirtualDisplay('install');
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Look at PC screen and click "Yes" on the Windows prompt!'),
                                            backgroundColor: Color(0xFF1E3A2E),
                                            duration: Duration(seconds: 4),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.add_to_queue, size: 14),
                                      label: const Text('CREATE DISPLAY 2 (VIRTUAL MONITOR)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () {
                                        Navigator.of(ctx).pop();
                                        _showDualMonitorHelpDialog();
                                      },
                                      child: const Text(
                                        'Why is Win+P mirroring? Tap for info →',
                                        style: TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Windows Multi-Display Projection Modes
                      const Text(
                        'WINDOWS DISPLAY PROJECTION (WIN + P)',
                        style: TextStyle(color: Color(0xFF888899), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _conn.setWindowsDisplayMode('extend');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Switched to Extend Displays mode'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: const Icon(Icons.splitscreen, size: 13, color: Color(0xFF60A5FA)),
                              label: const Text('EXTEND', style: TextStyle(fontSize: 10, color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF282838)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _conn.setWindowsDisplayMode('clone');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Switched to Duplicate (Clone) mode'), duration: Duration(seconds: 1)),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 13, color: Color(0xFF34D399)),
                              label: const Text('DUPLICATE', style: TextStyle(fontSize: 10, color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF282838)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _conn.controlSpacedesk('launch_console');
                              },
                              icon: const Icon(Icons.launch, size: 13, color: Color(0xFFFBBF24)),
                              label: const Text('CONSOLE', style: TextStyle(fontSize: 10, color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF282838)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _conn.controlSpacedesk('open_display_settings');
                              },
                              icon: const Icon(Icons.settings, size: 13, color: Color(0xFFA78BFA)),
                              label: const Text('SETTINGS', style: TextStyle(fontSize: 10, color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF282838)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Phone 1600x720 Native Resolution Optimizer Banner
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16253A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2563EB).withAlpha(150)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.screen_lock_landscape, color: Color(0xFF60A5FA), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'PHONE NATIVE: 1600 × 720 (20:9)',
                                    style: TextStyle(color: Color(0xFF93C5FD), fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'For razor-sharp text and zero stretching, choose 1600x720 in Windows Display Settings.',
                                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                _conn.controlSpacedesk('open_display_settings');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Windows Display Settings opened! Click Display 2 -> Resolution -> choose 1600x720.'),
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('OPEN PC SETTINGS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),

                      // Select Target Monitor
                      const Text(
                        'SELECT MONITOR TO STREAM',
                        style: TextStyle(color: Color(0xFF888899), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 6),
                      if (monitors.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFF1E1E28), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Display 1 (Main Laptop 1920x1080)', style: TextStyle(color: Colors.white, fontSize: 11)),
                        )
                      else
                        Column(
                          children: monitors.map((m) {
                            final idx = m['index'] ?? 0;
                            final name = m['name'] ?? 'Display $idx';
                            final w = m['width'] ?? 0;
                            final h = m['height'] ?? 0;
                            final bool isSel = idx == _selectedMonitorIndex;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedMonitorIndex = idx;
                                  });
                                  setSheetState(() {});
                                  _applyStreamSettings();
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF242C3D) : const Color(0xFF1A1A24),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel ? const Color(0xFF3B82F6) : const Color(0xFF2A2A38),
                                      width: isSel ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                                        color: isSel ? const Color(0xFF60A5FA) : const Color(0xFF666677),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$name (${w}x$h)',
                                          style: TextStyle(
                                            color: isSel ? Colors.white : const Color(0xFFC0C0D0),
                                            fontSize: 11.5,
                                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 14),

                      // Quality & Performance Controls
                      const Text(
                        'STREAM QUALITY & PERFORMANCE',
                        style: TextStyle(color: Color(0xFF888899), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildChoiceChip(
                              label: '1080p ULTRA',
                              sub: '60 FPS · Native (Best)',
                              selected: _scale == 1.0 && _fps == 60 && _quality == 80,
                              onTap: () {
                                setState(() {
                                  _scale = 1.0;
                                  _fps = 60;
                                  _quality = 80;
                                });
                                setSheetState(() {});
                                _applyStreamSettings();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildChoiceChip(
                              label: '120 FPS PRO',
                              sub: 'Zero Latency Gaming',
                              selected: _fps == 120,
                              onTap: () {
                                setState(() {
                                  _scale = 1.0;
                                  _fps = 120;
                                  _quality = 75;
                                });
                                setSheetState(() {});
                                _applyStreamSettings();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildChoiceChip(
                              label: 'CRISP RETINA',
                              sub: '90% Q Text Clarity',
                              selected: _quality == 90,
                              onTap: () {
                                setState(() {
                                  _scale = 1.0;
                                  _fps = 60;
                                  _quality = 90;
                                });
                                setSheetState(() {});
                                _applyStreamSettings();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required String sub,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF181822),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF3B82F6) : const Color(0xFF282836),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB0B0C0),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                color: selected ? const Color(0xFF93C5FD) : const Color(0xFF6B7280),
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickKeyButton(String label, String keyName) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: const Color(0xFF22222E),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.lightImpact();
            _conn.sendKey(keyName, action: 'press');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisplayLaunchHub() {
    final vdd = _conn.vddStatusNotifier.value;
    final bool vddInstalled = vdd['installed'] == true;
    final String connType = _conn.address.startsWith('127.0.0.1') ? 'USB CABLE' : 'WI-FI';

    return SafeArea(
      child: Container(
        color: const Color(0xFF09090C),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1C1C24), width: 1.0)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14141A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, color: Color(0xFFCCCCCC), size: 14),
                          SizedBox(width: 4),
                          Text('EXIT', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'DISPLAY STREAMING HUB',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14141A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$connType  ·  ${_conn.latencyMs}ms',
                          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Monitor Choice & Driver On-Demand Card
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'CHOOSE DISPLAY',
                            style: TextStyle(
                              color: Color(0xFF71717A),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Option 1: Primary Screen (Mirror) - Zero Driver Required!
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedMonitorIndex = 0);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _selectedMonitorIndex == 0 ? const Color(0xFF182030) : const Color(0xFF121216),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedMonitorIndex == 0 ? Colors.white : const Color(0xFF27272A),
                                  width: _selectedMonitorIndex == 0 ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedMonitorIndex == 0 ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: _selectedMonitorIndex == 0 ? Colors.white : const Color(0xFF71717A),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Display 1: Primary Screen (Mirror)',
                                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF064E3B),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'NO DRIVER REQUIRED',
                                                style: TextStyle(color: Color(0xFF34D399), fontSize: 8.5, fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Mirrors PC main display via Desktop Duplication API with hardware GPU acceleration.',
                                          style: TextStyle(color: Color(0xFF71717A), fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Option 2: Virtual Extended Display (1600x720)
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedMonitorIndex = 1);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _selectedMonitorIndex > 0 ? const Color(0xFF182030) : const Color(0xFF121216),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedMonitorIndex > 0 ? Colors.white : const Color(0xFF27272A),
                                  width: _selectedMonitorIndex > 0 ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedMonitorIndex > 0 ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: _selectedMonitorIndex > 0 ? Colors.white : const Color(0xFF71717A),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Display 2: Virtual Extended Display',
                                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: vddInstalled ? const Color(0xFF064E3B) : const Color(0xFF3B2710),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                vddInstalled ? 'DRIVER READY' : 'DRIVER ON DEMAND',
                                                style: TextStyle(
                                                  color: vddInstalled ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Independent 2nd Windows monitor (1600x720) matched to phone aspect ratio.',
                                          style: TextStyle(color: Color(0xFF71717A), fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Driver Notice / Install On-Demand Card
                          if (!vddInstalled && _selectedMonitorIndex > 0)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E170E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD97706).withAlpha(120)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Color(0xFFFBBF24), size: 16),
                                      SizedBox(width: 8),
                                      Text(
                                        'DRIVER REQUIRED FOR EXTENDED 2ND MONITOR',
                                        style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Windows requires the Virtual Display Driver (IddCx) so your GPU detects a second screen. You can stream Display 1 (Mirror) with zero drivers, or click below to install.',
                                    style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 9.5),
                                  ),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () {
                                      HapticFeedback.heavyImpact();
                                      _conn.controlVirtualDisplay('install');
                                      _conn.setWindowsDisplayMode('extend');
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Installing driver on PC... Click "Yes" on Windows prompt!'),
                                          backgroundColor: Color(0xFF1E3A2E),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'INSTALL VIRTUAL DISPLAY DRIVER ON PC',
                                        style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right Column: Performance, Fit, & START Button
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'STREAM PERFORMANCE',
                            style: TextStyle(
                              color: Color(0xFF71717A),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // FPS Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildChoiceChip(
                                  label: '60 FPS',
                                  sub: 'Native (Best)',
                                  selected: _fps == 60,
                                  onTap: () => setState(() => _fps = 60),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildChoiceChip(
                                  label: '120 FPS',
                                  sub: 'Pro Gaming',
                                  selected: _fps == 120,
                                  onTap: () => setState(() => _fps = 120),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildChoiceChip(
                                  label: '30 FPS',
                                  sub: 'Eco Mode',
                                  selected: _fps == 30,
                                  onTap: () => setState(() => _fps = 30),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Quality & Fit Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildChoiceChip(
                                  label: _quality == 80 ? '80% BALANCED' : '100% ULTRA',
                                  sub: 'Stream Quality',
                                  selected: true,
                                  onTap: () {
                                    setState(() => _quality = (_quality == 80 ? 100 : 80));
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildChoiceChip(
                                  label: _boxFit == BoxFit.fill ? 'FULL SCREEN' : 'FIT ASPECT',
                                  sub: 'Screen Scaling',
                                  selected: true,
                                  onTap: () {
                                    setState(() => _boxFit = (_boxFit == BoxFit.fill ? BoxFit.contain : BoxFit.fill));
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // BIG START DISPLAY STREAM BUTTON
                          InkWell(
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              _startStream();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.white24,
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow, color: Colors.black, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'START DISPLAY STREAM',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isConn = _conn.isConnected;

    if (!isConn) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              const Text(
                'NOT CONNECTED TO PC',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              const SizedBox(height: 6),
              const Text(
                'Please connect to PC via USB Cable or Wi-Fi to view display',
                style: TextStyle(color: Color(0xFF888899), fontSize: 11),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const ConnectionDialog(),
                      );
                    },
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('CONNECT TO PC'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white),
                    label: const Text('BACK', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Strictly On-Demand: If not streaming yet, show clean Display Streaming Hub
    if (!_conn.isScreenStreaming) {
      return Scaffold(
        backgroundColor: const Color(0xFF09090C),
        body: _buildDisplayLaunchHub(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        left: false,
        right: false,
        child: Stack(
          children: [
            // 1. VIDEO STREAM DISPLAY — fills entire phone screen edge-to-edge
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  if (_decodedImage == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(color: Color(0xFF60A5FA), strokeWidth: 2.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'STARTING DUAL MONITOR STREAM...',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Connected to ${_conn.address} · Waiting for display capture frames',
                            style: const TextStyle(color: Color(0xFF9E9EAE), fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _startStream,
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text('RETRY STREAM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _conn.stopScreenStream();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.stop, size: 14, color: Colors.white),
                                label: const Text('CANCEL', style: TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  // Render frame — direct hardware GPU texture with zero decode queuing
                  final Widget imageWidget = SizedBox.expand(
                    child: RawImage(
                      image: _decodedImage,
                      fit: _boxFit, // BoxFit.contain (exact proportions) or BoxFit.fill (full screen)
                      filterQuality: FilterQuality.low,
                    ),
                  );

                  if (_zoomEnabled) {
                    return InteractiveViewer(
                      transformationController: _transformCtrl,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: SizedBox.expand(child: imageWidget),
                    );
                  }

                  return Builder(
                    builder: (imgContext) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          if (_directTouch) {
                            _handleTouch(details.globalPosition, 'down', imgContext);
                          }
                        },
                        onTapUp: (details) {
                          if (_directTouch) {
                            _handleTouch(details.globalPosition, 'up', imgContext);
                            _handleTouch(details.globalPosition, 'tap', imgContext);
                          }
                        },
                        onDoubleTapDown: (details) {
                          if (_directTouch) {
                            HapticFeedback.selectionClick();
                            _handleTouch(details.globalPosition, 'double_tap', imgContext);
                          }
                        },
                        onLongPressStart: (details) {
                          HapticFeedback.heavyImpact();
                          _handleTouch(details.globalPosition, 'right_click', imgContext, button: 'right');
                        },
                        onPanStart: (details) {
                          if (_directTouch) {
                            _handleTouch(details.globalPosition, 'down', imgContext);
                          }
                        },
                        onPanUpdate: (details) {
                          if (_directTouch) {
                            _handleTouch(details.globalPosition, 'move', imgContext);
                          }
                        },
                        onPanEnd: (details) {
                          if (_directTouch) {
                            _conn.sendScreenTouch(
                              action: 'up',
                              normX: 0,
                              normY: 0,
                              monitor: _selectedMonitorIndex,
                            );
                          }
                        },
                        child: imageWidget,
                      );
                    },
                  );
                },
              ),
            ),

            // 2. FLOATING TOP HUD TOOLBAR
            if (_showControls)
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC101018),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88000000), blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Back to Home Button
                      InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF222230),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('EXIT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // STOP STREAM BUTTON
                      InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _conn.stopScreenStream();
                          setState(() {
                            _decodedImage?.dispose();
                            _decodedImage = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stop, color: Color(0xFFEF4444), size: 14),
                              SizedBox(width: 4),
                              Text('STOP STREAM', style: TextStyle(color: Color(0xFFEF4444), fontSize: 9.5, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Monitor & Spacedesk Badge
                      ValueListenableBuilder<List<dynamic>>(
                        valueListenable: _conn.monitorsNotifier,
                        builder: (context, monitors, _) {
                          final bool isSingle = monitors.length <= 1;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: _openSpacedeskConsoleSheet,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSingle ? const Color(0xFF281C10) : const Color(0xFF1E2838),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSingle ? const Color(0xFFD97706).withAlpha(150) : const Color(0xFF2B3C58),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSingle ? Icons.copy : Icons.splitscreen,
                                        color: isSingle ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA),
                                        size: 13,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isSingle
                                            ? 'MIRRORING'
                                            : 'DISPLAY ${_selectedMonitorIndex + 1} (EXTENDED)',
                                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_drop_down, color: Color(0xFF93C5FD), size: 15),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _boxFit = (_boxFit == BoxFit.fill) ? BoxFit.contain : BoxFit.fill;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_boxFit == BoxFit.fill
                                          ? 'Switched to Full Screen Fill (Zero Black Bars)'
                                          : 'Switched to Letterbox Fit (Native Monitor Aspect)'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _boxFit == BoxFit.fill ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _boxFit == BoxFit.fill ? const Color(0xFF10B981) : const Color(0xFF475569),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _boxFit == BoxFit.fill ? Icons.fullscreen : Icons.fit_screen,
                                        color: _boxFit == BoxFit.fill ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                        size: 13,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _boxFit == BoxFit.fill ? 'FULL SCREEN' : 'FIT ASPECT',
                                        style: TextStyle(
                                          color: _boxFit == BoxFit.fill ? Colors.white : const Color(0xFFCBD5E1),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isSingle) ...[
                                const SizedBox(width: 5),
                                InkWell(
                                  onTap: () {
                                    _conn.controlVirtualDisplay('install');
                                    _conn.setWindowsDisplayMode('extend');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Creating Display 2... Please check PC screen and click "Yes" if Windows prompts!'),
                                        backgroundColor: Color(0xFF1E3A2E),
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF065F46),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add_to_queue, color: Color(0xFF6EE7B7), size: 12),
                                        SizedBox(width: 4),
                                        Text('CREATE DISPLAY 2', style: TextStyle(color: Color(0xFFD1FAE5), fontSize: 9, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: _showDualMonitorHelpDialog,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B2710),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                                    ),
                                    child: const Text('WHY? ⓘ', style: TextStyle(color: Color(0xFFFDE68A), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),

                      const Spacer(),

                      // Spacedesk Console Quick Action
                      IconButton(
                        onPressed: _openSpacedeskConsoleSheet,
                        icon: const Icon(Icons.settings_input_composite, color: Color(0xFF60A5FA), size: 18),
                        tooltip: 'Spacedesk Driver Console',
                      ),

                      // Keyboard Toggle
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showKeyboard = !_showKeyboard;
                            if (_showKeyboard) {
                              _textFocus.requestFocus();
                            } else {
                              _textFocus.unfocus();
                            }
                          });
                        },
                        icon: Icon(
                          _showKeyboard ? Icons.keyboard_hide : Icons.keyboard,
                          color: _showKeyboard ? const Color(0xFF34D399) : Colors.white,
                          size: 18,
                        ),
                        tooltip: 'PC Keyboard',
                      ),

                      // Zoom / Touch Mode Toggle
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _zoomEnabled = !_zoomEnabled;
                            _directTouch = !_zoomEnabled;
                            if (!_zoomEnabled) {
                              _transformCtrl.value = Matrix4.identity();
                            }
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_zoomEnabled ? 'Pinch-to-Zoom Enabled (Touch disabled in Zoom)' : 'Direct Touchscreen Mode Enabled'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: Icon(
                          _zoomEnabled ? Icons.zoom_in : Icons.touch_app,
                          color: _zoomEnabled ? const Color(0xFFF59E0B) : Colors.white,
                          size: 18,
                        ),
                        tooltip: _zoomEnabled ? 'Zoom Mode' : 'Touch Mode',
                      ),

                      // Aspect Ratio / Fit Toggle
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _boxFit = (_boxFit == BoxFit.contain) ? BoxFit.fill : BoxFit.contain;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_boxFit == BoxFit.contain
                                  ? 'Aspect Ratio: Exact Unstretched Monitor'
                                  : 'Aspect Ratio: Full Stretch Fill'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: Icon(
                          _boxFit == BoxFit.contain ? Icons.aspect_ratio : Icons.fullscreen,
                          color: _boxFit == BoxFit.contain ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
                          size: 18,
                        ),
                        tooltip: _boxFit == BoxFit.contain ? 'Exact Aspect Ratio' : 'Stretch Full Screen',
                      ),

                      // Hide Toolbar
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showControls = false;
                          });
                        },
                        icon: const Icon(Icons.visibility_off, color: Color(0xFF888899), size: 16),
                        tooltip: 'Hide Controls',
                      ),
                    ],
                  ),
                ),
              ),

            // 3. SHOW CONTROLS RE-OPEN BUTTON (When HUD is hidden)
            if (!_showControls)
              Positioned(
                top: 10,
                right: 14,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showControls = true;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xAA14141E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu, color: Colors.white, size: 16),
                  ),
                ),
              ),

            // 4. ON-SCREEN PC KEYBOARD BAR
            if (_showKeyboard)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xEE121218),
                    border: Border(top: BorderSide(color: Color(0xFF282836))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Quick PC Function keys
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickKeyButton('ESC', 'esc'),
                            _buildQuickKeyButton('WIN', 'win'),
                            _buildQuickKeyButton('TAB', 'tab'),
                            _buildQuickKeyButton('CTRL+Z', 'ctrl+z'),
                            _buildQuickKeyButton('CTRL+C', 'ctrl+c'),
                            _buildQuickKeyButton('CTRL+V', 'ctrl+v'),
                            _buildQuickKeyButton('ENTER', 'enter'),
                            _buildQuickKeyButton('BKSP', 'backspace'),
                            _buildQuickKeyButton('SPACE', 'space'),
                            _buildQuickKeyButton('ALT+F4', 'alt+f4'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Direct Text Stream Input
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textCtrl,
                              focusNode: _textFocus,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Type text directly into PC...',
                                hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF1E1E28),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                              onSubmitted: (txt) {
                                if (txt.isNotEmpty) {
                                  _conn.sendText(txt);
                                  _conn.sendKey('enter', action: 'press');
                                  _textCtrl.clear();
                                  _textFocus.requestFocus();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final txt = _textCtrl.text;
                              if (txt.isNotEmpty) {
                                _conn.sendText(txt);
                                _textCtrl.clear();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            child: const Text('SEND', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
