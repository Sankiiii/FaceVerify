import 'package:flutter_test/flutter_test.dart';
import 'package:face_verification/models/user_profile.dart';
import 'package:face_verification/services/facenet_service.dart';

void main() {
  group('Biometric ArcFace Math & L2 Normalization Tests', () {
    test('L2 Normalization produces unit length vector', () {
      final rawVector = [3.0, 4.0, 0.0];
      final normalized = FaceNetService.l2Normalize(rawVector);

      expect(normalized.length, 3);
      expect(normalized[0], closeTo(0.6, 0.0001));
      expect(normalized[1], closeTo(0.8, 0.0001));
      expect(normalized[2], closeTo(0.0, 0.0001));

      // Norm of normalized vector must equal 1.0
      final norm = normalized[0] * normalized[0] +
          normalized[1] * normalized[1] +
          normalized[2] * normalized[2];
      expect(norm, closeTo(1.0, 0.0001));
    });

    test('Cosine similarity of identical faces is 1.0', () {
      final v1 = [0.5, 0.5, 0.5, 0.5];
      final v2 = [0.5, 0.5, 0.5, 0.5];

      final similarity = FaceNetService.cosineSimilarity(v1, v2);
      expect(similarity, closeTo(1.0, 0.0001));

      final result = FaceNetService.verify(
        registeredEmbedding: v1,
        liveEmbedding: v2,
        threshold: 0.70,
      );
      expect(result.isMatch, isTrue);
    });

    test('Cosine similarity of different faces (friend/stranger) is correctly rejected', () {
      final genuineUser = [1.0, 0.0, 0.0, 0.0];
      final friendFace = [0.2, 0.9, 0.3, 0.1];

      final similarity = FaceNetService.cosineSimilarity(genuineUser, friendFace);
      expect(similarity, lessThan(0.40));

      final result = FaceNetService.verify(
        registeredEmbedding: genuineUser,
        liveEmbedding: friendFace,
        threshold: 0.70,
      );
      expect(result.isMatch, isFalse);
    });

    test('1:N Multi-User Identification matches correct candidate and rejects imposters', () {
      final userAlice = UserProfile(
        id: '1',
        name: 'Alice',
        embedding: [1.0, 0.0, 0.0, 0.0],
        imagePath: '/alice.jpg',
        registeredAt: DateTime.now(),
      );

      final userBob = UserProfile(
        id: '2',
        name: 'Bob',
        embedding: [0.0, 1.0, 0.0, 0.0],
        imagePath: '/bob.jpg',
        registeredAt: DateTime.now(),
      );

      final candidates = [userAlice, userBob];

      // Test 1: Alice scans live
      final liveAlice = [0.95, 0.05, 0.0, 0.0];
      final matchAlice = FaceNetService.identify(
        candidates: candidates,
        liveEmbedding: liveAlice,
        threshold: 0.70,
      );
      expect(matchAlice.isMatch, isTrue);
      expect(matchAlice.matchedUser?.name, 'Alice');
      expect(matchAlice.bestSimilarity, greaterThan(0.90));

      // Test 2: Unenrolled Friend / Imposter scans live
      final imposterFriend = [0.1, 0.1, 0.9, 0.3];
      final matchImposter = FaceNetService.identify(
        candidates: candidates,
        liveEmbedding: imposterFriend,
        threshold: 0.70,
      );
      expect(matchImposter.isMatch, isFalse);
      expect(matchImposter.matchedUser, isNull);
      expect(matchImposter.bestSimilarity, lessThan(0.40));
    });

    test('UserProfile JSON serialization and deserialization', () {
      final profile = UserProfile(
        id: '12345',
        name: 'John Doe',
        embedding: [0.1, 0.2, 0.3],
        imagePath: '/path/to/face.jpg',
        registeredAt: DateTime(2026, 1, 1),
      );

      final jsonStr = profile.toJson();
      final restored = UserProfile.fromJson(jsonStr);

      expect(restored.id, '12345');
      expect(restored.name, 'John Doe');
      expect(restored.embedding, [0.1, 0.2, 0.3]);
      expect(restored.imagePath, '/path/to/face.jpg');
    });
  });
}
