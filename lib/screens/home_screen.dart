import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/facenet_service.dart';
import '../services/storage_service.dart';
import 'registration_screen.dart';
import 'verification_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceNetService faceNetService;
  final StorageService storageService;

  const HomeScreen({
    super.key,
    required this.cameras,
    required this.faceNetService,
    required this.storageService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<UserProfile> _enrolledUsers = [];
  bool _isLoading = true;
  double _threshold = 0.70;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    final users = await widget.storageService.getUsers();
    final t = await widget.storageService.getThreshold();

    if (mounted) {
      setState(() {
        _enrolledUsers = users;
        _threshold = t;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteUser(UserProfile user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${user.name}?'),
        content: const Text(
          'This will remove this enrolled person from the database. Their face will no longer be recognized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.storageService.deleteUser(user.id);
      await _loadState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} removed from enrolled list.')),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Enrolled Faces?'),
        content: const Text(
          'This will delete all enrolled profiles. You will need to enroll faces again to verify.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.storageService.clearAllUsers();
      await _loadState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All enrolled profiles cleared.')),
        );
      }
    }
  }

  void _openRegistration() async {
    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cameras found on device.')),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RegistrationScreen(
          cameras: widget.cameras,
          faceNetService: widget.faceNetService,
          storageService: widget.storageService,
        ),
      ),
    );

    if (result == true) {
      await _loadState();
    }
  }

  void _openVerification() {
    if (_enrolledUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enroll at least one face before verifying.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cameras found on device.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificationScreen(
          cameras: widget.cameras,
          faceNetService: widget.faceNetService,
          storageService: widget.storageService,
          candidates: _enrolledUsers,
        ),
      ),
    );
  }

  Future<void> _updateThreshold(double val) async {
    await widget.storageService.setThreshold(val);
    setState(() {
      _threshold = val;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      appBar: AppBar(
        title: const Text(
          'FaceBiometrics AI',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_enrolledUsers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              tooltip: 'Clear All Users',
              onPressed: _clearAll,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadState,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Status Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield, color: Colors.cyanAccent, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '100% Offline Biometrics • 1:N Identification',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 2. Primary Start Verification Button
                  SizedBox(
                    height: 58,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _enrolledUsers.isNotEmpty
                            ? Colors.cyanAccent
                            : Colors.white24,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: _enrolledUsers.isNotEmpty ? _openVerification : null,
                      icon: const Icon(Icons.face, size: 28),
                      label: Text(
                        _enrolledUsers.isNotEmpty
                            ? 'Start Face Verification (${_enrolledUsers.length})'
                            : 'Start Verification',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Enroll New Person Button
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _openRegistration,
                      icon: const Icon(Icons.person_add_alt_1, color: Colors.cyanAccent, size: 20),
                      label: const Text(
                        '+ Enroll New Person',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 4. Enrolled Users List Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enrolled Profiles (${_enrolledUsers.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_enrolledUsers.isNotEmpty)
                        const Text(
                          '192-D Vectors Ready',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  _buildEnrolledUsersSection(),

                  const SizedBox(height: 24),

                  // 5. Threshold Settings
                  _buildThresholdSettings(),

                  const SizedBox(height: 20),

                  // 6. Diagnostics Info
                  _buildDiagnosticsInfo(),
                ],
              ),
            ),
    );
  }

  Widget _buildEnrolledUsersSection() {
    if (_enrolledUsers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1C28),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: const Icon(Icons.people_outline, size: 34, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            const Text(
              'No People Enrolled Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "+ Enroll New Person" to add yourself and your team members.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _enrolledUsers.map((user) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1C28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(user.imagePath),
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 54,
                    height: 54,
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: Colors.cyanAccent),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enrolled: ${user.registeredAt.toLocal().toString().split(' ')[0]}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete User',
                onPressed: () => _deleteUser(user),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildThresholdSettings() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, color: Colors.cyanAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Matching Threshold',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                '${(_threshold * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Enrolled persons score 80-92%. Unenrolled friends/imposters score 15-35%.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(
                value: 0.65,
                label: Text('Relaxed\n65%', textAlign: TextAlign.center),
              ),
              ButtonSegment(
                value: 0.70,
                label: Text('Standard\n70%', textAlign: TextAlign.center),
              ),
              ButtonSegment(
                value: 0.74,
                label: Text('Strict\n74%', textAlign: TextAlign.center),
              ),
            ],
            selected: {_threshold},
            onSelectionChanged: (Set<double> newSelection) {
              _updateThreshold(newSelection.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.cyanAccent;
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return Colors.white70;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'Smooth & User-Friendly Liveness Flow',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• 2 clear, comfortable challenge steps with generous hold time.\n'
            '• 1.2s celebratory checkmark pause between steps so you can read and prepare.\n'
            '• Frame debouncing eliminates rapid text jitter and stabilizes on-screen instructions.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
