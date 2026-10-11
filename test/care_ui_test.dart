import 'family_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/ui/app.dart';
import 'package:thermocare/ui/care_pages.dart';
import 'capture_fixture.dart';

void main() {
  for (final scenario in [
    (const Size(390, 844), 1.0),
    (const Size(320, 640), 1.5),
  ]) {
    testWidgets(
      'guided check-in, notes, calendar and reminders at ${scenario.$1.width}px ${scenario.$2}x',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final setup = await tester.runAsync(() async {
          await (FontLoader(
            'Nunito',
          )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final db = await databaseFactoryMemory.openDatabase(
            'care-ui-${scenario.$1.width}',
          );
          final c = MonitorController(AppStore(db), familyFixtureApi());
          await initializeFamilyFixture(c);
          c.pause();
          return (db, c);
        });
        final (db, c) = setup!;
        final boundary = GlobalKey();
        Future<void> settle() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));
          await tester.pump();
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await settle();
          await tester.tap(finder);
          await settle();
          expect(tester.takeException(), isNull);
        }

        Future<void> capture(String name) async => tester.runAsync(() async {
          await Directory('artifacts').create(recursive: true);
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'artifacts/$name-${scenario.$1.width.toInt()}-care.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ThermoCareApp(controller: c),
          ),
        );
        await settle();
        await tap(find.text('Start guided check-in'));
        await capture('guided-person');
        await tap(find.widgetWithText(ChoiceChip, 'Dad'));
        await tap(find.text('Let’s begin'));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Capture reading'),
              )
              .onPressed,
          isNull,
        );
        for (final label in [
          'Rested indoors, away from direct heat or drafts',
          'Same exposed skin site as previous check-ins',
          'Sensor aimed and held at the validated device distance',
        ]) {
          await tap(find.text(label));
        }
        seedStableCapture(c);
        c.dismissReminder();
        await settle();
        await capture('guided-ready');
        await tap(find.text('Capture reading'));
        final held = c.latest!;
        await tester.enterText(find.byType(TextField), 'A cozy afternoon');
        await tester.runAsync(c.poll);
        await settle();
        expect(c.latest!.id, isNot(held.id));
        await capture('guided-note');
        await tap(find.text('Save check-in'));
        expect(c.records.firstWhere((r) => r.id == held.id).memberId, 'dad');
        expect(
          c.records.firstWhere((r) => r.id == held.id).note,
          'A cozy afternoon',
        );
        await tap(find.text('All done'));
        await tap(find.text('Family calendar'));
        await capture('family-calendar');
        await tap(find.byTooltip('Next month'));
        expect(find.text('0 saved check-ins this month'), findsOneWidget);
        await tap(find.text('Back to today'));
        await tap(find.widgetWithText(ChoiceChip, 'Dad'));
        await tap(find.textContaining('A cozy afternoon'));
        expect(find.byType(ReadingNote), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'After a rest');
        await tap(find.text('Save note'));
        expect(
          c.records.firstWhere((r) => r.id == held.id).note,
          'After a rest',
        );
        Navigator.of(tester.element(find.byType(ReadingNote))).pop();
        await settle();
        expect(find.textContaining('After a rest'), findsOneWidget);
        await tap(find.byTooltip('Back'));
        await tap(find.text('Reminders'));
        await tap(find.text('Add a reminder'));
        await tap(find.widgetWithText(FilterChip, 'Tue'));
        await tap(find.text('Save reminder'));
        expect(c.reminders.single.weekdays, [1, 3, 4, 5, 6, 7]);
        await capture('personal-reminders');
        await tap(find.byType(Switch));
        expect(c.reminders.single.enabled, isFalse);
        await tap(find.text('Edit'));
        await tap(find.text('Save reminder'));
        expect(c.reminders.single.enabled, isFalse);
        await tap(find.text('Remove'));
        expect(c.reminders, isEmpty);
        await tap(find.byTooltip('Back'));
        await tap(find.text('Personal trends'));
        await tap(find.widgetWithText(ChoiceChip, 'Dad'));
        await tap(find.widgetWithText(ChoiceChip, '30 days'));
        expect(find.textContaining('After a rest'), findsOneWidget);
        await capture('personal-trends');
        await tap(find.textContaining('After a rest'));
        expect(find.byType(ReadingNote), findsOneWidget);
        expect(find.textContaining('Checklist completed'), findsOneWidget);
        Navigator.of(tester.element(find.byType(ReadingNote))).pop();
        await settle();
        await tap(find.widgetWithText(ChoiceChip, 'Mom'));
        expect(find.textContaining('After a rest'), findsNothing);
        await capture('personal-trends-mom');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(db.close);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
