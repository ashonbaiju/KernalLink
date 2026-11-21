import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class ControllerStatusBar extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onOpenConnectionDialog;
  final VoidCallback onOpenSettings;

  const ControllerStatusBar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
    required this.onOpenConnectionDialog,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ConnectionService(),
      builder: (context, _) {
        final conn = ConnectionService();

        final bool isConn = conn.state == ConnectionStateEnum.connected;
        final bool isConnecting = conn.state == ConnectionStateEnum.connecting;

        String statusText;
        if (isConn) {
          statusText = conn.latencyMs > 0 ? '${conn.latencyMs}ms' : 'ONLINE';
        } else if (isConnecting) {
          statusText = 'CONNECTING...';
        } else {
          statusText = 'OFFLINE';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF000000),
            border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
          ),
          child: Row(
            children: [
              // Connection Status Pill
              InkWell(
                onTap: onOpenConnectionDialog,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConn ? const Color(0xFF151515) : const Color(0xFF0D0D0D),
                    border: Border.all(
                      color: isConn ? const Color(0xFFFFFFFF) : const Color(0xFF333333),
                      width: 1.0,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isConn
                              ? const Color(0xFFFFFFFF)
                              : (isConnecting ? const Color(0xFF888888) : const Color(0xFF444444)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: isConn ? const Color(0xFFFFFFFF) : const Color(0xFF888888),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: isConn ? const Color(0xFFFFFFFF) : const Color(0xFF666666),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Mode Tabs (Monochrome Minimal)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTab(0, 'GAMEPAD'),
                      _buildTab(1, 'TRACKPAD'),
                      _buildTab(2, 'KEYBOARD'),
                      _buildTab(3, 'MEDIA'),
                    ],
                  ),
                ),
              ),

              // Settings button
              InkWell(
                onTap: onOpenSettings,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF262626)),
                  ),
                  child: const Icon(
                    Icons.tune,
                    color: Color(0xFFFFFFFF),
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTab(int index, String title) {
    final isSelected = currentTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => onTabSelected(index),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFF222222),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? const Color(0xFF000000) : const Color(0xFF888888),
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
