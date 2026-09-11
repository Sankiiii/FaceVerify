import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/facenet_service.dart';
import 'services/storage_service.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait for consistent face geometry
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Failed to load cameras: $e');
  }

  // Pre-initialize MobileFaceNet TFLite interpreter
  final faceNetService = FaceNetService();
  try {
    await faceNetService.initialize();
  } catch (e) {
    debugPrint('Warning: FaceNet initialization deferred: $e');
  }

  final storageService = StorageService();

  runApp(FaceVerificationApp(
    cameras: _cameras,
    faceNetService: faceNetService,
    storageService: storageService,
  ));
}

class FaceVerificationApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final FaceNetService faceNetService;
  final StorageService storageService;

  const FaceVerificationApp({
    super.key,
    required this.cameras,
    required this.faceNetService,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceBiometrics AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0E15),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.tealAccent,
          surface: Color(0xFF1B1C28),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: HomeScreen(
        cameras: cameras,
        faceNetService: faceNetService,
        storageService: storageService,
      ),
    );
  }
}
