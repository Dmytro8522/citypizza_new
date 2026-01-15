// Generated manually from GoogleService-Info.plist and google-services.json
// FlutterFire-like options for Android/iOS. Update if you change Firebase configs.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase is not configured for web');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCeOe5S74_u75lrhlrVglC6ZIe6pu5WkpA',
    appId: '1:900205557601:android:a8fba067a46b05c7ccf720',
    messagingSenderId: '900205557601',
    projectId: 'pizza-83d2a',
    storageBucket: 'pizza-83d2a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB-N8pjJl0GTBdCK2f4KBOk5F3RxsjgKAE',
    appId: '1:900205557601:ios:2d42dec129bc0bfbccf720',
    messagingSenderId: '900205557601',
    projectId: 'pizza-83d2a',
    storageBucket: 'pizza-83d2a.firebasestorage.app',
    iosBundleId: 'com.citypizza.order',
  );
}
