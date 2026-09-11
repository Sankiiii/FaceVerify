import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../services/face_detector_service.dart';
import '../services/facenet_service.dart';
import '../services/storage_service.dart';
import '../widgets/face_overlay_painter.dart';

class RegistrationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceNetService faceNetService;
  final StorageService storageService;

  const RegistrationScreen({
    super.key,
    required this.cameras,
    required this.faceNetService,
    required this.storageService,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  CameraController? _controller;
  late final FaceDetectorService _detectorService;
  final TextEditingController _nameController =
      TextEditingController(text: 'Registered User');

  bool _isCameraReady = false;
  bool _isProcessing = false;
  String _statusMessage = 'Align your face in the oval';
  Color _borderColor = Colors.cyanAccent;

  @override
  void initState() {
    super.initState();
    _detectorService = FaceDetectorService();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Find front camera if available
    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _captureAndEnroll() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name or student ID')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Analyzing photo quality...';
      _borderColor = Colors.amberAccent;
    });

    try {
      // 1. Capture pristine still photo
      final file = await _controller!.takePicture();

      // 2. Run Google ML Kit face detection
      final faces = await _detectorService.detectFromFile(file.path);

      if (faces.isEmpty) {
        _showError('No face detected. Look directly at camera with proper lighting.');
        return;
      }

      if (faces.length > 1) {
        _showError('Multiple faces detected! Make sure only you are in frame.');
        return;
      }

      final face = faces.first;

      // Check pose alignment (must be frontal for high enrollment accuracy)
      final yaw = face.headEulerAngleY ?? 0.0;
      final pitch = face.headEulerAngleX ?? 0.0;

      if (yaw.abs() > 14.0 || pitch.abs() > 14.0) {
        _showError('Please look straight ahead. Do not tilt your head.');
        return;
      }

      setState(() {
        _statusMessage = 'Extracting facial biometrics...';
      });

      // 3. Read image bytes and decode
      final imageBytes = await file.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        _showError('Failed to decode captured image.');
        return;
      }

      // 4. Crop face with biometric margin
      final croppedFace = widget.faceNetService.cropFace(
        decodedImage,
        face.boundingBox,
      );

      // 5. Generate 192-D L2-normalized MobileFaceNet embedding
      final embedding = widget.faceNetService.predict(croppedFace);

      // 6. Save locally
      await widget.storageService.saveUser(
        name: name,
        embedding: embedding,
        faceImage: croppedFace,
      );

      // Cleanup raw photo
      final rawFile = File(file.path);
      if (await rawFile.exists()) {
        await rawFile.delete();
      }

      if (!mounted) return;

      setState(() {
        _borderColor = Colors.greenAccent;
        _statusMessage = 'Face enrolled successfully!';
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Colors.green),
              SizedBox(width: 8),
              Text('Enrollment Complete'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Face biometrics successfully extracted and normalized into 192-D vector space.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Registered As: $name',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Error during enrollment: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _borderColor = Colors.redAccent;
      _statusMessage = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detectorService.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Enroll Face')),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Enroll Registered Face'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera View
          CameraPreview(_controller!),

          // 2. Biometric Viewfinder Overlay
          CustomPaint(
            painter: FaceOverlayPainter(
              borderColor: _borderColor,
              borderWidth: 3.5,
            ),
          ),

          // 3. Top Info Banner
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // 4. Bottom Controls
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Full Name / Student ID',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.person, color: Colors.cyanAccent),
                      filled: true,
                      fillColor: Colors.black38,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _captureAndEnroll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.camera_alt, size: 24),
                      label: Text(
                        _isProcessing ? 'Enrolling...' : 'Capture & Save Biometrics',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
