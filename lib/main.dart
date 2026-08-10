import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/records_screen.dart';
import 'widgets/floating_nav_bar.dart';
import 'theme/app_colors.dart';

List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait by default across the app; the camera screen opts back into
  // landscape for its own lifetime so wide boxes can be captured tilted
  // (see CameraScreen).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  globalCameras = await availableCameras();
  runApp(const UIPrototypeApp());
}

class UIPrototypeApp extends StatelessWidget {
  const UIPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckMuna',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        useMaterial3: true,
      ),
      home: const RootNavigator(),
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
      child = const AppShell();
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
  // 0 = Homepage, 1 = Records. The camera itself is no longer a permanently
  // mounted tab — Homepage hosts the Check Label / Check Damage / Inspection
  // Mode entry points, each of which pushes CameraScreen as its own route,
  // so orientation handling for the camera now lives on CameraScreen instead
  // of here.
  int _currentIndex = 0;

  final GlobalKey<RecordsScreenState> _recordsKey =
  GlobalKey<RecordsScreenState>();

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);

    if (index == 1) {
      // Reload records every time the Records tab is opened, with a
      // post-frame fallback in case the key isn't attached yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recordsKey.currentState?.loadFiles();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      RecordsScreen(key: _recordsKey),
    ];

    return Scaffold(
      // Both tabs stay mounted at all times (so Records state is never
      // destroyed/rebuilt) — only their horizontal position is animated to
      // create a sliding cross-fade.
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