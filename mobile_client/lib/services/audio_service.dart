import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'connection_service.dart';

class AudioRelayService extends ChangeNotifier {
  static final AudioRelayService _instance = AudioRelayService._internal();
  factory AudioRelayService() => _instance;
  AudioRelayService._internal() {
    _initConnectionListener();
  }

  static const MethodChannel _channel = MethodChannel('com.touchcontroller.mobile_client/audio');

  bool _wasConnected = false;
  bool _isStreaming = false;
  bool _socketConnected = false;
  int _bytesReceived = 0;
  String _lastError = '';
  double _volume = 1.0;
  bool _isMuted = false;

  String _activePcDevice = 'Detecting...';
  bool _isVirtualSpeakerDefault = false;
  bool _virtualAvailable = true;
  bool _pcRelayRunning = false;
  String _pcRelayDevice = '';
  bool _isSwitching = false;
  List<Map<String, dynamic>> _pcDevices = [];

  Timer? _stateTimer;
  Timer? _switchTimeoutTimer;

  bool get isStreaming => _isStreaming;
  bool get socketConnected => _socketConnected;
  int get bytesReceived => _bytesReceived;
  String get lastError => _lastError;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  String get activePcDevice => _activePcDevice;
  bool get isVirtualSpeakerDefault => _isVirtualSpeakerDefault;
  bool get virtualAvailable => _virtualAvailable;
  bool get pcRelayRunning => _pcRelayRunning;
  String get pcRelayDevice => _pcRelayDevice;
  bool get isSwitching => _isSwitching;
  List<Map<String, dynamic>> get pcDevices => List.unmodifiable(_pcDevices);

  void _initConnectionListener() {
    final conn = ConnectionService();
    conn.addListener(() {
      final nowConn = conn.isConnected;
      if (!nowConn && _wasConnected) {
        _wasConnected = false;
        _isSwitching = false;
        stopStream();
      } else if (nowConn && !_wasConnected) {
        _wasConnected = true;
        // Strictly On-Demand: Query PC audio status on connect, but do NOT auto-start streaming
        requestPcAudioStatus();
      }
    });

    conn.audioStatusNotifier.addListener(() {
      final data = conn.audioStatusNotifier.value;
      if (data.isNotEmpty) {
        handlePcAudioStatus(data);
      }
    });
  }

  void _startStateMonitor() {
    _stateTimer?.cancel();
    _stateTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!_isStreaming) {
        _stateTimer?.cancel();
        return;
      }
      try {
        final Map<dynamic, dynamic>? st = await _channel.invokeMapMethod('getAudioState');
        if (st != null) {
          final bool sockOk = st['socketConnected'] == true;
          final int rxBytes = (st['bytesReceived'] is int) ? st['bytesReceived'] as int : 0;
          final String err = (st['lastError'] ?? '').toString();
          if (sockOk != _socketConnected || rxBytes != _bytesReceived || err != _lastError) {
            _socketConnected = sockOk;
            _bytesReceived = rxBytes;
            _lastError = err;
            notifyListeners();
          }
        }
      } catch (_) {}
    });
  }

  Future<bool> startStream({String? host, int port = 8891}) async {
    final conn = ConnectionService();
    String targetHost = host ?? '127.0.0.1';

    if (host == null && conn.isConnected) {
      final addr = conn.address;
      if (addr.contains(':')) {
        targetHost = addr.split(':').first;
      } else {
        targetHost = addr;
      }
    }

    // Also wake PC Audio Relay engine in case it was stopped from PC panel
    if (conn.isConnected) {
      conn.send({'type': 'audio_relay_control', 'action': 'start'});
    }

    try {
      final bool? success = await _channel.invokeMethod<bool>('startAudio', {
        'host': targetHost,
        'port': port,
      });

      _isStreaming = success ?? false;
      if (_isStreaming) {
        _startStateMonitor();
      }
      notifyListeners();
      return _isStreaming;
    } catch (e) {
      debugPrint('[AudioRelay] Error starting audio: $e');
      _isStreaming = false;
      _socketConnected = false;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> stopStream() async {
    _stateTimer?.cancel();
    try {
      await _channel.invokeMethod('stopAudio');
    } catch (e) {
      debugPrint('[AudioRelay] Error stopping audio: $e');
    }
    _isStreaming = false;
    _socketConnected = false;
    notifyListeners();
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod('setVolume', {
        'volume': _isMuted ? 0.0 : _volume,
      });
    } catch (e) {
      debugPrint('[AudioRelay] Error setting volume: $e');
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    try {
      await _channel.invokeMethod('setVolume', {
        'volume': _isMuted ? 0.0 : _volume,
      });
    } catch (e) {
      debugPrint('[AudioRelay] Error toggling mute: $e');
    }
    notifyListeners();
  }

  void requestPcAudioStatus() {
    final conn = ConnectionService();
    if (conn.isConnected) {
      conn.send({'type': 'get_audio_status'});
    }
  }

  void switchPcAudioDevice(String target) {
    // target: 'virtual', 'speakers', or exact device name from pcDevices
    final conn = ConnectionService();
    if (!conn.isConnected) return;

    _isSwitching = true;
    notifyListeners();

    conn.send({
      'type': 'switch_audio_device',
      'target': target,
    });

    _switchTimeoutTimer?.cancel();
    _switchTimeoutTimer = Timer(const Duration(milliseconds: 2200), () {
      if (_isSwitching) {
        _isSwitching = false;
        requestPcAudioStatus();
        notifyListeners();
      }
    });
  }

  void triggerPcChime() {
    final conn = ConnectionService();
    if (conn.isConnected) {
      conn.send({'type': 'audio_relay_control', 'action': 'test_chime'});
    }
  }

  void handlePcAudioStatus(Map<String, dynamic> data) {
    _switchTimeoutTimer?.cancel();
    _isSwitching = false;
    _activePcDevice = (data['default_device'] ?? 'Unknown').toString();
    _isVirtualSpeakerDefault = data['is_virtual_default'] == true;
    if (data.containsKey('virtual_available')) {
      _virtualAvailable = data['virtual_available'] == true;
    }
    if (data['devices'] is List) {
      _pcDevices = List<Map<String, dynamic>>.from(
        (data['devices'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
      );
    }
    if (data['relay'] is Map) {
      final r = Map<String, dynamic>.from(data['relay'] as Map);
      _pcRelayRunning = r['running'] == true;
      _pcRelayDevice = (r['device'] ?? '').toString();
    }
    notifyListeners();
  }
}
