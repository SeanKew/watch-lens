import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'services/gemini_service.dart';
import 'services/image_search_service.dart';
import 'services/segmentation_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WatchLensApp());
}

class WatchLensApp extends StatelessWidget {
  const WatchLensApp({super.key});

  static const _seed = Color(0xFFB08D57); // 香槟金

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
      );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 无状态服务
        Provider<SettingsService>(create: (_) => SettingsService()),
        Provider<GeminiService>(create: (_) => GeminiService()),
        Provider<ImageSearchService>(create: (_) => ImageSearchService()),
        Provider<SegmentationService>(
          create: (_) => SegmentationService(),
          dispose: (_, s) => s.dispose(),
        ),
        // 全局状态
        ChangeNotifierProvider<SettingsProvider>(
          create: (c) => SettingsProvider(c.read<SettingsService>())..load(),
        ),
        ChangeNotifierProvider<LibraryProvider>(
          create: (_) => LibraryProvider()..load(),
        ),
      ],
      child: MaterialApp(
        title: 'WatchLens',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
