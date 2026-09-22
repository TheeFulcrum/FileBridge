import 'package:flutter/material.dart';

import 'screens/connections_screen.dart';
import 'theme.dart';

void main() {
  runApp(const FileBridgeApp());
}

class FileBridgeApp extends StatelessWidget {
  const FileBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FileBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const ConnectionsScreen(),
    );
  }
}
