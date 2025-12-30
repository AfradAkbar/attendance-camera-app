import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _faceDetected = false;
  String _statusMessage = 'Initializing camera...';

  int _countdown = 3;
  Timer? _countdownTimer;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
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
          _statusMessage = 'Position your face in the frame';
        });
        _startFaceDetection();
      }
    } catch (e) {
      print('Camera init error: $e');
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((image) async {
      if (_isProcessing || _isCapturing) return;
      _isProcessing = true;

      try {
        final inputImage = _convertCameraImage(image);
        if (inputImage != null) {
          final faces = await _faceDetector!.processImage(inputImage);

          if (mounted) {
            setState(() {
              _faceDetected = faces.isNotEmpty;
              if (_faceDetected && !_isCapturing) {
                _statusMessage = 'Face detected! Hold still...';
                _startCountdown();
              } else if (!_faceDetected) {
                _statusMessage = 'Position your face in the frame';
                _cancelCountdown();
              }
            });
          }
        }
      } catch (e) {
        print('Face detection error: $e');
      }

      _isProcessing = false;
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );
      if (rotation == null) return null;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  void _startCountdown() {
    if (_countdownTimer != null || _isCapturing) return;

    setState(() {
      _countdown = 3;
      _isCapturing = true;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        _countdownTimer = null;
        _captureAndVerify();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _countdown = 3;
      });
    }
  }

  Future<void> _captureAndVerify() async {
    if (_cameraController == null) return;

    try {
      await _cameraController!.stopImageStream();

      setState(() => _statusMessage = 'Verifying face...');

      // For demo: We'll do a simple comparison
      // In production, this would use face embeddings
      final hasStudentImage = widget.student['image_url'] != null;

      if (!hasStudentImage) {
        // No reference image - send request to class incharge
        await _sendAttendanceRequest('No reference image available');
        return;
      }

      // Simulate face matching (in production, use ML model)
      // For demo, we'll assume face matches if detected
      await Future.delayed(const Duration(seconds: 1));

      // Mark attendance
      await _markAttendance();
    } catch (e) {
      print('Capture error: $e');
      await _sendAttendanceRequest('Face verification failed');
    }
  }

  Future<void> _markAttendance() async {
    final now = DateTime.now();
    final hour = now.hour >= 9 ? (now.hour - 8) : 1; // Simple hour calc

    final response = await ApiService.post(kCameraAttendance, {
      'student_id': widget.student['_id'],
      'batch_id': widget.batchId,
      'date': DateFormat('yyyy-MM-dd').format(now),
      'hour': hour,
    });

    if (response != null && response['success'] == true) {
      if (mounted) {
        _showResultDialog(true, 'Attendance Marked!');
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
      _showResultDialog(false, 'Request sent to class incharge');
    }
  }

  void _showResultDialog(bool success, String message) {
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
                color: success ? Colors.green.shade50 : Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                success ? Icons.check_circle : Icons.pending,
                size: 50,
                color: success ? Colors.green : Colors.orange,
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
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
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
                  color: _faceDetected ? Colors.green : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(120),
              ),
            ),
          ),

          // Countdown
          if (_isCapturing && _countdown > 0)
            Center(
              child: Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

          // Status Bar
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
                  const SizedBox(height: 16),
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
