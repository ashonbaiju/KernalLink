import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final ConnectionService _conn = ConnectionService();
  late TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _addressCtrl = TextEditingController(
      text: _conn.hasDiscoveredServer ? _conn.discoveredAddress! : _conn.address,
    );
    _conn.sendDiscoveryProbe();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  void _connect(String addr) {
    _conn.connect(addr);
    Navigator.of(context).pop();
  }

  Widget _buildPresetBtn({
    required String title,
    required String subtitle,
    required String address,
    required IconData icon,
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          _addressCtrl.text = address;
          _connect(address);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted ? const Color(0xFF18181C) : const Color(0xFF0C0C0E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHighlighted ? const Color(0xFFE4E4E7) : const Color(0xFF222226),
              width: isHighlighted ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isHighlighted ? const Color(0xFFFFFFFF) : const Color(0xFFA1A1AA),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isHighlighted ? const Color(0xFFFFFFFF) : const Color(0xFFE4E4E7),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isHighlighted ? const Color(0xFFD4D4D8) : const Color(0xFF71717A),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isHighlighted ? const Color(0xFFFFFFFF) : const Color(0xFF52525B),
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _conn,
      builder: (context, _) {
        return Dialog(
          backgroundColor: const Color(0xFF09090B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF27272A), width: 1.2),
          ),
          child: Container(
            width: 400,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title with Logo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF27272A), width: 1.0),
                            ),
                            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'CONNECT TO PC',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF888888), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // DISCOVERED PC CARD (over Wi-Fi)
                  if (_conn.hasDiscoveredServer) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141418),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_tethering, color: Color(0xFFFFFFFF), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FOUND PC: ${_conn.discoveredHostname ?? "Windows PC"}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_conn.discoveredAddress}  ·  Auto-Detected over Wi-Fi',
                                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 9.5),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              _addressCtrl.text = _conn.discoveredAddress!;
                              _connect(_conn.discoveredAddress!);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFFFFF),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('CONNECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Connection Presets Header + Scan Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'QUICK CONNECTION PRESETS',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _conn.sendDiscoveryProbe();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Scanning Wi-Fi for PC server...'),
                              duration: Duration(seconds: 1),
                              backgroundColor: Color(0xFF18181B),
                            ),
                          );
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.refresh, color: Color(0xFFE4E4E7), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'SCAN WI-FI',
                              style: TextStyle(
                                color: Color(0xFFE4E4E7),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  _buildPresetBtn(
                    title: 'USB Cable (ADB Reverse)',
                    subtitle: '127.0.0.1:8889  ·  Ultra Low Latency (<0.5ms)',
                    address: '127.0.0.1:8889',
                    icon: Icons.usb,
                  ),

                  _buildPresetBtn(
                    title: _conn.hasDiscoveredServer ? 'Local Wi-Fi (Detected PC)' : 'Local Wi-Fi Network',
                    subtitle: _conn.hasDiscoveredServer
                        ? '${_conn.discoveredAddress}  ·  Active PC on Network'
                        : (_conn.host.startsWith('192.168.') ? '${_conn.address}  ·  Saved Wi-Fi IP' : '192.168.1.3:8889  ·  Default LAN'),
                    address: _conn.hasDiscoveredServer
                        ? _conn.discoveredAddress!
                        : (_conn.host.startsWith('192.168.') ? _conn.address : '192.168.1.3:8889'),
                    icon: Icons.wifi,
                    isHighlighted: _conn.hasDiscoveredServer,
                  ),

                  _buildPresetBtn(
                    title: 'USB Tethering',
                    subtitle: '192.168.42.129:8889  ·  USB Hotspot / RNDIS',
                    address: '192.168.42.129:8889',
                    icon: Icons.cable,
                  ),

                  const SizedBox(height: 12),

                  // Manual IP input
                  const Text(
                    'OR ENTER PC IP ADDRESS',
                    style: TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C0C0E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF27272A)),
                          ),
                          alignment: Alignment.center,
                          child: TextField(
                            controller: _addressCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: '192.168.1.x:8889',
                              hintStyle: TextStyle(color: Color(0xFF52525B), fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _connect(_addressCtrl.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFFFFF),
                          foregroundColor: const Color(0xFF000000),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          elevation: 0,
                        ),
                        child: const Text('CONNECT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),

                  if (_conn.lastError != null && !_conn.isConnected) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3F3F46), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, color: Color(0xFFE4E4E7), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'CONNECTION NOTICE',
                                style: TextStyle(
                                  color: Color(0xFFE4E4E7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _conn.lastError!,
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 10,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_conn.isConnected) ...[
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () {
                        _conn.disconnect();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFCCCCCC),
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      child: const Text('DISCONNECT FROM PC', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
