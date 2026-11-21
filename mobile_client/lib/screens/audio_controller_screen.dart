import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/audio_service.dart';

class AudioControllerScreen extends StatefulWidget {
  const AudioControllerScreen({super.key});

  @override
  State<AudioControllerScreen> createState() => _AudioControllerScreenState();
}

class _AudioControllerScreenState extends State<AudioControllerScreen> with SingleTickerProviderStateMixin {
  final ConnectionService _conn = ConnectionService();
  final AudioRelayService _audio = AudioRelayService();
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _audio.addListener(_onAudioUpdated);
    _conn.addListener(_onAudioUpdated);
    _audio.requestPcAudioStatus();
  }

  @override
  void dispose() {
    _audio.removeListener(_onAudioUpdated);
    _conn.removeListener(_onAudioUpdated);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onAudioUpdated() {
    if (mounted) setState(() {});
  }

  void _triggerMedia(String action) {
    HapticFeedback.lightImpact();
    _conn.sendMedia(action);
  }

  @override
  Widget build(BuildContext context) {
    final bool isStreaming = _audio.isStreaming;
    final bool isSocketLive = _audio.socketConnected;
    final bool isVirtualActive = _audio.isVirtualSpeakerDefault;
    final bool isSwitching = _audio.isSwitching;
    final String activeDev = _audio.activePcDevice;
    final double rxMb = _audio.bytesReceived / (1024 * 1024);
    final String connType = _conn.address.startsWith('127.0.0.1') ? 'USB CABLE' : 'WI-FI';
    final String latencyText = _conn.address.startsWith('127.0.0.1') ? '<0.5ms Ping' : '${_conn.latencyMs}ms Ping';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Status Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1C1C22), width: 1.0)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121216),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF27272A), width: 0.8),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AUDIO CONTROLLER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'KERNALLINK VIRTUAL SPEAKER · 48KHZ',
                          style: TextStyle(
                            color: Color(0xFF71717A),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141418),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF27272A), width: 0.8),
                    ),
                    child: Text(
                      '$connType · $latencyText',
                      style: const TextStyle(
                        color: Color(0xFFE4E4E7),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Visualizer & Master Stream Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090C),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isStreaming ? Colors.white : const Color(0xFF27272A),
                          width: isStreaming ? 1.2 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Animated Visualizer Bars Simulation
                          SizedBox(
                            height: 48,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(24, (i) {
                                return AnimatedBuilder(
                                  animation: _animCtrl,
                                  builder: (context, _) {
                                    final double phase = (i * 0.28);
                                    final double v = isStreaming
                                        ? (0.2 + 0.8 * ((_animCtrl.value + phase) % 1.0))
                                        : 0.15;
                                    return Container(
                                      width: 4,
                                      height: isStreaming ? (44 * v).clamp(4.0, 44.0) : 4,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: isStreaming ? Colors.white : const Color(0xFF27272A),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    );
                                  },
                                );
                              }),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Text(
                            !isStreaming
                                ? 'AUDIO RELAY STANDBY'
                                : (isSocketLive ? 'STREAMING LAPTOP AUDIO' : 'CONNECTING TO PC AUDIO...'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            !isStreaming
                                ? 'Tap below to stream all laptop sound to this phone'
                                : (isSocketLive
                                    ? '48,000 Hz Stereo PCM · ${rxMb.toStringAsFixed(2)} MB Received'
                                    : 'Ensure KernalLink Server is running (Port 8891)'),
                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 10),
                          ),

                          const SizedBox(height: 18),

                          // Big Master Stream Toggle Button + Test Chime
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.heavyImpact();
                                    if (isStreaming) {
                                      _audio.stopStream();
                                    } else {
                                      _audio.startStream();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    decoration: BoxDecoration(
                                      color: isStreaming ? const Color(0xFF18181D) : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isStreaming ? Border.all(color: const Color(0xFF3F3F46)) : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      isStreaming ? 'STOP AUDIO STREAM' : 'START AUDIO STREAM',
                                      style: TextStyle(
                                        color: isStreaming ? const Color(0xFFA1A1AA) : Colors.black,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _audio.triggerPcChime();
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141418),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF27272A)),
                                  ),
                                  child: const Text(
                                    'TEST SOUND',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Windows Playback Output Target Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'WINDOWS AUDIO OUTPUT TARGET',
                          style: TextStyle(
                            color: Color(0xFF71717A),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          isSwitching ? 'SWITCHING...' : activeDev,
                          style: TextStyle(
                            color: isSwitching ? Colors.white : const Color(0xFFA1A1AA),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Mode 1: KernalLink Virtual Speaker (Phone Exclusive)
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _audio.switchPcAudioDevice('virtual');
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0C0F),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isVirtualActive ? Colors.white : const Color(0xFF222226),
                            width: isVirtualActive ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isVirtualActive ? Colors.white : const Color(0xFF16161A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.headphones,
                                color: isVirtualActive ? Colors.black : const Color(0xFFA1A1AA),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'KERNALLINK VIRTUAL SPEAKER',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _audio.virtualAvailable
                                        ? 'Routes all PC audio to phone only. Laptop physical speakers are muted.'
                                        : 'Virtual Speaker endpoint not detected on PC.',
                                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            if (isVirtualActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Mode 2: Laptop Speakers (Mirror)
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _audio.switchPcAudioDevice('speakers');
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0C0F),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !isVirtualActive ? Colors.white : const Color(0xFF222226),
                            width: !isVirtualActive ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: !isVirtualActive ? Colors.white : const Color(0xFF16161A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.speaker_group,
                                color: !isVirtualActive ? Colors.black : const Color(0xFFA1A1AA),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LAPTOP SPEAKERS (SYSTEM MIRROR)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Sound plays on laptop physical speakers and streams to phone simultaneously.',
                                    style: TextStyle(color: Color(0xFF71717A), fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            if (!isVirtualActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Exact Detected Windows Output Devices List (for headphones or alternate outputs)
                    if (_audio.pcDevices.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _audio.pcDevices.map((d) {
                          final String devName = (d['name'] ?? '').toString();
                          final bool isDef = d['is_default'] == true;
                          return InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _audio.switchPcAudioDevice(devName);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDef ? Colors.white : const Color(0xFF121216),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDef ? Colors.white : const Color(0xFF27272A),
                                ),
                              ),
                              child: Text(
                                devName,
                                style: TextStyle(
                                  color: isDef ? Colors.black : const Color(0xFFA1A1AA),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Volume Controls Section
                    const Text(
                      'AUDIO MIXER & CONTROLS',
                      style: TextStyle(
                        color: Color(0xFF71717A),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Phone Volume Slider Card
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090C),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF222226)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PHONE PLAYBACK VOLUME',
                                style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${(_audio.volume * 100).toInt()}%',
                                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  _audio.toggleMute();
                                },
                                icon: Icon(
                                  _audio.isMuted ? Icons.volume_off : Icons.volume_up,
                                  color: _audio.isMuted ? const Color(0xFF71717A) : Colors.white,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: const Color(0xFF27272A),
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  ),
                                  child: Slider(
                                    value: _audio.volume,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (val) {
                                      _audio.setVolume(val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // PC Media Remote Strip
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090C),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF222226)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PC MEDIA REMOTE',
                            style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildQuickBtn(icon: Icons.skip_previous, label: 'PREV', onTap: () => _triggerMedia('prev')),
                              _buildQuickBtn(icon: Icons.replay_10, label: '-10S', onTap: () => _triggerMedia('backward_10')),
                              _buildQuickBtn(icon: Icons.play_arrow, label: 'PLAY', isPrimary: true, onTap: () => _triggerMedia('play_pause')),
                              _buildQuickBtn(icon: Icons.forward_10, label: '+10S', onTap: () => _triggerMedia('forward_10')),
                              _buildQuickBtn(icon: Icons.skip_next, label: 'NEXT', onTap: () => _triggerMedia('next')),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isPrimary ? Colors.white : const Color(0xFF27272A)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.black : const Color(0xFF71717A),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
