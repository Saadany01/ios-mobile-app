import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/login_two_factor_screen.dart';
import 'screens/auth/mandatory_password_change_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/calls_service.dart';
import 'services/chat_service.dart';
import 'services/contacts_service.dart';
import 'services/local_notifications_service.dart';
import 'services/server_config.dart';
import 'services/turn_service.dart';

const String kAppVersion = '1.1.0';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard against native-side pre-initialization reporting duplicate app.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      rethrow;
    }
  }

  await LocalNotificationsService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global key to preserve HomeScreen state
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<ContactsService>(create: (_) => ContactsService()),
        Provider<CallsService>(create: (_) => CallsService()),
        Provider<ChatService>(create: (_) => ChatService()),
        Provider<TurnService>(create: (_) => TurnService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: MyApp.navigatorKey,
          title: 'HearMySign',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(themeProvider.textScale),
            ),
            child: child!,
          ),
          locale: themeProvider.locale,
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
            Locale('fr'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _SplashGate(),
        );
      },
    );
  }
}

// ── Splash → OTA check → Auth ────────────────────────────────────────
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _splashDone = false;

  void _onSplashDone() {
    setState(() => _splashDone = true);
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final base = await ServerConfig.getUrl();
      final res = await http
          .get(Uri.parse('$base/api/version'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final serverVersion = data['version'] as String? ?? '';
      final apkUrl = data['apk_url'] as String? ?? '';
      if (serverVersion != kAppVersion && apkUrl.isNotEmpty && mounted && Platform.isAndroid) {
        _showUpdateDialog(serverVersion, apkUrl);
      }
    } catch (_) {}
  }

  void _showUpdateDialog(String newVersion, String apkUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text('Update Available', style: TextStyle(color: Colors.white)),
        content: Text(
          'Version $newVersion is ready. Update now for the latest features.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadAndInstall(apkUrl);
            },
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(String apkUrl) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Downloading update...'),
        ]),
        duration: Duration(minutes: 5),
        backgroundColor: Color(0xFF25D366),
      ),
    );
    try {
      final res = await http.get(Uri.parse(apkUrl)).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hearmysign_update.apk');
      await file.writeAsBytes(res.bodyBytes);
      messenger.hideCurrentSnackBar();
      // Trigger Android install prompt
      await OpenFile.open(file.path, type: 'application/vnd.android.package-archive');
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(onDone: _onSplashDone);
    }
    return const _AuthGate();
  }
}

// ── Auth Gate ─────────────────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Stream<User?> _authChanges;

  @override
  void initState() {
    super.initState();
    _authChanges = context.read<AuthService>().authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final authService = context.read<AuthService>();

    return StreamBuilder<User?>(
      stream: _authChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AuthGateErrorView(
            message: 'Failed to read authentication state.',
            onSignOut: authService.signOut,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: themeProvider.isDarkMode
                    ? AppTheme.primaryTealDark
                    : AppTheme.primaryTeal,
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;

          return StreamBuilder<Map<String, dynamic>?>(
            stream: authService
                .userDocumentStream(user.uid)
                .map((doc) => doc.data()),
            builder: (context, userDocSnapshot) {
              if (userDocSnapshot.hasError) {
                return _AuthGateErrorView(
                  message: 'Failed to read account verification state.',
                  onSignOut: authService.signOut,
                );
              }

              if (userDocSnapshot.connectionState == ConnectionState.waiting &&
                  !userDocSnapshot.hasData) {
                return Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(
                      color: themeProvider.isDarkMode
                          ? AppTheme.primaryTealDark
                          : AppTheme.primaryTeal,
                    ),
                  ),
                );
              }

              final data = userDocSnapshot.data ?? const <String, dynamic>{};
              final pendingSecondFactorInProfile =
                  data['pendingLoginSecondFactor'] == true;
              final pendingSecondFactor =
                  authService.isSecondFactorPendingForSession ||
                  pendingSecondFactorInProfile;
              final mustChangePassword = data['mustChangePassword'] == true;

              if (pendingSecondFactor) {
                return const LoginTwoFactorScreen();
              }

              if (mustChangePassword) {
                return const MandatoryPasswordChangeScreen();
              }

              // Use a key to preserve state across theme changes.
              return const HomeScreen(key: ValueKey('home_screen'));
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class _AuthGateErrorView extends StatelessWidget {
  const _AuthGateErrorView({required this.message, required this.onSignOut});

  final String message;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await onSignOut();
                  },
                  child: const Text('Go to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
