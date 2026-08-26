import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'ui/home_page.dart';
import 'ui/theme/app_theme.dart';

void main() {
  AppConfig.validate();
  runApp(const SafeHubApp());
}

class SafeHubApp extends StatelessWidget {
  const SafeHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeHub',
      theme: AppTheme.light,
      home: const SafeHubHomePage(),
    );
  }
}