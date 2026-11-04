import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/notebooks/presentation/notebooks_screen.dart';

class EulerNotesApp extends StatelessWidget {
  const EulerNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Euler Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const NotebooksScreen(),
    );
  }
}
