import 'dart:convert';
import 'dart:io';

void main() {
  try {
    final config =
        jsonDecode(File('firebase-config.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final key in [
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_IOS_APP_ID',
      'FIREBASE_IOS_API_KEY',
      'FIREBASE_IOS_BUNDLE_ID',
    ]) {
      if (config[key] is! String || (config[key] as String).trim().isEmpty) {
        throw FormatException('Missing iPhone configuration: $key');
      }
    }
    if (config['FIREBASE_IOS_BUNDLE_ID'] != 'com.thermocare.thermocare' ||
        !(config['FIREBASE_IOS_APP_ID'] as String).contains(':ios:') ||
        (config['FIREBASE_PROJECT_ID'] as String).startsWith('demo-')) {
      throw const FormatException('Use the registered production iOS app.');
    }
    for (final entry in config.entries) {
      if (RegExp('DEMO|EMULATOR').hasMatch(entry.key) &&
          !['', 'false', '0'].contains('${entry.value}'.toLowerCase())) {
        throw const FormatException('Disable development modes for iPhone.');
      }
    }
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    if (!project.contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.thermocare.thermocare;',
        ) ||
        !project.contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;')) {
      throw const FormatException(
        'Check the iOS bundle ID and deployment target.',
      );
    }
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    if (!plist.contains('<key>NSLocalNetworkUsageDescription</key>')) {
      throw const FormatException(
        'The thermometer needs local-network permission.',
      );
    }
    stdout.writeln(
      'PASS: production iOS client, bundle ID, iOS 15+ target and local-network permission.',
    );
    stdout.writeln(
      'Apple build tools and signing must still be configured on macOS. This check does not create an iPhone installer.',
    );
  } catch (error) {
    stderr.writeln('iOS preflight failed: $error');
    exitCode = 1;
  }
}
