import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - passenger app is mobile only.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqcvs9fmoSpv1PSdtAVyHgK54kGUPFC4I',
    appId: '1:258397191065:android:5ae8b79f763662342a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCqcvs9fmoSpv1PSdtAVyHgK54kGUPFC4I',
    appId: '1:258397191065:android:5ae8b79f763662342a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
    iosBundleId: 'com.flutour.passenger',
  );
}
