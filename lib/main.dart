import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'screens/calls/call_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/calls_service.dart';
import 'services/chat_service.dart';
import 'services/contacts_service.dart';
import 'services/local_notifications_service.dart';
import 'services/server_config.dart';
import 'services/turn_service.dart';

// Top-level FCM background handler — runs in a separate isolate when
// the app is killed. Firebase must be re-initialized here.
@pragma('vm:entry-point')
Future<void> _onFcmBackgroundMessage(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  // OS already shows the notification from the FCM payload; nothing extra
  // needed here unless we want silent data-only processing.
}

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

  // Register FCM background handler before runApp.
  FirebaseMessaging.onBackgroundMessage(_onFcmBackgroundMessage);

  // Pre-warm the ASL server URL from Gist so it's ready before any call opens.
  // Runs in background — does not block app startup.
  ServerConfig.getUrl().catchError((_) => '');

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
  String? _fcmRegisteredUid;

  @override
  void initState() {
    super.initState();
    _authChanges = context.read<AuthService>().authStateChanges();
    _setupFcmListeners();
  }

  void _setupFcmListeners() {
    // Foreground messages: show a local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] == 'direct_message') {
        final chatId = (data['chatId'] ?? '').toString();
        final senderName = (data['senderName'] ?? '').toString();
        final body = message.notification?.body ?? '';
        if (chatId.isNotEmpty) {
          LocalNotificationsService.instance.showIncomingMessageNotification(
            chatId: chatId,
            senderName: senderName,
            messagePreview: body,
          );
        }
      }
    });

    // App was in background and user tapped the notification
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);

    // App was terminated and user tapped the notification
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _navigateFromMessage(message);
    });
  }

  void _navigateFromMessage(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    if (type == 'incoming_call') {
      final callId = (data['callId'] ?? '').toString();
      final mediaType = (data['mediaType'] ?? 'audio').toString();
      if (callId.isNotEmpty) {
        MyApp.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(callId: callId, isCaller: false, mediaType: mediaType),
        ));
      }
    }
  }

  Future<void> _registerFcmToken(String uid) async {
    if (_fcmRegisteredUid == uid) return;
    _fcmRegisteredUid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) {
        await _saveDeviceSession(uid, token);
      }
      messaging.onTokenRefresh.listen((newToken) {
        _saveDeviceSession(uid, newToken).catchError((_) {});
      });
    } catch (_) {}
  }

  Future<void> _saveDeviceSession(String uid, String token) async {
    final platform = Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Device';
    final osVersion = Platform.operatingSystemVersion;
    final deviceName = Platform.isIOS
        ? 'iPhone ($osVersion)'
        : Platform.isAndroid
        ? 'Android Phone ($osVersion)'
        : platform;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': token,
      'deviceName': deviceName,
      'devicePlatform': platform,
      'deviceLastSeen': FieldValue.serverTimestamp(),
    });
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
          _registerFcmToken(user.uid);

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
