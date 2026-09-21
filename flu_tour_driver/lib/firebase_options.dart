import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - driver app is mobile only.',
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
    appId: '1:258397191065:android:648201ce64ac08342a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA_Y1sLVHmNwswr2hPtK7EhjjG3e80zAHs',
    appId: '1:258397191065:ios:cecafb994e4725ce2a7108',
    messagingSenderId: '258397191065',
    projectId: 'flutour-3fc69',
    databaseURL: 'https://flutour-3fc69-default-rtdb.firebaseio.com',
    storageBucket: 'flutour-3fc69.firebasestorage.app',
    iosClientId: '258397191065-usppb664m2hdb5acaa6ob8klb6ec1mb4.apps.googleusercontent.com',
    iosBundleId: 'com.flutour.driver',
  );
}
