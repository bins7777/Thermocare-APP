import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../models.dart';
import '../care_models.dart';
import 'family_widgets.dart';
import 'motion.dart';
import 'night_art.dart';
import 'theme.dart';
import 'temperature_alert.dart';

class CarePage extends StatelessWidget {
  const CarePage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      backgroundColor: canvas,
      foregroundColor: nightText,
    ),
    body: NightBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openCheckIn(
  BuildContext context,
  MonitorController controller, {
  String? memberId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => GuidedCheckIn(controller: controller, memberId: memberId),
  ),
);

class GuidedCheckIn extends StatefulWidget {
  const GuidedCheckIn({super.key, required this.controller, this.memberId});
  final MonitorController controller;
  final String? memberId;
  @override
  State<GuidedCheckIn> createState() => _GuidedCheckInState();
}

class _GuidedCheckInState extends State<GuidedCheckIn> {
  MonitorController get c => widget.controller;
  late String? memberId = widget.memberId ?? c.selectedMember?.id;
  final note = TextEditingController();
  int step = 0;
  bool busy = false;
  String? error;
  CheckInDraft? draft;
  final preparation = [false, false, false];
  bool get prepared => preparation.every((v) => v);
  @override
  void dispose() {
    c.endMeasurement(notify: false);
    note.dispose();
    super.dispose();
  }

  FamilyMember? get person {
    for (final m in c.activeMembers) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  Future<void> capture() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!c.active) {
        throw const FormatException(
          'Connect your thermometer in My device first, then come back.',
        );
      }
      if (c.busy) {
        throw const FormatException(
          'Your thermometer is updating. Give it a moment, then try again.',
        );
      }
      if (!c.fresh) {
        throw const FormatException(
          'We could not get a fresh reading. Check the device and Wi-Fi, then try again.',
        );
      }
      final member = person;
      if (member == null) {
        throw const FormatException('Choose an active family member first.');
      }
      final captured = c.captureCheckIn(member: member, prepared: prepared);
      c.endMeasurement();
      setState(() {
        draft = captured;
        step = 2;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Please try that check-in again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.saveCheckIn(draft!, note: note.text);
      if (mounted) {
        setState(() => step = 3);
        if (draft!.reading.celsius >= c.threshold) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('High temperature alert'),
              content: SingleChildScrollView(
                child: TemperatureAlertNotice(
                  reading: draft!.reading,
                  person: draft!.member.name,
                  threshold: c.threshold,
                  unit: c.unit,
                  showTitle: false,
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Understood'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'We could not save yet. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addPerson() async {
    final result = await editMember(context);
    if (result == null || !mounted) return;
    try {
      await c.saveMember(name: result.$1, avatar: result.$2);
      if (mounted) setState(() => memberId = c.selectedMember?.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'That profile could not save. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => CarePage(
      title: 'A little check-in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CheerMotion(
              trigger: step,
              child: const CareMascot(width: 150),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Let’s take a little moment.',
              'I’m right here with you.',
              'A little note, if you like.',
              'One little moment of care, saved.',
            ][step],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: nightText,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Surface(
            child: AnimatedSwitcher(
              duration: motionTime(context, 320),
              child: Column(
                key: ValueKey(step),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step < 3) ...[
                    Text(
                      'Step ${step + 1} of 3',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TweenAnimationBuilder<double>(
                        duration: motionTime(context, 400),
                        tween: Tween(end: (step + 1) / 3),
                        builder: (_, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: pale,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (step == 0) ...[
                    const Text(
                      'Who are we caring for today?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: c.activeMembers
                          .map(
                            (m) => ChoiceChip(
                              label: Text(m.name),
                              avatar: MemberAvatar(m, size: 24),
                              selected: memberId == m.id,
                              onSelected: (_) => setState(() {
                                memberId = m.id;
                                preparation.fillRange(0, 3, false);
                                c.endMeasurement();
                              }),
                            ),
                          )
                          .toList(),
                    ),
                    TextButton.icon(
                      onPressed: addPerson,
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: const Text('Add someone'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: person == null
                          ? null
                          : () => setState(() {
                              step = 1;
                              error = null;
                              c.endMeasurement();
                            }),
                      child: const Text('Let’s begin'),
                    ),
                  ],
                  if (step == 1) ...[
                    Text(
                      'Ready, ${person?.name ?? 'friend'}?',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Find a comfy spot. Aim the sensor at the skin you want to measure, following your device’s setup, and hold still for a moment.',
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(
                      3,
                      (i) => Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            [
                              'Rested indoors, away from direct heat or drafts',
                              'Same exposed skin site as previous check-ins',
                              'Sensor aimed and held at the validated device distance',
                            ][i],
                          ),
                          value: preparation[i],
                          onChanged: busy
                              ? null
                              : (value) {
                                  setState(
                                    () => preparation[i] = value == true,
                                  );
                                  if (prepared) {
                                    c.beginMeasurement();
                                  } else {
                                    c.endMeasurement();
                                    c.measurements.reset();
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      !prepared
                          ? 'Complete the checklist, then hold still.'
                          : !c.measuring
                          ? 'Reading paused. Tap Try again when you are ready.'
                          : !c.fresh
                          ? 'Waiting for a fresh device reading.'
                          : c.measurementReady
                          ? 'Ready to capture · three stable readings'
                          : c.measurements.count == 3
                          ? 'Readings are still changing. Hold position and avoid drafts.'
                          : 'Hold still · checking three fresh readings (${c.measurements.count}/3)',
                      style: TextStyle(
                        color: prepared && c.measurementReady ? teal : muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (prepared && !c.measuring)
                      OutlinedButton.icon(
                        onPressed: c.beginMeasurement,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    const Text(
                      'Sampling runs for up to one minute, and stops when you capture or leave this check-in. Stability helps repeatability; it does not verify accuracy.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This sensor measures skin-surface temperature. It does not confirm a fever.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: busy || !prepared || !c.measurementReady
                          ? null
                          : capture,
                      icon: Icon(
                        busy
                            ? Icons.hourglass_top_rounded
                            : Icons.sensors_rounded,
                      ),
                      label: Text(
                        busy ? 'Taking a moment…' : 'Capture reading',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              step = 0;
                              error = null;
                              c.endMeasurement();
                            }),
                      child: const Text('Choose someone else'),
                    ),
                  ],
                  if (step == 2) ...[
                    Text(
                      draft!.member.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${c.unit.format(draft!.reading.celsius)} ${c.unit.symbol}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: teal,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      DateFormat(
                        'MMM d · h:mm:ss a',
                      ).format(draft!.reading.at.toLocal()),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 18),
                    if (draft!.reading.celsius >= c.threshold) ...[
                      TemperatureAlertNotice(
                        reading: draft!.reading,
                        person: draft!.member.name,
                        threshold: c.threshold,
                        unit: c.unit,
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextField(
                      controller: note,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'A note for this reading (optional)',
                        hintText: 'After a nap, feeling a little tired…',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : save,
                      icon: const Icon(Icons.favorite_border_rounded),
                      label: Text(
                        busy ? 'Saving your moment…' : 'Save check-in',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              step = 1;
                              draft = null;
                              error = null;
                              c.beginMeasurement();
                            }),
                      child: const Text('Take another reading'),
                    ),
                  ],
                  if (step == 3) ...[
                    const Icon(
                      Icons.check_circle_rounded,
                      color: teal,
                      size: 52,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'You made time for ${draft!.member.name}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Their reading and note are together in History and the family calendar.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('All done'),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(error!, style: const TextStyle(color: amber)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class FamilyCareCalendar extends StatefulWidget {
  const FamilyCareCalendar({
    super.key,
    required this.controller,
    required this.onReadingTap,
  });
  final MonitorController controller;
  final ValueChanged<Reading> onReadingTap;
  @override
  State<FamilyCareCalendar> createState() => _FamilyCareCalendarState();
}

class _FamilyCareCalendarState extends State<FamilyCareCalendar> {
  DateTime selected = careDay(DateTime.now());
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? memberId;
  MonitorController get c => widget.controller;
  void move(int offset) => setState(() {
    month = DateTime(month.year, month.month + offset);
    selected = month;
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final days = DateTime(month.year, month.month + 1, 0).day;
      final offset = month.weekday - 1;
      final readings = checkInsOn(c.records, selected, memberId: memberId);
      final planned =
          c.reminders
              .where(
                (r) =>
                    r.enabled &&
                    !selected.isBefore(careDay(DateTime.now())) &&
                    r.weekdays.contains(selected.weekday) &&
                    (memberId == null || memberId == r.memberId) &&
                    c.activeMembers.any((m) => m.id == r.memberId),
              )
              .toList()
            ..sort(
              (a, b) =>
                  (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
            );
      final monthRecords = c.records
          .where(
            (r) =>
                r.memberId != null &&
                (memberId == null || r.memberId == memberId) &&
                r.at.toLocal().year == month.year &&
                r.at.toLocal().month == month.month,
          )
          .toList();
      final counts = <int, int>{};
      for (final r in monthRecords) {
        counts.update(r.at.toLocal().day, (n) => n + 1, ifAbsent: () => 1);
      }
      return CarePage(
        title: 'Family care calendar',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Little moments, remembered.',
              style: TextStyle(
                color: nightText,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dots mark saved family check-ins. Tap a day to see their readings and notes.',
              style: TextStyle(color: nightMuted),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Everyone'),
                  selected: memberId == null,
                  onSelected: (_) => setState(() => memberId = null),
                ),
                ...c.members.map(
                  (m) => ChoiceChip(
                    label: Text('${m.name}${m.archived ? ' (archived)' : ''}'),
                    avatar: MemberAvatar(m, size: 24),
                    selected: memberId == m.id,
                    onSelected: (_) => setState(() => memberId = m.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (planned.isNotEmpty) ...[
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Planned moments',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...planned.map(
                      (r) => _CareListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.notifications_none_rounded,
                          color: teal,
                        ),
                        title: Text(
                          c.activeMembers
                              .firstWhere((m) => m.id == r.memberId)
                              .name,
                        ),
                        subtitle: Text(
                          TimeOfDay(
                            hour: r.hour,
                            minute: r.minute,
                          ).format(context),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            openCheckIn(context, c, memberId: r.memberId),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            Surface(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => move(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => move(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selected = careDay(DateTime.now());
                      month = DateTime(selected.year, selected.month);
                    }),
                    child: const Text('Back to today'),
                  ),
                  Row(
                    children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                        .map(
                          (day) => Expanded(
                            child: Text(
                              day,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: muted),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: motionTime(context, 250),
                    child: GridView.builder(
                      key: ValueKey(month),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 5,
                        crossAxisSpacing: 3,
                        mainAxisExtent: MediaQuery.textScalerOf(
                          context,
                        ).scale(42).clamp(48, 70),
                      ),
                      itemCount: ((offset + days + 6) ~/ 7) * 7,
                      itemBuilder: (context, i) {
                        final day = i - offset + 1;
                        if (day < 1 || day > days) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime(month.year, month.month, day);
                        final chosen = date == selected;
                        final count = counts[day] ?? 0;
                        final today = date == careDay(DateTime.now());
                        return Semantics(
                          label:
                              '${DateFormat('MMMM d').format(date)}, $count saved check-ins',
                          selected: chosen,
                          button: true,
                          child: MotionPress(
                            child: InkWell(
                              onTap: () => setState(() => selected = date),
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: motionTime(context, 200),
                                decoration: BoxDecoration(
                                  color: chosen
                                      ? teal
                                      : today
                                      ? pale
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: chosen ? Colors.white : ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: count == 0
                                            ? Colors.transparent
                                            : chosen
                                            ? Colors.white
                                            : teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${monthRecords.length} saved check-in${monthRecords.length == 1 ? '' : 's'} this month',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    DateFormat('EEEE, MMMM d').format(selected),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (readings.isEmpty)
                    const Text(
                      'No saved check-ins on this day. There’s always room for a little moment of care.',
                      style: TextStyle(color: muted),
                    ),
                  ...readings.map(
                    (r) => _CareListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.memberName(r)),
                      subtitle: Text(
                        '${DateFormat('h:mm a').format(r.at.toLocal())}${r.note.isEmpty ? '' : '\n${r.note}'}',
                      ),
                      trailing: Text(
                        '${c.unit.format(r.celsius)} ${c.unit.symbol}',
                        style: const TextStyle(
                          color: teal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () => widget.onReadingTap(r),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CareListTile extends StatelessWidget {
  const _CareListTile({
    this.contentPadding,
    this.leading,
    this.trailing,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final EdgeInsetsGeometry? contentPadding;
  final Widget? leading;
  final Widget? trailing;
  final Widget title;
  final Widget subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      contentPadding: contentPadding,
      leading: leading,
      trailing: trailing,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    ),
  );
}

class PersonalReminders extends StatelessWidget {
  const PersonalReminders({super.key, required this.controller});
  final MonitorController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => CarePage(
      title: 'Family reminders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: CareMascot(width: 120)),
          const Text(
            'A gentle nudge, your way.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: nightText,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.store.ownerId == null
                ? 'Choose a person, a time, and the days that suit your family. Sign in to share reminders across phones.'
                : 'Reminders are shared with phones using your family account. Each phone follows its own local time. Open the app online on each phone to receive new or changed schedules.',
            textAlign: TextAlign.center,
            style: TextStyle(color: nightMuted),
          ),
          const SizedBox(height: 18),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  controller.reminderGateway.backgroundSupported
                      ? 'Your phone can notify you even when the app is closed. Allow notifications when asked. Delivery may vary with battery settings.'
                      : 'On the web, reminders appear while ThermoCare is open. Use the installed mobile app for notifications when it is closed.',
                  style: const TextStyle(color: muted),
                ),
                if (controller.reminderGateway.backgroundSupported)
                  TextButton.icon(
                    onPressed: controller.enableReminderNotifications,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Enable notifications on this phone'),
                  ),
                if (controller.reminderWarning != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.reminderWarning!,
                    style: const TextStyle(color: amber),
                  ),
                  TextButton(
                    onPressed: () async {
                      await controller.enableReminderNotifications();
                    },
                    child: const Text('Try notifications again'),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      controller.activeMembers.isEmpty ||
                          controller.reminders.length >= 8
                      ? null
                      : () => editReminder(context, controller),
                  icon: const Icon(Icons.add_alarm_rounded),
                  label: const Text('Add a reminder'),
                ),
                if (controller.activeMembers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Add a family member in Settings first.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                if (controller.reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text(
                      'No reminders yet. You can start with just one.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ...controller.reminders.map((r) {
                  FamilyMember? member;
                  for (final m in controller.members) {
                    if (m.id == r.memberId) member = m;
                  }
                  final inactive = member == null || member.archived;
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: pale.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (member != null) ...[
                                  MemberAvatar(member),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    member?.name ?? 'Unavailable profile',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: r.enabled && !inactive,
                                  onChanged: inactive
                                      ? null
                                      : (value) async {
                                          try {
                                            await controller.saveReminder(
                                              r.withEnabled(value),
                                            );
                                          } catch (e) {
                                            if (context.mounted) {
                                              careToast(context, e);
                                            }
                                          }
                                        },
                                ),
                              ],
                            ),
                            Text(
                              TimeOfDay(
                                hour: r.hour,
                                minute: r.minute,
                              ).format(context),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              r.weekdays.length == 7
                                  ? 'Every day'
                                  : r.weekdays
                                        .map(
                                          (d) => [
                                            'Mon',
                                            'Tue',
                                            'Wed',
                                            'Thu',
                                            'Fri',
                                            'Sat',
                                            'Sun',
                                          ][d - 1],
                                        )
                                        .join(' · '),
                              style: const TextStyle(color: muted),
                            ),
                            if (inactive)
                              const Text(
                                'Paused while this profile is archived or unavailable.',
                                style: TextStyle(color: muted),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: inactive
                                      ? null
                                      : () => editReminder(
                                          context,
                                          controller,
                                          reminder: r,
                                        ),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Edit'),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      await controller.deleteReminder(r.id);
                                    } catch (e) {
                                      if (context.mounted) {
                                        careToast(context, e);
                                      }
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void careToast(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is FormatException
              ? error.message
              : 'That could not save. Please try again.',
        ),
      ),
    );

Future<void> editReminder(
  BuildContext context,
  MonitorController c, {
  CareReminder? reminder,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReminderEditor(controller: c, reminder: reminder),
);

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.controller, this.reminder});
  final MonitorController controller;
  final CareReminder? reminder;
  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late String memberId =
      widget.reminder?.memberId ??
      widget.controller.selectedMember?.id ??
      widget.controller.activeMembers.first.id;
  late TimeOfDay time = widget.reminder == null
      ? const TimeOfDay(hour: 19, minute: 0)
      : TimeOfDay(hour: widget.reminder!.hour, minute: widget.reminder!.minute);
  late final days = (widget.reminder?.weekdays ?? [1, 2, 3, 4, 5, 6, 7])
      .toSet();
  bool busy = false;
  String? error;
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.saveReminder(
        CareReminder(
          id: widget.reminder?.id ?? newFamilyId(),
          memberId: memberId,
          hour: time.hour,
          minute: time.minute,
          weekdays: days.toList()..sort(),
          enabled: widget.reminder?.enabled ?? true,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'That reminder could not save. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reminder == null ? 'Make a little time.' : 'Your little reminder.',
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: memberId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'For someone you love',
              ),
              items: widget.controller.activeMembers
                  .map(
                    (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                  )
                  .toList(),
              onChanged: busy ? null : (id) => setState(() => memberId = id!),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (picked != null && mounted) {
                        setState(() => time = picked);
                      }
                    },
              icon: const Icon(Icons.schedule_rounded),
              label: Text(time.format(context)),
            ),
            const SizedBox(height: 16),
            const Text('On these days'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(
                7,
                (i) => FilterChip(
                  label: Text(
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                  ),
                  selected: days.contains(i + 1),
                  onSelected: busy
                      ? null
                      : (value) => setState(() {
                          if (value) {
                            days.add(i + 1);
                          } else {
                            days.remove(i + 1);
                          }
                        }),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: amber)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Maybe later'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Saving…' : 'Save reminder'),
      ),
    ],
  );
}

/// A reading detail can edit a note without changing the measured value.
class ReadingNote extends StatefulWidget {
  const ReadingNote({
    super.key,
    required this.controller,
    required this.reading,
  });
  final MonitorController controller;
  final Reading reading;
  @override
  State<ReadingNote> createState() => _ReadingNoteState();
}

class _ReadingNoteState extends State<ReadingNote> {
  late final text = TextEditingController(text: widget.reading.note);
  bool busy = false;
  String? feedback;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: text,
        maxLength: 500,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Your note',
          hintText: 'Anything you’d like to remember…',
        ),
      ),
      if (widget.reading.memberId == null)
        const Text(
          'Notes on automatic samples stay on this device until the reading is saved for a family member.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    feedback = null;
                  });
                  try {
                    await widget.controller.updateNote(
                      widget.reading,
                      text.text,
                    );
                    if (mounted) {
                      setState(() => feedback = 'Your note is saved.');
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => feedback = e is FormatException
                            ? e.message
                            : 'That note could not save. Please try again.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(busy ? 'Saving…' : 'Save note'),
        ),
      ),
      if (feedback != null)
        Text(feedback!, style: const TextStyle(color: teal)),
    ],
  );
}
