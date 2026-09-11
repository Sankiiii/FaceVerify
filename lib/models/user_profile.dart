import 'dart:convert';

class UserProfile {
  final String id;
  final String name;
  final List<double> embedding;
  final String imagePath;
  final DateTime registeredAt;

  UserProfile({
    required this.id,
    required this.name,
    required this.embedding,
    required this.imagePath,
    required this.registeredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'embedding': embedding,
      'imagePath': imagePath,
      'registeredAt': registeredAt.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      embedding: List<double>.from(
        (map['embedding'] as List).map((e) => (e as num).toDouble()),
      ),
      imagePath: map['imagePath'] as String,
      registeredAt: DateTime.parse(map['registeredAt'] as String),
    );
  }

  String toJson() => json.encode(toMap());

  factory UserProfile.fromJson(String source) =>
      UserProfile.fromMap(json.decode(source) as Map<String, dynamic>);
}
