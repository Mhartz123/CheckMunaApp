import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/records_screen.dart';
import 'widgets/floating_nav_bar.dart';
import 'services/app_storage.dart';
import 'services/theme_controller.dart';
import 'widgets/theme_fade.dart';

List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  globalCameras = await availableCameras();

  await ThemeController.instance.load();

  await AppStorage.clearCaptures();
  runApp(const UIPrototypeApp());
}

class UIPrototypeApp extends StatelessWidget {
  const UIPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {

    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark;
        return MaterialApp(
          title: 'CheckMuna',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,

          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF0F7F2),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF10160F),
            useMaterial3: true,
          ),

          builder: (context, child) =>
              ThemeFade(child: child ?? const SizedBox.shrink()),

          home: RootNavigator(),
        );
      },
    );
  }
}

class RootNavigator extends StatefulWidget {
  const RootNavigator({super.key});

  @override
  State<RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<RootNavigator> {
  bool _showSplash = true;
  bool _showHome = true;

  @override
  Widget build(BuildContext context) {
    late Widget child;
    late Key key;

    if (_showSplash) {
      child = SplashScreen(
        onFinished: () => setState(() => _showSplash = false),
      );
      key = const ValueKey('splash');
    } else if (_showHome) {
      child = HomeScreen(
        onGetStarted: () => setState(() => _showHome = false),
      );
      key = const ValueKey('home');
    } else {

      child = AppShell();
      key = const ValueKey('app');
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (widget, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: widget,
      ),
      child: KeyedSubtree(key: key, child: child),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {

  int _currentIndex = 0;

  final GlobalKey<RecordsScreenState> _recordsKey =
  GlobalKey<RecordsScreenState>();

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);

    if (index == 1) {

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recordsKey.currentState?.loadFiles();
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    final screens = [
      DashboardScreen(),
      RecordsScreen(key: _recordsKey),
    ];

    return Scaffold(

      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: List.generate(screens.length, (i) {
          final isActive = i == _currentIndex;
          return IgnorePointer(
            ignoring: !isActive,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset: Offset((i - _currentIndex).toDouble(), 0),
              child: screens[i],
            ),
          );
        }),
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: _currentIndex,
        onTap: _switchTab,
      ),
    );
  }
}
