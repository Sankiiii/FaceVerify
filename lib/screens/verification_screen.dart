import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../models/user_profile.dart';
import '../services/face_detector_service.dart';
import '../services/facenet_service.dart';
import '../services/liveness_service.dart';
import '../services/storage_service.dart';
import '../widgets/face_overlay_painter.dart';

class VerificationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceNetService faceNetService;
  final StorageService storageService;
  final List<UserProfile> candidates;

  const VerificationScreen({
    super.key,
    required this.cameras,
    required this.faceNetService,
    required this.storageService,
    required this.candidates,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  CameraController? _controller;
  late final FaceDetectorService _detectorService;
  late final LivenessService _livenessService;

  bool _isCameraReady = false;
  bool _isStreaming = false;
  bool _isVerifying = false;
  bool _sessionComplete = false;
  bool _isInStepTransition = false;

  // UI state
  String _challengeTitle = 'Look Straight Ahead';
  String _challengeInstruction = 'Align your face in the oval guide';
  IconData _challengeIcon = Icons.face;
  double _stepProgress = 0.0;
  Color _borderColor = Colors.cyanAccent;
  String? _warning;

  DateTime _lastFrameProcessedTime = DateTime.now();
  double _threshold = 0.70;

  @override
  void initState() {
    super.initState();
    _detectorService = FaceDetectorService();
    _livenessService = LivenessService();
    _loadThreshold();
    _initCamera();
  }

  Future<void> _loadThreshold() async {
    final t = await widget.storageService.getThreshold();
    if (mounted) {
      setState(() {
        _threshold = t;
      });
    }
  }

  Future<void> _initCamera() async {
    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });
      _startLivenessFlow(frontCamera);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _challengeTitle = 'Camera Error';
        _challengeInstruction = 'Failed to start camera: $e';
      });
    }
  }

  void _startLivenessFlow(CameraDescription camera) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _livenessService.startNewSession();
    _isStreaming = true;
    _sessionComplete = false;
    _isInStepTransition = false;

    // Initialize UI with first challenge
    final current = _livenessService.currentChallenge;
    setState(() {
      _challengeTitle = current.title;
      _challengeInstruction = current.instruction;
      _challengeIcon = current.icon;
      _stepProgress = 0.0;
      _borderColor = Colors.cyanAccent;
      _warning = null;
    });

    _controller!.startImageStream((CameraImage image) async {
      // 1. Throttle frame rate: process 1 frame every 130ms (prevents UI flicker & CPU load)
      final now = DateTime.now();
      if (now.difference(_lastFrameProcessedTime).inMilliseconds < 130) {
        return;
      }
      _lastFrameProcessedTime = now;

      if (!_isStreaming || _isVerifying || _sessionComplete || _isInStepTransition) return;

      final orientation = _controller?.value.deviceOrientation ??
          DeviceOrientation.portraitUp;

      final faces = await _detectorService.processCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: orientation,
      );

      if (!mounted || !_isStreaming || _isInStepTransition) return;

      final result = _livenessService.evaluateFrame(faces);

      if (result.isChallengePassed) {
        // Step Passed! Pause frame evaluation and show clear celebration banner
        _onStepCompleted(result);
      } else {
        setState(() {
          _challengeTitle = result.title;
          _challengeInstruction = result.instruction;
          _challengeIcon = result.icon;
          _stepProgress = result.currentStepProgress;
          _warning = result.warning;
          _borderColor = result.warning != null ? Colors.orangeAccent : Colors.cyanAccent;
        });
      }
    });
  }

  Future<void> _onStepCompleted(LivenessStepResult result) async {
    _isInStepTransition = true;
    HapticFeedback.mediumImpact();

    setState(() {
      _challengeTitle = result.title;
      _challengeInstruction = result.instruction;
      _challengeIcon = Icons.check_circle;
      _stepProgress = 1.0;
      _borderColor = Colors.greenAccent;
      _warning = null;
    });

    if (result.isSessionComplete) {
      // All 3 challenges complete! Transition to final capture
      _sessionComplete = true;
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        _performFinalBiometricCapture();
      }
    } else {
      // Hold success for 1.2 seconds so user clearly sees they completed this step
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_isStreaming) return;

      final nextChallenge = _livenessService.currentChallenge;
      _livenessService.resetStability();

      setState(() {
        _challengeTitle = nextChallenge.title;
        _challengeInstruction = nextChallenge.instruction;
        _challengeIcon = nextChallenge.icon;
        _stepProgress = 0.0;
        _borderColor = Colors.cyanAccent;
        _isInStepTransition = false;
      });
    }
  }

  Future<void> _performFinalBiometricCapture() async {
    setState(() {
      _isVerifying = true;
      _challengeTitle = 'Authenticating...';
      _challengeInstruction = 'Comparing biometrics with enrolled database';
      _borderColor = Colors.greenAccent;
    });

    try {
      // Stop image stream before taking high-res photo
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        _isStreaming = false;
      }

      await Future.delayed(const Duration(milliseconds: 200));

      final file = await _controller!.takePicture();
      final faces = await _detectorService.detectFromFile(file.path);

      if (faces.isEmpty) {
        _showResultSheet(
          isPassed: false,
          similarity: 0.0,
          reason: 'No face detected in capture frame.',
        );
        return;
      }

      final imageBytes = await file.readAsBytes();
      final fullImage = img.decodeImage(imageBytes);

      if (fullImage == null) {
        _showResultSheet(
          isPassed: false,
          similarity: 0.0,
          reason: 'Image decoding failed.',
        );
        return;
      }

      final croppedFace = widget.faceNetService.cropFace(
        fullImage,
        faces.first.boundingBox,
      );

      final tempLivePath = '${file.path}_face.jpg';
      await File(tempLivePath).writeAsBytes(img.encodeJpg(croppedFace));

      // Extract 192-D L2-normalized embedding
      final liveEmbedding = widget.faceNetService.predict(croppedFace);

      // Perform 1:N multi-user identification
      final multiResult = FaceNetService.identify(
        candidates: widget.candidates,
        liveEmbedding: liveEmbedding,
        threshold: _threshold,
      );

      if (!mounted) return;

      _showResultSheet(
        isPassed: multiResult.isMatch,
        similarity: multiResult.bestSimilarity,
        matchedUser: multiResult.matchedUser,
        closestCandidate: multiResult.closestCandidate,
        capturedFacePath: tempLivePath,
      );
    } catch (e) {
      if (mounted) {
        _showResultSheet(
          isPassed: false,
          similarity: 0.0,
          reason: 'Verification error: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  void _showResultSheet({
    required bool isPassed,
    required double similarity,
    UserProfile? matchedUser,
    UserProfile? closestCandidate,
    String? capturedFacePath,
    String? reason,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scorePercent = (similarity * 100).toStringAsFixed(1);
        final thresholdPercent = (_threshold * 100).toStringAsFixed(1);

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1B1C28),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Result Status Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPassed
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                ),
                child: Icon(
                  isPassed ? Icons.check_circle : Icons.cancel,
                  size: 44,
                  color: isPassed ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Text(
                isPassed ? 'VERIFIED ✓' : 'ACCESS DENIED ✗',
                style: TextStyle(
                  color: isPassed ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                isPassed
                    ? 'Identified as ${matchedUser?.name}'
                    : (reason ?? 'Biometric mismatch! You are not in the enrolled user list.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),

              const SizedBox(height: 18),

              // Diagnostic Metrics
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Similarity Score:',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          '$scorePercent%',
                          style: TextStyle(
                            color: isPassed ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Threshold Required:',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          '$thresholdPercent%',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: similarity.clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPassed ? Colors.greenAccent : Colors.redAccent,
                      ),
                      minHeight: 5,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Side-by-Side Photo Comparison
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (matchedUser != null || closestCandidate != null)
                    _buildFaceThumb(
                      isPassed ? 'Enrolled Face' : 'Closest Enrolled',
                      (matchedUser ?? closestCandidate)!.imagePath,
                    ),
                  const Icon(Icons.compare_arrows, color: Colors.white38, size: 28),
                  if (capturedFacePath != null)
                    _buildFaceThumb('Live Capture', capturedFacePath)
                  else
                    const SizedBox(width: 70, height: 70),
                ],
              ),

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Back to Home'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPassed ? Colors.greenAccent : Colors.redAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _resetAndRetry();
                      },
                      child: Text(
                        isPassed ? 'Verify Again' : 'Retry Verification',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFaceThumb(String label, String imagePath) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(imagePath),
            width: 70,
            height: 70,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 70,
              height: 70,
              color: Colors.white10,
              child: const Icon(Icons.person, color: Colors.white38),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final challenges = _livenessService.allChallenges;
    final currentIdx = _livenessService.currentStepIndex;

    return Row(
      children: List.generate(challenges.length, (index) {
        final isDone = index < currentIdx;
        final isCurrent = index == currentIdx;
        final challenge = challenges[index];

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isDone
                        ? Colors.green.withValues(alpha: 0.25)
                        : (isCurrent
                            ? Colors.cyanAccent.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDone
                          ? Colors.greenAccent
                          : (isCurrent ? Colors.cyanAccent : Colors.white12),
                      width: isCurrent ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isDone
                            ? Icons.check_circle
                            : (isCurrent ? challenge.icon : Icons.circle_outlined),
                        size: 13,
                        color: isDone
                            ? Colors.greenAccent
                            : (isCurrent ? Colors.cyanAccent : Colors.white38),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${index + 1}. ${challenge.shortLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isDone
                                ? Colors.greenAccent
                                : (isCurrent ? Colors.white : Colors.white38),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (index < challenges.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.chevron_right,
                    size: 13,
                    color: isDone ? Colors.greenAccent : Colors.white24,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  void _resetAndRetry() {
    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _startLivenessFlow(frontCamera);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detectorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Face Verification')),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    final int stepNum = _livenessService.currentStepNumber;
    final int totalSteps = _livenessService.totalSteps;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live Face Verification'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Feed
          CameraPreview(_controller!),

          // 2. Biometric Oval Viewfinder
          CustomPaint(
            painter: FaceOverlayPainter(
              borderColor: _borderColor,
              borderWidth: 3.5,
              progress: _stepProgress,
            ),
          ),

          // 3. User-Friendly Prominent Challenge Card (HUD) with 3-Step Stepper
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141520).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _borderColor.withValues(alpha: 0.7),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Visual 3-Step Stepper Bar (1. Center > 2. Action > 3. Action)
                  _buildStepIndicator(),

                  const SizedBox(height: 12),

                  // Step Badge & Warning
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _borderColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'STEP $stepNum OF $totalSteps',
                          style: TextStyle(
                            color: _borderColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (_warning != null)
                        Text(
                          _warning!,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Large Action Icon
                  Icon(
                    _challengeIcon,
                    size: 42,
                    color: _borderColor,
                  ),

                  const SizedBox(height: 6),

                  // Big Action Title
                  Text(
                    _challengeTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Clear Subtitle Instruction
                  Text(
                    _challengeInstruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Active Hold Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _stepProgress,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(_borderColor),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Verification Overlay
          if (_isVerifying)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.greenAccent),
                    SizedBox(height: 16),
                    Text(
                      'Matching face in database...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
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
