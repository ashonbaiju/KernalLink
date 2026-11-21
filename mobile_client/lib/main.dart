import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/connection_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConnectionService().init();
  // Auto-connect to last saved address (defaults to 127.0.0.1:8889 USB ADB)
  ConnectionService().connect(ConnectionService().address);

  // Allow portrait and landscape by default on Home Screen
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const KernalLinkApp());
}

class KernalLinkApp extends StatelessWidget {
  const KernalLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KernalLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          surface: Color(0xFF09090B),
          onPrimary: Color(0xFF000000),
          onSurface: Color(0xFFFFFFFF),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}
