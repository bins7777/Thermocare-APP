import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/ui/app.dart';

void main() {
  testWidgets(
    'new users get an empty product, setup guidance and no exploration controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final setup = await tester.runAsync(() async {
        await (FontLoader(
          'Nunito',
        )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final db = await databaseFactoryMemory.openDatabase('product-welcome');
        final c = MonitorController(AppStore(db), DeviceApi());
        await c.initialize();
        c.pause();
        return (db, c);
      });
      final (db, c) = setup!;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ThermoCareApp(controller: c),
        ),
      );
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump();
      }

      await settle();
      expect(find.text('Welcome to ThermoCare'), findsOneWidget);
      expect(find.text('Add your first family member'), findsOneWidget);
      expect(c.members, isEmpty);
      expect(c.records, isEmpty);
      await tester.runAsync(() async {
        final capture =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await capture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts').create(recursive: true);
        await File(
          'artifacts/product-first-launch-320.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        capture.dispose();
      });
      await tester.ensureVisible(find.text('Set up your thermometer'));
      await tester.tap(find.text('Set up your thermometer'));
      await settle();
      expect(find.text('Connect your thermometer'), findsOneWidget);
      expect(find.textContaining('demo'), findsNothing);
      expect(find.textContaining('Explore with'), findsNothing);
      expect(find.textContaining('Firebase'), findsNothing);
      expect(c.latest, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
    },
  );
}
