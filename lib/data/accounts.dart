import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyAccounts extends ChangeNotifier {
  FamilyAccounts(this.auth) {
    _subscription = auth.authStateChanges().listen((_) => notifyListeners());
  }
  final FirebaseAuth auth;
  late final StreamSubscription<User?> _subscription;
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  User? get user => auth.currentUser;
  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> create(String email, String password) async {
    await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> reset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());
  Future<void> signOut() => auth.signOut();
}

class FirebaseSetup {
  static const emulator = bool.fromEnvironment('FIREBASE_EMULATOR');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool get configured => emulator || projectId.isNotEmpty;
  static Future<FamilyAccounts?> initialize() async {
    if (kReleaseMode && (!configured || emulator)) {
      throw StateError('Release builds require the production family service.');
    }
    if (!configured) return null;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: emulator
            ? 'fake-api-key'
            : kIsWeb
            ? const String.fromEnvironment('FIREBASE_API_KEY')
            : defaultTargetPlatform == TargetPlatform.android
            ? const String.fromEnvironment('FIREBASE_ANDROID_API_KEY')
            : const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        appId: emulator
            ? '1:123456789:web:thermocare'
            : kIsWeb
            ? const String.fromEnvironment('FIREBASE_APP_ID')
            : defaultTargetPlatform == TargetPlatform.android
            ? const String.fromEnvironment('FIREBASE_ANDROID_APP_ID')
            : const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
        messagingSenderId: emulator
            ? '123456789'
            : const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: emulator ? 'demo-thermocare' : projectId,
        authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: const String.fromEnvironment(
          'FIREBASE_IOS_BUNDLE_ID',
          defaultValue: 'com.thermocare.thermocare',
        ),
      ),
    );
    if (emulator) {
      const host = String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8085);
    }
    return FamilyAccounts(FirebaseAuth.instance);
  }
}

String accountError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Please check your email address.',
      'email-already-in-use' =>
        'This email already has an account. Try signing in.',
      'weak-password' => 'Choose a password with at least 6 characters.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Please check your email and password.',
      'network-request-failed' =>
        'Connect to the internet to sign in. Your phone’s saved readings are still here.',
      'too-many-requests' => 'Please wait a little before trying again.',
      'operation-not-allowed' =>
        'Account sign-in is unavailable right now. Please try again later.',
      _ => 'We couldn’t sign you in just yet. Please try again.',
    };
  }
  return 'Something didn’t go through. Please try again.';
}
