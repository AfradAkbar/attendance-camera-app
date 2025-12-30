import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../constants.dart';
import 'face_capture_screen.dart';

class StudentListScreen extends StatefulWidget {
  final String batchId;
  final String batchName;

  const StudentListScreen({
    super.key,
    required this.batchId,
    required this.batchName,
  });

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  static const Color primaryColor = Color(0xFF5B8A72);

  List<Map<String, dynamic>> students = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => isLoading = true);
    try {
      final url = '$kCameraBatchStudents/${widget.batchId}/students';
      final data = await ApiService.get(url);
      if (data != null && data['data'] != null) {
        setState(() {
          students = List<Map<String, dynamic>>.from(data['data']);
        });
      }
    } catch (e) {
      print('Error loading students: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _selectStudent(Map<String, dynamic> student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FaceCaptureScreen(student: student, batchId: widget.batchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F4),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: Text(widget.batchName),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 40,
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select Your Name',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap on your photo to mark attendance',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Student Grid
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : students.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      return _buildStudentCard(students[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return GestureDetector(
      onTap: () => _selectStudent(student),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Student Photo
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.1),
              ),
              child: ClipOval(
                child: student['image_url'] != null
                    ? CachedNetworkImage(
                        imageUrl: student['image_url'],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Icon(
                          Icons.person,
                          size: 30,
                          color: primaryColor.withOpacity(0.5),
                        ),
                        errorWidget: (context, url, error) => Icon(
                          Icons.person,
                          size: 30,
                          color: primaryColor.withOpacity(0.5),
                        ),
                      )
                    : Icon(
                        Icons.person,
                        size: 30,
                        color: primaryColor.withOpacity(0.5),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // Student Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                student['name'] ?? 'Unknown',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
