import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/notebooks/presentation/notebooks_screen.dart';

class CuadernoApp extends StatelessWidget {
  const CuadernoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuaderno Científico',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const NotebooksScreen(),
    );
  }
}
