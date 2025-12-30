import 'package:flutter/material.dart';
import '../api_service.dart';
import '../constants.dart';
import 'student_list_screen.dart';

class BatchSelectScreen extends StatefulWidget {
  const BatchSelectScreen({super.key});

  @override
  State<BatchSelectScreen> createState() => _BatchSelectScreenState();
}

class _BatchSelectScreenState extends State<BatchSelectScreen> {
  static const Color primaryColor = Color(0xFF5B8A72);

  List<Map<String, dynamic>> batches = [];
  bool isLoading = true;
  String? selectedBatchId;
  String? selectedBatchName;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => isLoading = true);
    try {
      final data = await ApiService.get(kCameraBatches);
      if (data != null && data['data'] != null) {
        setState(() {
          batches = List<Map<String, dynamic>>.from(data['data']);
        });
      }
    } catch (e) {
      print('Error loading batches: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _proceedToStudentList() {
    if (selectedBatchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a batch')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentListScreen(
          batchId: selectedBatchId!,
          batchName: selectedBatchName!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // App Logo/Title
              Center(
                child: Column(
                  children: [
                    Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 40,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Face Attendance',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select your batch to continue',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60),

              // Batch Selection Label
              const Text(
                'Select Batch',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              // Batch Dropdown
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (batches.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No batches available',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedBatchId,
                      isExpanded: true,
                      hint: const Text('Choose your batch'),
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: primaryColor,
                      ),
                      items: batches.map((batch) {
                        return DropdownMenuItem(
                          value: batch['_id'] as String,
                          child: Text(
                            batch['name'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 16),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        final batch = batches.firstWhere(
                          (b) => b['_id'] == value,
                        );
                        setState(() {
                          selectedBatchId = value;
                          selectedBatchName = batch['name'];
                        });
                      },
                    ),
                  ),
                ),

              const Spacer(),

              // Continue Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedBatchId != null
                      ? _proceedToStudentList
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
