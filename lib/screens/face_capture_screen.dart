import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:face_verification/face_verification.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
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
  String _statusMessage = 'Initializing...';
  bool _referenceImageReady = false;
  String? _referenceImagePath;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _prepareReferenceImage();
    await _initializeCamera();
  }

  Future<void> _prepareReferenceImage() async {
    setState(() => _statusMessage = 'Preparing verification...');

    final imageUrl = widget.student['image_url'];
    if (imageUrl == null || imageUrl.toString().isEmpty) {
      setState(() {
        _statusMessage = 'No reference image available';
        _referenceImageReady = false;
      });
      return;
    }

    try {
      // Download reference image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image');
      }

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final studentId = widget.student['_id'] ?? 'unknown';
      final refImagePath = '${tempDir.path}/ref_$studentId.jpg';
      final refFile = File(refImagePath);
      await refFile.writeAsBytes(response.bodyBytes);

      // Clear any previous registration for this student
      await FaceVerification.instance.deleteRecord(studentId);

      // Register the reference face
      await FaceVerification.instance.registerFromImagePath(
        id: studentId,
        imagePath: refImagePath,
        imageId: 'reference',
      );

      setState(() {
        _referenceImagePath = refImagePath;
        _referenceImageReady = true;
        _statusMessage = 'Ready to verify';
      });
    } catch (e) {
      print('Error preparing reference image: $e');
      setState(() {
        _statusMessage = 'Error loading reference image';
        _referenceImageReady = false;
      });
    }
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
          if (_referenceImageReady) {
            _statusMessage = 'Position your face and tap Verify';
          }
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

      // Get student ID
      final studentId = widget.student['_id'] ?? 'unknown';

      // Verify the captured face against registered reference
      final matchId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: photo.path,
        threshold: 0.70,
        staffId: studentId, // Only compare against this specific student
      );

      if (matchId != null && matchId == studentId) {
        // Face matched! Mark attendance
        await _markAttendance();
      } else {
        // Face did not match
        _showResultDialog(
          false,
          'Face does not match',
          'The captured face does not match the registered student photo. Please try again or request manual verification.',
        );
      }
    } catch (e) {
      print('Verification error: $e');
      setState(() => _statusMessage = 'Verification failed');
      _showResultDialog(
        false,
        'Verification Error',
        'Could not verify face. Please try again or request manual verification.',
      );
    } finally {
      setState(() {
        _isProcessing = false;
        if (_referenceImageReady) {
          _statusMessage = 'Position your face and tap Verify';
        }
      });
    }
  }

  Future<void> _markAttendance() async {
    final now = DateTime.now();
    final hour = now.hour >= 9 ? (now.hour - 8) : 1;

    final response = await ApiService.post(kCameraAttendance, {
      'student_id': widget.student['_id'],
      'batch_id': widget.batchId,
      'date': DateFormat('yyyy-MM-dd').format(now),
      'hour': hour,
    });

    if (response != null && response['success'] == true) {
      if (mounted) {
        _showResultDialog(
          true,
          'Attendance Marked!',
          'Face verified successfully. Attendance has been recorded.',
        );
      }
    } else {
      await _sendAttendanceRequest('Failed to mark attendance');
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
      _showResultDialog(
        false,
        'Request Sent',
        'Verification request sent to class incharge for approval.',
      );
    }
  }

  void _showResultDialog(bool success, String title, String message) {
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
                color: success ? Colors.green.shade50 : Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                success ? Icons.check_circle : Icons.error_outline,
                size: 50,
                color: success ? Colors.green : Colors.red,
              ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: success ? Colors.green : Colors.red,
              ),
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
                if (success) {
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
                success ? 'Done' : 'Try Again',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    // Clean up reference image
    if (_referenceImagePath != null) {
      File(
        _referenceImagePath!,
      ).delete().catchError((_) => File(_referenceImagePath!));
    }
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
                border: Border.all(
                  color: _referenceImageReady ? Colors.green : Colors.white,
                  width: 3,
                ),
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
                  if (_isInitialized && _referenceImageReady && !_isProcessing)
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

                  // No reference image - show request button
                  if (!_referenceImageReady && _isInitialized)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () =>
                            _sendAttendanceRequest('No reference image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Request Manual Verification',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Manual Request Button
                  if (_referenceImageReady)
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
