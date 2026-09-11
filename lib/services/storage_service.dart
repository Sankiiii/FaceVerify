import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class StorageService {
  static const String _usersListKey = 'registered_users_list';
  static const String _thresholdKey = 'face_matching_threshold';

  /// Saves a new user profile (or updates existing) and persists face picture locally
  Future<UserProfile> saveUser({
    required String name,
    required List<double> embedding,
    required img.Image faceImage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final docsDir = await getApplicationDocumentsDirectory();

    final userId = DateTime.now().millisecondsSinceEpoch.toString();
    final imagePath = '${docsDir.path}/registered_face_$userId.jpg';

    // Save image to local disk
    final jpgBytes = img.encodeJpg(faceImage, quality: 90);
    final file = File(imagePath);
    await file.writeAsBytes(jpgBytes);

    final newUser = UserProfile(
      id: userId,
      name: name,
      embedding: embedding,
      imagePath: imagePath,
      registeredAt: DateTime.now(),
    );

    final users = await getUsers();
    users.add(newUser);

    final jsonList = users.map((u) => u.toMap()).toList();
    await prefs.setString(_usersListKey, json.encode(jsonList));

    return newUser;
  }

  /// Retrieves all currently enrolled users
  Future<List<UserProfile>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_usersListKey);

    if (rawJson == null) {
      // Check legacy single-user key for backward compatibility
      final legacy = prefs.getString('registered_user_profile');
      if (legacy != null) {
        try {
          final user = UserProfile.fromJson(legacy);
          await prefs.setString(_usersListKey, json.encode([user.toMap()]));
          await prefs.remove('registered_user_profile');
          return [user];
        } catch (_) {}
      }
      return [];
    }

    try {
      final decoded = json.decode(rawJson) as List;
      return decoded.map((item) => UserProfile.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Deletes a specific enrolled user by ID and cleans up their photo file
  Future<void> deleteUser(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final users = await getUsers();

    final userToDelete = users.where((u) => u.id == id).firstOrNull;
    if (userToDelete != null) {
      final file = File(userToDelete.imagePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    users.removeWhere((u) => u.id == id);
    final jsonList = users.map((u) => u.toMap()).toList();
    await prefs.setString(_usersListKey, json.encode(jsonList));
  }

  /// Clears all enrolled users and their images
  Future<void> clearAllUsers() async {
    final users = await getUsers();
    for (final u in users) {
      final file = File(u.imagePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usersListKey);
    await prefs.remove('registered_user_profile');
  }

  /// Gets the currently configured matching threshold (default 0.70)
  Future<double> getThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_thresholdKey) ?? 0.70;
  }

  /// Sets custom matching threshold
  Future<void> setThreshold(double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_thresholdKey, threshold);
  }
}
