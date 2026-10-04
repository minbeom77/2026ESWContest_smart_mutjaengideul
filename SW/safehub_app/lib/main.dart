import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'ui/home_page.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  AppConfig.validate();
  runApp(const SafeHubApp());
}

class SafeHubApp extends StatefulWidget {
  const SafeHubApp({super.key});

  @override
  State<SafeHubApp> createState() => _SafeHubAppState();
}

class _SafeHubAppState extends State<SafeHubApp> {
  int _settingsRevision = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.localPreview ? 'SafeHub · 장비 연결 전 체험' : 'SafeHub',
      theme: AppTheme.light,
      home: SafeHubHomePage(
        key: ValueKey(_settingsRevision),
        onSettingsSaved: () => setState(() => _settingsRevision++),
      ),
    );
  }
}
