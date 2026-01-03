import 'package:flutter/material.dart';
import 'screens/batch_select_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:face_verification/face_verification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize face verification model
  await FaceVerification.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.urbanistTextTheme(),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const BatchSelectScreen(),
    );
  }
}
