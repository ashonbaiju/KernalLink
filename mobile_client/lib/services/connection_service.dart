import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

enum ConnectionStateEnum { disconnected, connecting, connected }

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;

  ConnectionStateEnum _state = ConnectionStateEnum.disconnected;
  ConnectionStateEnum get state => _state;
  bool get isConnected => _state == ConnectionStateEnum.connected;

  String _host = '127.0.0.1';
  int _port = 8889;
  String get host => _host;
  int get port => _port;
  String get address => '$_host:$_port';

  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  List<String> _recentHosts = [
    '127.0.0.1:8889', // USB Cable (ADB)
    '192.168.1.3:8889', // Wi-Fi LAN
    '192.168.42.129:8889', // USB Tethering default
  ];
  List<String> get recentHosts => List.unmodifiable(_recentHosts);

  double sensitivity = 1.0;
  double deadzone = 0.08;

  // --- UDP AUTO-DISCOVERY ---
  RawDatagramSocket? _discoverySocket;
  String? _discoveredHost;
  int _discoveredPort = 8889;
  String? _discoveredHostname;
  DateTime? _lastDiscoveredTime;

  String? get discoveredHost => _discoveredHost;
  int get discoveredPort => _discoveredPort;
  String? get discoveredHostname => _discoveredHostname;
  String? get discoveredAddress => _discoveredHost != null ? '$_discoveredHost:$_discoveredPort' : null;
  bool get hasDiscoveredServer =>
      _discoveredHost != null &&
      _lastDiscoveredTime != null &&
      DateTime.now().difference(_lastDiscoveredTime!).inSeconds < 15;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _host = prefs.getString('saved_host') ?? '127.0.0.1';
      _port = prefs.getInt('saved_port') ?? 8889;
      final savedRecent = prefs.getStringList('recent_hosts');
      if (savedRecent != null && savedRecent.isNotEmpty) {
        _recentHosts = savedRecent;
      }
      sensitivity = prefs.getDouble('sensitivity') ?? 1.0;
      deadzone = prefs.getDouble('deadzone') ?? 0.08;
      notifyListeners();
    } catch (_) {}

    startDiscovery();
  }

  void startDiscovery() async {
    if (_discoverySocket != null) return;
    try {
      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8890, reuseAddress: true, reusePort: true);
      _discoverySocket?.broadcastEnabled = true;
      _discoverySocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg != null) {
            _onDiscoveryPacket(dg);
          }
        }
      });
      sendDiscoveryProbe();
    } catch (_) {
      // Fallback: bind to any ephemeral port for receiving broadcasts
      try {
        _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _discoverySocket?.broadcastEnabled = true;
        _discoverySocket?.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final dg = _discoverySocket?.receive();
            if (dg != null) {
              _onDiscoveryPacket(dg);
            }
          }
        });
        sendDiscoveryProbe();
      } catch (_) {}
    }
  }

  void _onDiscoveryPacket(Datagram dg) {
    try {
      final text = utf8.decode(dg.data);
      final json = jsonDecode(text);
      if (json is Map && (json['service'] == 'kernallink_server' || json['service'] == 'touch_pc_server')) {
        final String? hName = json['hostname'];
        final int p = json['port'] ?? 8889;
        final ips = json['ips'];

        String? ipToUse;
        if (ips is List && ips.isNotEmpty) {
          ipToUse = ips.first.toString();
        } else {
          ipToUse = dg.address.address;
        }

        if (ipToUse.isNotEmpty && !ipToUse.startsWith('127.')) {
          final changed = _discoveredHost != ipToUse || _discoveredHostname != hName;
          _discoveredHost = ipToUse;
          _discoveredHostname = hName;
          _discoveredPort = p;
          _lastDiscoveredTime = DateTime.now();

          // Also update recent hosts if not already there
          final addr = '$ipToUse:$p';
          if (!_recentHosts.contains(addr)) {
            _recentHosts.insert(0, addr);
            if (_recentHosts.length > 5) _recentHosts.removeLast();
          }

          if (changed) {
            notifyListeners();
          }
        }
      }
    } catch (_) {}
  }

  void sendDiscoveryProbe() {
    try {
      final data = utf8.encode(jsonEncode({'service': 'find_kernallink', 'time': DateTime.now().millisecondsSinceEpoch}));
      _discoverySocket?.send(data, InternetAddress('255.255.255.255'), 8890);
      _discoverySocket?.send(data, InternetAddress('192.168.1.255'), 8890);
    } catch (_) {}
  }

  String _formatFriendlyError(dynamic e, String targetHost, int targetPort) {
    final errStr = e.toString();
    final isLoopback = targetHost == '127.0.0.1' || targetHost == 'localhost';

    if (errStr.contains('Connection refused') || errStr.contains('errno = 111')) {
      if (isLoopback) {
        return 'Connection refused at 127.0.0.1:$targetPort.\n\n'
            '• USB Cable Mode: Ensure your phone is connected to your PC via USB with USB Debugging enabled, and start_server.bat is running on PC.\n'
            '• Wi-Fi Mode: Do not use 127.0.0.1. Tap your discovered PC or enter your PC\'s Wi-Fi IP address shown in the PC server window!';
      } else {
        return 'Connection refused at $targetHost:$targetPort.\n\n'
            'The PC server is not running or not listening on port $targetPort. Double-click start_server.bat on your PC.';
      }
    }

    if (errStr.contains('timed out') || errStr.contains('TimeoutException') || errStr.contains('No route to host')) {
      return 'Connection timed out to $targetHost:$targetPort.\n\n'
          '• Ensure PC and phone are connected to the SAME Wi-Fi network.\n'
          '• Check if Windows Firewall is blocking port $targetPort on your PC.';
    }

    return 'Could not connect to $targetHost:$targetPort:\n$errStr';
  }

  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_host', _host);
      await prefs.setInt('saved_port', _port);
      await prefs.setStringList('recent_hosts', _recentHosts);
      await prefs.setDouble('sensitivity', sensitivity);
      await prefs.setDouble('deadzone', deadzone);
    } catch (_) {}
  }

  Future<void> connect(String targetAddress) async {
    disconnect();

    String cleanAddress = targetAddress.trim().replaceAll('http://', '').replaceAll('ws://', '');
    if (cleanAddress.contains(':')) {
      final parts = cleanAddress.split(':');
      _host = parts[0];
      _port = int.tryParse(parts[1]) ?? 8889;
    } else {
      _host = cleanAddress;
      _port = 8889;
    }

    if (!_recentHosts.contains(address)) {
      _recentHosts.insert(0, address);
      if (_recentHosts.length > 5) _recentHosts.removeLast();
    }
    saveSettings();

    _state = ConnectionStateEnum.connecting;
    _lastError = null;
    notifyListeners();

    final wsUri = Uri.parse('ws://$_host:$_port');
    try {
      _channel = WebSocketChannel.connect(wsUri);
      await _channel!.ready.timeout(const Duration(seconds: 8));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (err) {
          _lastError = _formatFriendlyError(err, _host, _port);
          disconnect();
        },
        onDone: () {
          disconnect();
        },
      );

      _state = ConnectionStateEnum.connected;
      _lastError = null;
      notifyListeners();

      _startPingLoop();
    } catch (e) {
      _lastError = _formatFriendlyError(e, _host, _port);
      disconnect();
    }
  }

  String? _lastError;
  String? get lastError => _lastError;

  // --- SCREEN STREAMING & DUAL MONITOR (SPACEDESK & VDD) ---
  final ValueNotifier<Uint8List?> screenFrameNotifier = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<List<Map<String, dynamic>>> monitorsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<Map<String, dynamic>> spacedeskStatusNotifier = ValueNotifier<Map<String, dynamic>>({});
  final ValueNotifier<Map<String, dynamic>> vddStatusNotifier = ValueNotifier<Map<String, dynamic>>({});
  final ValueNotifier<Map<String, dynamic>> streamConfigNotifier = ValueNotifier<Map<String, dynamic>>({});
  final ValueNotifier<Map<String, dynamic>> audioStatusNotifier = ValueNotifier<Map<String, dynamic>>({});

  bool _isScreenStreaming = false;
  bool get isScreenStreaming => _isScreenStreaming;

  void disconnect() {
    stopScreenStream();
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close(status.normalClosure);
    } catch (_) {}
    _channel = null;

    if (_state != ConnectionStateEnum.disconnected) {
      _state = ConnectionStateEnum.disconnected;
      _latencyMs = 0;
      notifyListeners();
    }
  }

  bool _loggedFirstFrame = false;

  void _onMessage(dynamic raw) {
    if (raw is ByteBuffer) {
      final bytes = raw.asUint8List();
      if (!_loggedFirstFrame) {
        _loggedFirstFrame = true;
        debugPrint('[DualMonitor] First screen frame received: ${bytes.length} bytes');
      }
      screenFrameNotifier.value = bytes;
      return;
    }

    if (raw is List<int>) {
      final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
      if (!_loggedFirstFrame) {
        _loggedFirstFrame = true;
        debugPrint('[DualMonitor] First screen frame received: ${bytes.length} bytes');
      }
      screenFrameNotifier.value = bytes;
      return;
    }

    try {
      final data = jsonDecode(raw.toString());
      if (data is Map<String, dynamic>) {
        final type = data['type'];
        if (type == 'pong') {
          final int sentTime = data['t'] ?? 0;
          if (sentTime > 0) {
            final now = DateTime.now().millisecondsSinceEpoch;
            _latencyMs = (now - sentTime).clamp(0, 9999);
            notifyListeners();
          }
        } else if (type == 'screen_meta') {
          if (data['monitors'] is List) {
            monitorsNotifier.value = List<Map<String, dynamic>>.from(
              (data['monitors'] as List).map((m) => Map<String, dynamic>.from(m)),
            );
          }
          if (data['spacedesk'] is Map) {
            spacedeskStatusNotifier.value = Map<String, dynamic>.from(data['spacedesk']);
          }
          if (data['vdd'] is Map) {
            vddStatusNotifier.value = Map<String, dynamic>.from(data['vdd']);
          }
          notifyListeners();
        } else if (type == 'stream_config') {
          streamConfigNotifier.value = Map<String, dynamic>.from(data);
          notifyListeners();
        } else if (type == 'audio_status') {
          audioStatusNotifier.value = Map<String, dynamic>.from(data);
          notifyListeners();
        } else if (type == 'screen_stop_ack' || type == 'screen_disabled') {
          _isScreenStreaming = false;
          screenFrameNotifier.value = null;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (isConnected) {
        sendPacket({
          'type': 'ping',
          't': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void sendPacket(Map<String, dynamic> packet) {
    if (_state == ConnectionStateEnum.connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(packet));
      } catch (_) {
        disconnect();
      }
    }
  }

  void send(Map<String, dynamic> packet) => sendPacket(packet);

  // --- CONTROLLER TRANSMIT METHODS ---

  void sendGamepad({
    required double lx,
    required double ly,
    required double rx,
    required double ry,
    required double lt,
    required double rt,
    required Set<String> buttons,
  }) {
    sendPacket({
      'type': 'gamepad',
      'lx': lx,
      'ly': ly,
      'rx': rx,
      'ry': ry,
      'lt': lt,
      'rt': rt,
      'buttons': buttons.toList(),
    });
  }

  void sendMouseMove(double dx, double dy) {
    sendPacket({
      'type': 'mouse_move',
      'dx': dx * sensitivity,
      'dy': dy * sensitivity,
    });
  }

  void sendMouseClick(String button, {String action = 'click'}) {
    sendPacket({
      'type': 'mouse_click',
      'button': button, // left, right, middle
      'action': action, // click, down, up
    });
  }

  void sendMouseScroll(int dy) {
    sendPacket({
      'type': 'mouse_scroll',
      'dy': dy,
    });
  }

  void sendZoom(String direction, {int amount = 120}) {
    sendPacket({
      'type': 'zoom',
      'direction': direction,
      'amount': amount,
    });
  }

  void sendKey(String key, {String action = 'press'}) {
    sendPacket({
      'type': 'key',
      'key': key,
      'action': action,
    });
  }

  void sendText(String text) {
    sendPacket({
      'type': 'text',
      'text': text,
    });
  }

  void sendMedia(String action) {
    sendPacket({
      'type': 'media',
      'action': action,
    });
  }

  void sendCombo(List<String> keys) {
    sendPacket({
      'type': 'combo',
      'keys': keys,
    });
  }

  // --- SCREEN STREAMING & SPACEDESK METHODS ---

  void startScreenStream({
    int monitor = 0,
    int quality = 80,
    int fps = 60,
    double scale = 1.0,
  }) {
    _loggedFirstFrame = false;
    _isScreenStreaming = true;
    debugPrint('[DualMonitor] Requesting screen stream (monitor=$monitor, ${fps}fps, Q$quality, scale=$scale)...');
    sendPacket({
      'type': 'screen_start',
      'monitor': monitor,
      'quality': quality,
      'fps': fps,
      'scale': scale,
    });
    requestMonitors();
    notifyListeners();
  }

  void stopScreenStream() {
    if (_isScreenStreaming) {
      _isScreenStreaming = false;
      sendPacket({'type': 'screen_stop'});
      screenFrameNotifier.value = null;
      notifyListeners();
    }
  }

  void requestMonitors() {
    sendPacket({'type': 'get_monitors'});
  }

  void sendScreenTouch({
    required String action, // down, move, up, tap, double_tap, right_click, scroll
    required double normX,
    required double normY,
    int monitor = 0,
    int deltaY = 0,
    String button = 'left',
  }) {
    sendPacket({
      'type': 'screen_touch',
      'action': action,
      'x': normX.clamp(0.0, 1.0),
      'y': normY.clamp(0.0, 1.0),
      'monitor': monitor,
      'delta_y': deltaY,
      'button': button,
    });
  }

  void setWindowsDisplayMode(String mode) {
    sendPacket({
      'type': 'display_switch',
      'mode': mode, // extend, clone, internal
    });
  }

  void controlSpacedesk(String action) {
    sendPacket({
      'type': 'spacedesk_action',
      'action': action, // start, stop, launch_console
    });
  }

  void controlVirtualDisplay(String action) {
    sendPacket({
      'type': 'vdd_action',
      'action': action, // install, uninstall, enable, disable
    });
  }
}


