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

List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait by default across the app; the camera screen opts back into
  // landscape for its own lifetime so wide boxes can be captured tilted
  // (see CameraScreen).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  globalCameras = await availableCameras();
  // Load the persisted light/dark preference before the first frame, so a
  // returning user doesn't see a flash of the wrong theme on startup.
  await ThemeController.instance.load();
  // A scan that was interrupted by a crash or a force-quit leaves its photos
  // staged. Nothing refers to them once the app restarts, so clear them here
  // rather than letting them accumulate in app storage.
  await AppStorage.clearCaptures();
  runApp(const UIPrototypeApp());
}

class UIPrototypeApp extends StatelessWidget {
  const UIPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app whenever the theme is toggled (see
    // ThemeController). Every screen reads its colors from AppColors at
    // build time rather than caching them, so this one listener at the root
    // is enough to repaint the entire app when the toggle on the Homepage
    // is tapped.
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark;
        return MaterialApp(
          title: 'CheckMuna',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          // theme/darkTheme are deliberately built from fixed literals here,
          // not from AppColors — AppColors.accent/.bg reflect whichever mode
          // is *currently* active, so reading them here would make both
          // ThemeData objects collapse onto the same palette instead of
          // giving MaterialApp two genuinely different ones to switch
          // between. These two seed/background values are kept in sync with
          // _Light/_Dark in theme/app_colors.dart by hand.
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
          // Was `const RootNavigator()`. That's the actual bug behind
          // "toggling the icon doesn't change colors": RootNavigator takes
          // no arguments, so `const RootNavigator()` is the exact same
          // canonicalized object on every rebuild. When Flutter diffs this
          // AnimatedBuilder's new MaterialApp against the old one and finds
          // an *identical* widget instance at this position, it skips
          // rebuilding that whole subtree as a fast-path optimization —
          // AppColors never gets re-read, no matter how many times
          // ThemeController notifies. Dropping const forces a fresh
          // instance each time, so the skip never triggers.
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
      // Was `const AppShell()` — same identical-widget problem as the
      // `home:` fix above, one level deeper: AppShell takes no arguments,
      // so this was the same frozen instance every time RootNavigator
      // rebuilt, silently blocking the rebuild from ever reaching
      // DashboardScreen/RecordsScreen below it.
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
    // Was `const DashboardScreen()`. Third occurrence of the same bug
    // fixed above in RootNavigator/AppShell — DashboardScreen takes no
    // arguments, so this was the identical frozen widget every time
    // AppShell rebuilt. This is the one that actually mattered most: it
    // directly blocked the Homepage — the toggle icon, the three scan
    // cards, the recent-scans strip — from ever picking up the new theme.
    final screens = [
      DashboardScreen(),
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