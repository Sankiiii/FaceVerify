import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  centerFace,
  turnHeadLeft,
  turnHeadRight,
  lookUp,
  blink,
}

extension LivenessChallengeExtension on LivenessChallenge {
  String get title {
    switch (this) {
      case LivenessChallenge.centerFace:
        return 'Look Straight Ahead';
      case LivenessChallenge.turnHeadLeft:
        return 'Turn Head Left';
      case LivenessChallenge.turnHeadRight:
        return 'Turn Head Right';
      case LivenessChallenge.lookUp:
        return 'Tilt Chin Up';
      case LivenessChallenge.blink:
        return 'Blink Your Eyes';
    }
  }

  String get shortLabel {
    switch (this) {
      case LivenessChallenge.centerFace:
        return 'Center';
      case LivenessChallenge.turnHeadLeft:
        return 'Turn Left';
      case LivenessChallenge.turnHeadRight:
        return 'Turn Right';
      case LivenessChallenge.lookUp:
        return 'Tilt Up';
      case LivenessChallenge.blink:
        return 'Blink';
    }
  }

  String get instruction {
    switch (this) {
      case LivenessChallenge.centerFace:
        return 'Hold your face inside the oval and look directly at camera';
      case LivenessChallenge.turnHeadLeft:
        return 'Turn your head slowly towards your left shoulder';
      case LivenessChallenge.turnHeadRight:
        return 'Turn your head slowly towards your right shoulder';
      case LivenessChallenge.lookUp:
        return 'Tilt your chin slightly upwards';
      case LivenessChallenge.blink:
        return 'Close both eyes and open them naturally';
    }
  }

  IconData get icon {
    switch (this) {
      case LivenessChallenge.centerFace:
        return Icons.face;
      case LivenessChallenge.turnHeadLeft:
        return Icons.arrow_circle_left_outlined;
      case LivenessChallenge.turnHeadRight:
        return Icons.arrow_circle_right_outlined;
      case LivenessChallenge.lookUp:
        return Icons.arrow_circle_up_outlined;
      case LivenessChallenge.blink:
        return Icons.remove_red_eye_outlined;
    }
  }
}

class LivenessStepResult {
  final String title;
  final String instruction;
  final IconData icon;
  final double currentStepProgress;
  final bool isChallengePassed;
  final bool isSessionComplete;
  final String? warning;

  LivenessStepResult({
    required this.title,
    required this.instruction,
    required this.icon,
    required this.currentStepProgress,
    required this.isChallengePassed,
    required this.isSessionComplete,
    this.warning,
  });
}

class LivenessService {
  final List<LivenessChallenge> _challenges = [];
  int _currentChallengeIndex = 0;

  // Stability counters: requires holding the gesture for ~3 consecutive frames (300-400ms)
  int _stableFrames = 0;
  static const int _requiredStableFrames = 3;

  // Blink state machine
  bool _blinkDetectedClosed = false;
  int? _lockedTrackingId;

  List<LivenessChallenge> get allChallenges => List.unmodifiable(_challenges);

  LivenessChallenge get currentChallenge =>
      _challenges.isNotEmpty && _currentChallengeIndex < _challenges.length
          ? _challenges[_currentChallengeIndex]
          : LivenessChallenge.centerFace;

  int get currentStepNumber => _currentChallengeIndex + 1;
  int get currentStepIndex => _currentChallengeIndex;
  int get totalSteps => _challenges.length;

  void startNewSession() {
    _challenges.clear();
    _currentChallengeIndex = 0;
    _stableFrames = 0;
    _blinkDetectedClosed = false;
    _lockedTrackingId = null;

    final random = Random();

    // Step 1: Always Center Face (calibrates user in oval)
    _challenges.add(LivenessChallenge.centerFace);

    // Step 2: Head Movement Challenge (Turn Right or Turn Left)
    final headTurns = [
      LivenessChallenge.turnHeadRight,
      LivenessChallenge.turnHeadLeft,
    ]..shuffle(random);
    _challenges.add(headTurns.first);

    // Step 3: Facial Action Challenge (Blink Eyes or Tilt Up)
    final facialActions = [
      LivenessChallenge.blink,
      LivenessChallenge.lookUp,
    ]..shuffle(random);
    _challenges.add(facialActions.first);
  }

  void resetStability() {
    _stableFrames = 0;
    _blinkDetectedClosed = false;
  }

  LivenessStepResult evaluateFrame(List<Face> faces) {
    final current = currentChallenge;

    if (faces.isEmpty) {
      _stableFrames = 0;
      return LivenessStepResult(
        title: current.title,
        instruction: 'Position your face in the oval guide',
        icon: current.icon,
        currentStepProgress: 0.0,
        isChallengePassed: false,
        isSessionComplete: false,
        warning: 'Face not detected',
      );
    }

    if (faces.length > 1) {
      _stableFrames = 0;
      return LivenessStepResult(
        title: 'Only 1 Person Allowed',
        instruction: 'Multiple faces in frame. Please ensure only you are visible.',
        icon: Icons.group,
        currentStepProgress: 0.0,
        isChallengePassed: false,
        isSessionComplete: false,
        warning: 'Multiple faces detected',
      );
    }

    final face = faces.first;

    // Continuous tracking validation
    if (face.trackingId != null) {
      if (_lockedTrackingId == null) {
        _lockedTrackingId = face.trackingId;
      } else if (_lockedTrackingId != face.trackingId) {
        _stableFrames = 0;
        return LivenessStepResult(
          title: 'Face Changed',
          instruction: 'Please stay in front of the camera',
          icon: Icons.warning_amber_rounded,
          currentStepProgress: 0.0,
          isChallengePassed: false,
          isSessionComplete: false,
          warning: 'Face tracking swapped',
        );
      }
    }

    final double yaw = face.headEulerAngleY ?? 0.0;
    final double pitch = face.headEulerAngleX ?? 0.0;
    final double? leftEye = face.leftEyeOpenProbability;
    final double? rightEye = face.rightEyeOpenProbability;

    bool conditionMetThisFrame = false;
    double progress = 0.0;

    switch (current) {
      case LivenessChallenge.centerFace:
        final bool centered = yaw.abs() < 12.0 && pitch.abs() < 12.0;
        if (centered) {
          conditionMetThisFrame = true;
          progress = 1.0;
        } else {
          progress = max(0.0, 1.0 - (yaw.abs() + pitch.abs()) / 30.0);
        }
        break;

      case LivenessChallenge.turnHeadLeft:
        if (yaw < -16.0 || yaw > 16.0) {
          conditionMetThisFrame = true;
          progress = 1.0;
        } else {
          progress = (yaw.abs() / 16.0).clamp(0.0, 0.85);
        }
        break;

      case LivenessChallenge.turnHeadRight:
        if (yaw > 16.0 || yaw < -16.0) {
          conditionMetThisFrame = true;
          progress = 1.0;
        } else {
          progress = (yaw.abs() / 16.0).clamp(0.0, 0.85);
        }
        break;

      case LivenessChallenge.lookUp:
        if (pitch > 13.0) {
          conditionMetThisFrame = true;
          progress = 1.0;
        } else {
          progress = (pitch / 13.0).clamp(0.0, 0.85);
        }
        break;

      case LivenessChallenge.blink:
        if (leftEye != null && rightEye != null) {
          final isClosed = leftEye < 0.20 && rightEye < 0.20;
          final isOpen = leftEye > 0.65 && rightEye > 0.65;

          if (isClosed) {
            _blinkDetectedClosed = true;
            progress = 0.6;
          } else if (_blinkDetectedClosed && isOpen) {
            conditionMetThisFrame = true;
            progress = 1.0;
          } else {
            progress = _blinkDetectedClosed ? 0.6 : 0.2;
          }
        }
        break;
    }

    if (conditionMetThisFrame) {
      _stableFrames++;
    } else {
      if (_stableFrames > 0) _stableFrames--;
    }

    final bool passed = _stableFrames >= _requiredStableFrames;

    if (passed) {
      _stableFrames = 0;
      _blinkDetectedClosed = false;
      _currentChallengeIndex++;

      final isDone = _currentChallengeIndex >= _challenges.length;

      return LivenessStepResult(
        title: isDone ? 'All 3 Steps Passed! ✓' : 'Step Passed! ✓',
        instruction: isDone
            ? 'Hold still for final biometric capture'
            : 'Great! Getting next challenge...',
        icon: Icons.check_circle,
        currentStepProgress: 1.0,
        isChallengePassed: true,
        isSessionComplete: isDone,
      );
    }

    return LivenessStepResult(
      title: current.title,
      instruction: current.instruction,
      icon: current.icon,
      currentStepProgress: progress,
      isChallengePassed: false,
      isSessionComplete: false,
    );
  }
}
