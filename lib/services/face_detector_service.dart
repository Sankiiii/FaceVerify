import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  late final FaceDetector _detector;
  bool _isProcessing = false;

  FaceDetectorService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Eye open probability & smiling
        enableLandmarks: true,       // Eye, nose, ear, mouth positions
        enableContours: false,
        enableTracking: true,        // Track face identity across frames
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );
  }

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Detects faces from a static image file on disk
  Future<List<Face>> detectFromFile(String filePath) async {
    final inputImage = InputImage.fromFilePath(filePath);
    return await _detector.processImage(inputImage);
  }

  /// Detects faces from a live camera frame
  Future<List<Face>> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_isProcessing) return [];
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: deviceOrientation,
      );

      if (inputImage == null) return [];
      return await _detector.processImage(inputImage);
    } catch (e) {
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[deviceOrientation];
      if (rotationCompensation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Handle single or multi-plane camera formats
    Uint8List allBytes;
    int bytesPerRow = 0;

    if (image.planes.length == 1) {
      allBytes = image.planes[0].bytes;
      bytesPerRow = image.planes[0].bytesPerRow;
    } else {
      // Concatenate planes for YUV420_888 if necessary
      final writeBuffer = WriteBuffer();
      for (final plane in image.planes) {
        writeBuffer.putUint8List(plane.bytes);
      }
      allBytes = writeBuffer.done().buffer.asUint8List();
      bytesPerRow = image.planes[0].bytesPerRow;
    }

    return InputImage.fromBytes(
      bytes: allBytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  void dispose() {
    _detector.close();
  }
}
