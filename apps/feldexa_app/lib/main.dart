import 'package:flutter/material.dart';

void main() {
  runApp(const FeldexaApp());
}

/// Root widget of the Feldexa application.
///
/// T002 initializes the Flutter application and its Android/Web hosts only;
/// product features and localization are added by later tasks.
class FeldexaApp extends StatelessWidget {
  const FeldexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Feldexa',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Feldexa'))),
    );
  }
}
