import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyASfXInknNASRzrtCAtHnNOcg5Jztt1xbk',
    appId: '1:651084462072:android:2f87cc5eda4ba1524ac80d',
    messagingSenderId: '651084462072',
    projectId: 'sign-language-app-5e3d6',
    storageBucket: 'sign-language-app-5e3d6.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyASfXInknNASRzrtCAtHnNOcg5Jztt1xbk',
    appId: '1:651084462072:web:2f87cc5eda4ba1524ac80d',
    messagingSenderId: '651084462072',
    projectId: 'sign-language-app-5e3d6',
    storageBucket: 'sign-language-app-5e3d6.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyASfXInknNASRzrtCAtHnNOcg5Jztt1xbk',
    appId: '1:651084462072:ios:2f87cc5eda4ba1524ac80d',
    messagingSenderId: '651084462072',
    projectId: 'sign-language-app-5e3d6',
    storageBucket: 'sign-language-app-5e3d6.firebasestorage.app',
    iosBundleId: 'com.example.signLanguageApp',
  );
}
