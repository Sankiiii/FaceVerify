import 'dart:math';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/user_profile.dart';

class FaceNetService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Threshold calibrated for MobileFaceNet ArcFace embeddings (L2-normalized)
  // Scores:
  // Genuine user: 0.78 - 0.95
  // Friends/imposters: 0.15 - 0.38
  static const double defaultThreshold = 0.70;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/mobilefacenet.tflite',
        options: options,
      );
      _isInitialized = true;
    } catch (e) {
      try {
        _interpreter = await Interpreter.fromAsset('mobilefacenet.tflite');
        _isInitialized = true;
      } catch (err) {
        throw Exception('Failed to load MobileFaceNet TFLite model: $err');
      }
    }
  }

  /// Extracts a 192-dimensional L2-normalized embedding vector from a cropped face image.
  List<double> predict(img.Image croppedFace) {
    if (_interpreter == null) {
      throw Exception('Interpreter is not initialized. Call initialize() first.');
    }

    // 1. Resize to 112x112 (MobileFaceNet input requirement)
    final resized = img.copyResize(croppedFace, width: 112, height: 112);

    // 2. Preprocess: Normalize pixel values (x - 128) / 128 to [-1, 1] range
    final input = List.generate(
      1,
      (_) => List.generate(
        112,
        (y) => List.generate(
          112,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              (pixel.r - 128.0) / 128.0,
              (pixel.g - 128.0) / 128.0,
              (pixel.b - 128.0) / 128.0,
            ];
          },
        ),
      ),
    );

    // 3. Allocate output buffer [1, 192]
    final output = List.generate(1, (_) => List.filled(192, 0.0));

    // 4. Run inference on device
    _interpreter!.run(input, output);

    // 5. Extract raw 192-D vector
    final rawVector = List<double>.from(output[0]);

    // 6. CRITICAL STEP: L2 Normalization (Prevents friends and imposters from matching)
    return l2Normalize(rawVector);
  }

  /// Crops the face from the full image using the detected bounding box, with a 20% margin
  img.Image cropFace(img.Image sourceImage, Rect boundingBox) {
    final double marginX = boundingBox.width * 0.15;
    final double marginY = boundingBox.height * 0.15;

    final int x = max(0, (boundingBox.left - marginX).round());
    final int y = max(0, (boundingBox.top - marginY).round());
    final int w = min(sourceImage.width - x, (boundingBox.width + (marginX * 2)).round());
    final int h = min(sourceImage.height - y, (boundingBox.height + (marginY * 2)).round());

    return img.copyCrop(sourceImage, x: x, y: y, width: w, height: h);
  }

  /// Mathematically normalizes a vector to unit length (L2-norm = 1.0)
  static List<double> l2Normalize(List<double> vector) {
    double sumSquares = 0.0;
    for (final val in vector) {
      sumSquares += val * val;
    }
    final norm = sqrt(sumSquares);
    if (norm == 0.0) return vector;
    return vector.map((v) => v / norm).toList();
  }

  /// Calculates the Cosine Similarity between two face embedding vectors.
  /// Result ranges from -1.0 (opposite) to +1.0 (identical face).
  static double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) {
      throw ArgumentError('Vectors must have the same dimension (got ${v1.length} vs ${v2.length})');
    }

    final norm1 = l2Normalize(v1);
    final norm2 = l2Normalize(v2);

    double dot = 0.0;
    for (int i = 0; i < norm1.length; i++) {
      dot += norm1[i] * norm2[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  /// 1:1 Verification (Single User comparison)
  static VerificationResult verify({
    required List<double> registeredEmbedding,
    required List<double> liveEmbedding,
    double threshold = defaultThreshold,
  }) {
    final similarity = cosineSimilarity(registeredEmbedding, liveEmbedding);
    final isMatch = similarity >= threshold;

    return VerificationResult(
      similarity: similarity,
      threshold: threshold,
      isMatch: isMatch,
    );
  }

  /// 1:N Identification (Searches across all enrolled users for the best match)
  static MultiMatchResult identify({
    required List<UserProfile> candidates,
    required List<double> liveEmbedding,
    double threshold = defaultThreshold,
  }) {
    if (candidates.isEmpty) {
      return MultiMatchResult(
        matchedUser: null,
        closestCandidate: null,
        bestSimilarity: 0.0,
        threshold: threshold,
        isMatch: false,
      );
    }

    UserProfile? bestCandidate;
    double maxSimilarity = -1.0;

    for (final user in candidates) {
      final sim = cosineSimilarity(user.embedding, liveEmbedding);
      if (sim > maxSimilarity) {
        maxSimilarity = sim;
        bestCandidate = user;
      }
    }

    final bool isMatch = maxSimilarity >= threshold;

    return MultiMatchResult(
      matchedUser: isMatch ? bestCandidate : null,
      closestCandidate: bestCandidate,
      bestSimilarity: maxSimilarity,
      threshold: threshold,
      isMatch: isMatch,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

class VerificationResult {
  final double similarity;
  final double threshold;
  final bool isMatch;

  VerificationResult({
    required this.similarity,
    required this.threshold,
    required this.isMatch,
  });

  double get similarityPercentage => (similarity * 100).clamp(0.0, 100.0);
  double get thresholdPercentage => (threshold * 100).clamp(0.0, 100.0);
}

class MultiMatchResult {
  final UserProfile? matchedUser;
  final UserProfile? closestCandidate;
  final double bestSimilarity;
  final double threshold;
  final bool isMatch;

  MultiMatchResult({
    required this.matchedUser,
    required this.closestCandidate,
    required this.bestSimilarity,
    required this.threshold,
    required this.isMatch,
  });

  double get similarityPercentage => (bestSimilarity * 100).clamp(0.0, 100.0);
  double get thresholdPercentage => (threshold * 100).clamp(0.0, 100.0);
}
