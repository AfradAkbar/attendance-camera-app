import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';
import '../constants.dart';

class FaceCaptureScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final String batchId;

  const FaceCaptureScreen({
    super.key,
    required this.student,
    required this.batchId,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  static const Color primaryColor = Color(0xFF5B8A72);

  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = 'Initializing camera...';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _statusMessage = 'No camera available');
        return;
      }

      // Use front camera
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = 'Position your face and tap Verify';
        });
      }
    } catch (e) {
      print('Camera init error: $e');
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  Future<void> _captureAndVerify() async {
    if (_cameraController == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturing...';
    });

    try {
      // Capture image
      final XFile photo = await _cameraController!.takePicture();

      setState(() => _statusMessage = 'Verifying face...');

      // Read and convert to base64
      final bytes = await File(photo.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      // Get student ID
      final studentId = widget.student['_id'] ?? 'unknown';

      // Call backend verification
      final response = await ApiService.post(kCameraVerifyFace, {
        'student_id': studentId,
        'captured_image': base64Image,
      });

      if (response == null) {
        _showFaceErrorDialog('Connection error. Please check your connection');
        return;
      }

      final verified = response['verified'] == true;
      final message = response['message'] ?? 'Unknown result';

      if (verified) {
        // Face matched! Mark attendance
        await _markAttendance();
      } else {
        // Face did not match - only show face error, no class info
        _showFaceErrorDialog(message);
      }
    } catch (e) {
      print('Verification error: $e');
      setState(() => _statusMessage = 'Verification failed');
      _showFaceErrorDialog('Could not verify face. Please try again');
    } finally {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Position your face and tap Verify';
      });
    }
  }

  Future<void> _markAttendance() async {
    final response = await ApiService.post(kCameraAttendance, {
      'student_id': widget.student['_id'],
      'batch_id': widget.batchId,
    });

    if (response == null) {
      _showFaceErrorDialog('Connection error. Could not connect to server');
      return;
    }

    final status = response['status'] ?? '';
    final message = response['message'] ?? 'Unknown result';
    final subject = response['subject'] ?? '';

    switch (status) {
      case 'on_time':
        if (mounted) {
          _showFaceVerifiedDialog(
            'Attendance Marked! ✅',
            subject.isNotEmpty ? 'Present for $subject' : message,
            navigateBack: true,
          );
        }
        break;
      case 'late':
        if (mounted) {
          _showFaceVerifiedDialog(
            'Late Arrival ⏰',
            message,
            navigateBack: true,
          );
        }
        break;
      case 'no_class':
        if (mounted) {
          // Face was verified but no class - show green tick + no class message
          _showFaceVerifiedDialog('No Class 📚', message, navigateBack: false);
        }
        break;
      case 'already_marked':
        if (mounted) {
          _showFaceVerifiedDialog(
            'Already Marked ✓',
            message,
            navigateBack: true,
          );
        }
        break;
      default:
        if (response['success'] == true) {
          if (mounted) {
            _showFaceVerifiedDialog('Success', message, navigateBack: true);
          }
        } else {
          await _sendAttendanceRequest('Failed to mark attendance');
        }
    }
  }

  Future<void> _sendAttendanceRequest(String reason) async {
    final now = DateTime.now();
    final hour = now.hour >= 9 ? (now.hour - 8) : 1;

    await ApiService.post(kCameraAttendanceRequest, {
      'student_id': widget.student['_id'],
      'batch_id': widget.batchId,
      'date': DateFormat('yyyy-MM-dd').format(now),
      'hour': hour,
      'reason': reason,
    });

    if (mounted) {
      _showInfoDialog(
        'Request Sent',
        'Verification request sent to class incharge for approval.',
      );
    }
  }

  /// Shows dialog when face is verified with class status
  void _showFaceVerifiedDialog(
    String title,
    String message, {
    required bool navigateBack,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Green tick for face verified
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 50,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Face Verified ✓',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              widget.student['name'] ?? 'Student',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (navigateBack) {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                navigateBack ? 'Done' : 'OK',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows dialog when face verification fails - no class info shown
  void _showFaceErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 50,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.student['name'] ?? 'Student',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Face Error',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$message. Please try again or request manual verification.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows info dialog for general messages (like request sent)
  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline,
                size: 50,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.student['name'] ?? 'Verify Face'),
      ),
      body: Stack(
        children: [
          // Camera Preview
          if (_isInitialized && _cameraController != null)
            Center(child: CameraPreview(_cameraController!))
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          // Face Frame Overlay
          Center(
            child: Container(
              height: 280,
              width: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(120),
              ),
            ),
          ),

          // Processing Indicator
          if (_isProcessing)
            Center(
              child: Container(
                height: 100,
                width: 100,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Verify Button
                  if (_isInitialized && !_isProcessing)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _captureAndVerify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Verify Face',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Manual Request Button
                  TextButton(
                    onPressed: () => _sendAttendanceRequest('Manual request'),
                    child: const Text(
                      'Can\'t verify? Send request to teacher',
                      style: TextStyle(
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
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
