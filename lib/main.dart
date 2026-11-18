import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WatchLensApp());
}

class WatchLensApp extends StatelessWidget {
  const WatchLensApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Watch Lens',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5267D8)),
          useMaterial3: true,
        ),
        home: const PlaceholderHomePage(),
      );
}

class PlaceholderHomePage extends StatelessWidget {
  const PlaceholderHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Watch Lens')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.center_focus_weak, size: 64),
                SizedBox(height: 16),
                Text('Watch Lens', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text('Flutter project initialized. Feature modules will be added here.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
