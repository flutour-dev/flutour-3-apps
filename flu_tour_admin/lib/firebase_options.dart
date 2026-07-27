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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - admin app is web only.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqcvs9fmoSpv1PSdtAVyHgK54kGUPFC4I',
    appId: '1:258397191065:android:e89a49a71a51e35d2a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDn5lw06s2bvvg2iMw1vGSVn_p9R-suK-8',
    appId: '1:258397191065:web:4592b9dd5cd2fb0f2a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    authDomain: 'flutour-3fc69.firebaseapp.com',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
  );
}
