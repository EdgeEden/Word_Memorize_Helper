import 'package:flutter/material.dart';
import 'screens/quiz_screen.dart';
import 'services/fsrs_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WordNApp());
}

class WordNApp extends StatefulWidget {
  const WordNApp({super.key});

  @override
  State<WordNApp> createState() => _WordNAppState();
}

class _WordNAppState extends State<WordNApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final modeStr = await FsrsRepository.getThemeMode();
    if (mounted) {
      setState(() {
        if (modeStr == 'light') {
          _themeMode = ThemeMode.light;
        } else if (modeStr == 'dark') {
          _themeMode = ThemeMode.dark;
        } else {
          _themeMode = ThemeMode.system;
        }
      });
    }
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Elegant Indigo brand seed color for modern educational UI
    const seedColor = Color(0xFF4F46E5);

    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
        surface: const Color(0xFFF8FAFC),
        surfaceContainerLowest: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F172A),
        surfaceContainerLowest: const Color(0xFF1E293B),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
    );

    return MaterialApp(
      title: 'WordN - 考研英语记单词',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: Builder(
        builder: (context) {
          final isCurrentlyDark = _themeMode == ThemeMode.dark ||
              (_themeMode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          return QuizScreen(
            isDarkMode: isCurrentlyDark,
            currentThemeMode: _themeMode,
            onThemeChanged: _setThemeMode,
          );
        },
      ),
    );
  }
}
