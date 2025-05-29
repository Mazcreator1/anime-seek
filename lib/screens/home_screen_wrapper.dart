import 'package:flutter/material.dart';
import 'screens/main_recognition_page.dart';
import 'package:provider/provider.dart';

class HomeScreenWrapper extends StatelessWidget {
  const HomeScreenWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Updated to use MainRecognitionPage only, removing the PageView
    return const MainRecognitionPage();
  }
}
