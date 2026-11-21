import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/audio_service.dart';

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  void _trigger(String action) {
    HapticFeedback.lightImpact();
    ConnectionService().sendMedia(action);
  }

  void _sendKey(String key) {
    HapticFeedback.lightImpact();
    ConnectionService().sendKey(key, action: 'press');
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = 58,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFFFFFFFF) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPrimary ? const Color(0xFFFFFFFF) : const Color(0xFF262626),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isPrimary ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              size: size * 0.40,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? const Color(0xFF000000) : const Color(0xFF888888),
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top Seek Controls (-10s / +10s) + Playback
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF080808),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Column(
                children: [
                  const Text(
                    'PLAYBACK & 10S SEEK',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Main 5-Button Row: Prev | -10s | PLAY/PAUSE | +10s | Next
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Previous Track
                      _buildMediaButton(
                        icon: Icons.skip_previous,
                        label: 'PREV',
                        onTap: () => _trigger('prev'),
                      ),
                      const SizedBox(width: 10),

                      // -10s Backward
                      _buildMediaButton(
                        icon: Icons.replay_10,
                        label: '-10 SEC',
                        onTap: () => _trigger('backward_10'),
                      ),
                      const SizedBox(width: 12),

                      // PLAY / PAUSE (Centerpiece)
                      _buildMediaButton(
                        icon: Icons.play_arrow,
                        label: 'PLAY',
                        size: 74,
                        isPrimary: true,
                        onTap: () => _trigger('play_pause'),
                      ),
                      const SizedBox(width: 12),

                      // +10s Forward
                      _buildMediaButton(
                        icon: Icons.forward_10,
                        label: '+10 SEC',
                        onTap: () => _trigger('forward_10'),
                      ),
                      const SizedBox(width: 10),

                      // Next Track
                      _buildMediaButton(
                        icon: Icons.skip_next,
                        label: 'NEXT',
                        onTap: () => _trigger('next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Volume & Audio Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF080808),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Column(
                children: [
                  const Text(
                    'AUDIO & DISPLAY',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMediaButton(
                        icon: Icons.volume_down,
                        label: 'VOL -',
                        onTap: () => _trigger('vol_down'),
                      ),
                      const SizedBox(width: 12),
                      _buildMediaButton(
                        icon: Icons.volume_off,
                        label: 'MUTE',
                        onTap: () => _trigger('mute'),
                      ),
                      const SizedBox(width: 12),
                      _buildMediaButton(
                        icon: Icons.volume_up,
                        label: 'VOL +',
                        onTap: () => _trigger('vol_up'),
                      ),
                      const SizedBox(width: 12),
                      _buildMediaButton(
                        icon: Icons.fullscreen,
                        label: 'FULLSCREEN',
                        onTap: () => _sendKey('f'),
                      ),
                      const SizedBox(width: 12),
                      _buildMediaButton(
                        icon: Icons.stop,
                        label: 'STOP',
                        onTap: () => _trigger('stop'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Live Audio Relay & Virtual Speaker Control
            AnimatedBuilder(
              animation: AudioRelayService(),
              builder: (context, _) {
                final audio = AudioRelayService();
                final isStreaming = audio.isStreaming;
                final isVirtual = audio.isVirtualSpeakerDefault;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF080808),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isStreaming ? Colors.white : const Color(0xFF1E1E1E)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isStreaming ? Icons.graphic_eq : Icons.headphones_outlined,
                                color: isStreaming ? Colors.white : const Color(0xFF888888),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'AUDIO RELAY (PHONE SPEAKER)',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isStreaming ? Colors.white : const Color(0xFF141418),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isStreaming ? 'STREAMING' : 'OFF',
                              style: TextStyle(
                                color: isStreaming ? Colors.black : const Color(0xFF888888),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                audio.switchPcAudioDevice(isVirtual ? 'speakers' : 'virtual');
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141418),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF262626)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  audio.isSwitching
                                      ? 'SWITCHING WINDOWS OUTPUT...'
                                      : (isVirtual ? 'OUTPUT: KERNALLINK VIRTUAL (PHONE ONLY)' : 'OUTPUT: LAPTOP SPEAKERS (MIRROR)'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              if (isStreaming) {
                                audio.stopStream();
                              } else {
                                audio.startStream();
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isStreaming ? const Color(0xFF1A1A1A) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: isStreaming ? Border.all(color: const Color(0xFF333333)) : null,
                              ),
                              child: Text(
                                isStreaming ? 'STOP' : 'STREAM',
                                style: TextStyle(
                                  color: isStreaming ? const Color(0xFFA1A1AA) : Colors.black,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
