import 'family_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/ui/app.dart';
import 'package:thermocare/ui/night_art.dart';
import 'package:thermocare/ui/chart.dart';
import 'package:thermocare/ui/care_pages.dart';
import 'capture_fixture.dart';

void main() {
  for (final scenario in [
    (const Size(390, 844), 1.0, false),
    (const Size(1440, 1050), 1.0, false),
    (const Size(320, 640), 1.0, false),
    (const Size(390, 844), 1.5, false),
    (const Size(390, 844), 1.0, true),
  ]) {
    final (size, textScale, reduced) = scenario;
    testWidgets(
      'all screens fit at ${size.width.toInt()}px, ${textScale}x text, reduced motion $reduced',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final setup = await tester.runAsync(() async {
          final loader = FontLoader('Nunito')
            ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          final db = await databaseFactoryMemory.openDatabase(
            'ui-${size.width}-$textScale-$reduced',
          );
          final c = MonitorController(AppStore(db), familyFixtureApi());
          await initializeFamilyFixture(c);
          c.pause();
          return (db, c);
        });
        final (db, c) = setup!;
        final boundaryKey = GlobalKey();
        Future<void> finishMotion() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));
          await tester.pump();
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: ThermoCareApp(controller: c),
          ),
        );
        await finishMotion();
        final clock = tester.widget<NightClock>(find.byType(NightClock)).clock;
        final before = clock.value;
        await tester.pump(const Duration(milliseconds: 120));
        expect(clock.value == before, reduced);
        expect(tester.takeException(), isNull);
        Future<void> capture(String page) async => tester.runAsync(() async {
          await Directory('artifacts').create(recursive: true);
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'artifacts/$page-${size.width.toInt()}${textScale > 1 ? '-large-text' : ''}${reduced ? '-reduced-motion' : ''}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await capture('overview');
        final previousId = c.latest!.id;
        await tester.ensureVisible(find.text('Get reading'));
        await finishMotion();
        await tester.tap(find.text('Get reading'));
        await finishMotion();
        expect(c.latest!.id, isNot(previousId));
        final previousCount = c.records.length;
        await tester.ensureVisible(find.text('Save reading'));
        await finishMotion();
        await tester.tap(find.text('Save reading'));
        await finishMotion();
        expect(find.byType(GuidedCheckIn), findsOneWidget);
        Navigator.of(tester.element(find.byType(GuidedCheckIn))).pop();
        await finishMotion();
        seedStableCapture(c);
        await tester.runAsync(() => c.saveCurrent(prepared: true));
        await finishMotion();
        expect(
          c.records.length,
          previousCount,
          reason:
              'Saving assigns the existing live sample instead of duplicating it',
        );
        expect(
          c.records.firstWhere((r) => r.id == c.latest!.id).memberId,
          c.selectedMember!.id,
        );

        for (final label in ['History', 'My device']) {
          await tester.tap(find.text(label).last);
          if (label == 'History' &&
              size.width == 390 &&
              textScale == 1 &&
              !reduced) {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 120));
            await capture('transition-history');
          }
          await finishMotion();
          expect(tester.takeException(), isNull, reason: label);
          await capture(label.toLowerCase().replaceAll(' ', '-'));
          if (label == 'History') {
            await tester.ensureVisible(
              find.widgetWithText(ChoiceChip, 'Unassigned'),
            );
            await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
            await finishMotion();
            final countBeforeLive = c.records.length;
            await tester.runAsync(c.poll);
            await finishMotion();
            expect(c.records.length, countBeforeLive + 1);
            expect(
              find.byKey(ValueKey(c.latest!.id)),
              findsOneWidget,
              reason: 'A new live sample appears while History stays open',
            );
            final dadChip = find.widgetWithText(ChoiceChip, 'Dad');
            await tester.ensureVisible(dadChip);
            await tester.tap(dadChip);
            await finishMotion();
            expect(tester.widget<ChoiceChip>(dadChip).selected, isTrue);
            expect(
              find.text('Mom'),
              findsOneWidget,
              reason: 'Only Mom’s filter remains; her rows are hidden',
            );
            expect(find.text('Dad'), findsNWidgets(9));
            final everyone = find.widgetWithText(ChoiceChip, 'Everyone');
            await tester.ensureVisible(everyone);
            await tester.tap(everyone);
            await finishMotion();
            await tester.ensureVisible(find.text('Above my reference'));
            await finishMotion();
            await tester.tap(find.text('Above my reference'));
            await finishMotion();
            expect(
              find.text('Your first check-in starts here.'),
              findsOneWidget,
            );
            await tester.tap(find.text('Above my reference'));
            await finishMotion();
            await tester.ensureVisible(dadChip);
            await tester.tap(dadChip);
            await finishMotion();
            await tester.ensureVisible(find.text('See the temperature trend'));
            await tester.tap(find.text('See the temperature trend'));
            await finishMotion();
            await tester.ensureVisible(find.byType(TemperatureChart));
            await finishMotion();
            expect(tester.takeException(), isNull, reason: 'Expanded trend');
            await capture('history-trend');
          }
        }
        await tester.tap(find.byTooltip('Settings'));
        await finishMotion();
        expect(tester.takeException(), isNull, reason: 'Settings');
        await capture('settings');
        c.disconnect();
        await tester.runAsync(() async {
          await c.clearRecords();
          for (final m in c.members.toList()) {
            await c.saveMember(
              existing: m,
              name: m.name,
              avatar: m.avatar,
              archived: true,
            );
          }
        });
        await tester.tap(find.text('Home').last);
        await finishMotion();
        expect(find.text('Ready whenever you are.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        {
          await tester.ensureVisible(find.byTooltip('Add family member'));
          await tester.tap(find.byTooltip('Add family member'));
          await finishMotion();
          await capture('family-picker');
          await tester.enterText(find.byType(TextField), 'Lily');
          final girlChoice = find.widgetWithText(ChoiceChip, 'Girl');
          await tester.ensureVisible(girlChoice);
          await tester.tap(girlChoice);
          await finishMotion();
          await tester.tap(find.text('Save profile'));
          await finishMotion();
          expect(c.selectedMember?.name, 'Lily');
          expect(c.selectedMember?.avatar, 8);
          expect(c.activeMembers.length, 1);
          expect(
            tester.takeException(),
            isNull,
            reason: 'Family profile editor',
          );
        }
        if (!reduced && size.width == 390 && textScale == 1) {
          for (final label in ['History', 'My device', 'Home']) {
            await tester.tap(find.text(label).last);
            await tester.pump(const Duration(milliseconds: 40));
          }
          await finishMotion();
          expect(tester.takeException(), isNull);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          final paused = clock.value;
          await tester.pump(const Duration(milliseconds: 300));
          expect(clock.value, paused);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await finishMotion();
          expect(clock.value, isNot(paused));
          c.pause();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(db.close);
      },
    );
  }
}
