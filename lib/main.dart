import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sembast/sembast.dart';
import 'controller.dart';
import 'data/accounts.dart';
import 'data/database.dart';
import 'data/device_api.dart';
import 'data/family_cloud.dart';
import 'data/store.dart';
import 'data/reminders.dart';
import 'ui/app.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  try {
    final database = await openAppDatabase();
    FamilyAccounts? accounts;
    String? setupError;
    try {
      accounts = await FirebaseSetup.initialize();
    } catch (_) {
      setupError =
          'Family sync is unavailable. Your readings can still save on this phone. Restart the app to try again.';
    }
    runApp(
      _FamilyApp(
        database: database,
        accounts: accounts,
        setupError: setupError,
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'ThermoCare could not open local storage. Your existing records have not been cleared.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: main, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _fontLicensesRegistered = false;
void registerFontLicenses() {
  if (_fontLicensesRegistered) return;
  _fontLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/Nunito-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
}

final phoneReminders = PhoneReminders();

class _FamilyApp extends StatelessWidget {
  const _FamilyApp({required this.database, this.accounts, this.setupError});
  final Database database;
  final FamilyAccounts? accounts;
  final String? setupError;
  @override
  Widget build(BuildContext context) {
    Widget session() => _Session(
      key: ValueKey(accounts?.user?.uid ?? 'local'),
      database: database,
      accounts: accounts,
      setupError: setupError,
    );
    return accounts == null
        ? session()
        : ListenableBuilder(
            listenable: accounts!,
            builder: (_, _) => session(),
          );
  }
}

class _Session extends StatefulWidget {
  const _Session({
    super.key,
    required this.database,
    this.accounts,
    this.setupError,
  });
  final Database database;
  final FamilyAccounts? accounts;
  final String? setupError;
  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  late final controller = MonitorController(
    AppStore(widget.database, ownerId: widget.accounts?.user?.uid),
    DeviceApi(),
    accountEmail: widget.accounts?.user?.email,
    remindersGateway: phoneReminders,
    cloudGateway: widget.accounts?.user == null
        ? null
        : FirestoreFamilyGateway(
            FirebaseFirestore.instance,
            widget.accounts!.user!.uid,
          ),
  );
  late final ready = controller.initialize();
  bool handedOff = false;
  @override
  void dispose() {
    if (!handedOff) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: Center(
              child: Text(
                'Your family records could not open. Please restart the app.',
              ),
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      handedOff = true;
      return ThermoCareApp(
        controller: controller,
        accounts: widget.accounts,
        firebaseSetupError: widget.setupError,
      );
    },
  );
}
