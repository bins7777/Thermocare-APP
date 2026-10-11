import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../controller.dart';
import '../models.dart';
import '../data/accounts.dart';
import '../data/store.dart';
import 'family_widgets.dart';
import 'night_art.dart';
import 'motion.dart';
import 'chart.dart';
import 'theme.dart';
import 'care_pages.dart';
import 'personal_trends.dart';
import '../product.dart';
import 'temperature_alert.dart';

class ThermoCareApp extends StatelessWidget {
  const ThermoCareApp({
    super.key,
    required this.controller,
    this.accounts,
    this.firebaseSetupError,
  });
  final MonitorController controller;
  final FamilyAccounts? accounts;
  final String? firebaseSetupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ThermoCare',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        expansionTileTheme: ExpansionTileThemeData(
          expansionAnimationStyle: AnimationStyle(
            duration: motionTime(context, 340),
            reverseDuration: motionTime(context, 260),
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
      ),
      child: child!,
    ),
    home: MonitorShell(
      controller: controller,
      accounts: accounts,
      firebaseSetupError: firebaseSetupError,
    ),
  );
}

class MonitorShell extends StatefulWidget {
  const MonitorShell({
    super.key,
    required this.controller,
    this.accounts,
    this.firebaseSetupError,
  });
  final MonitorController controller;
  final FamilyAccounts? accounts;
  final String? firebaseSetupError;
  @override
  State<MonitorShell> createState() => _MonitorShellState();
}

class _MonitorShellState extends State<MonitorShell>
    with WidgetsBindingObserver {
  MonitorController get c => widget.controller;
  int tab = 0;
  String range = 'Today';
  bool onlyAbove = false;
  String memberFilter = 'all';
  int historyLimit = 50;
  int cheer = 0;
  bool foreground = true;
  bool forward = true;
  bool saving = false;
  bool refreshing = false;
  bool syncingClock = false;
  bool connecting = false;
  late final TextEditingController address;
  late final TextEditingController threshold;
  String? addressError;
  static const titles = ['Home', 'History', 'My device', 'Settings'];
  static const icons = [
    Icons.cottage_outlined,
    Icons.history_rounded,
    Icons.sensors_rounded,
    Icons.tune_rounded,
  ];

  @override
  void initState() {
    super.initState();
    address = TextEditingController(text: c.address);
    threshold = TextEditingController(text: c.threshold.toStringAsFixed(1));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    address.dispose();
    threshold.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (foreground != visible && mounted) setState(() => foreground = visible);
    if (state == AppLifecycleState.resumed) {
      c.resume();
    } else if ([
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ].contains(state)) {
      c.pause();
    }
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> action(Future<void> Function() callback, String success) async {
    try {
      await callback();
      toast(success);
    } catch (e) {
      toast(
        e is FormatException
            ? e.message
            : 'That did not go through. Please give it another try.',
      );
    }
  }

  void select(int index) {
    if (tab == index) return;
    setState(() {
      forward = index > tab;
      tab = index;
    });
  }

  Widget _pageMotion(Widget page) => ClipRect(
    child: AnimatedSwitcher(
      duration: motionTime(context, 360),
      reverseDuration: motionTime(context, 160),
      switchInCurve: const Interval(.15, 1, curve: Curves.easeOutCubic),
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => IgnorePointer(
        ignoring: child.key != ValueKey(tab),
        child: ExcludeSemantics(
          excluding: child.key != ValueKey(tab),
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(forward ? .035 : -.035, .012),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        ),
      ),
      child: page,
    ),
  );
  String get connectionLabel => c.fresh
      ? 'Connected'
      : c.active
      ? c.busy
            ? 'Connecting'
            : c.error != null
            ? 'Check connection'
            : 'Ready to read'
      : 'Not connected';
  List<Reading> get filtered {
    final now = DateTime.now();
    final start = range == 'Today'
        ? DateTime(now.year, now.month, now.day)
        : range == '7 days'
        ? now.subtract(const Duration(days: 7))
        : null;
    return c.records
        .where(
          (r) =>
              (start == null || !r.at.isBefore(start)) &&
              ((memberFilter == 'all' && r.memberId != null) ||
                  (memberFilter == 'unassigned'
                      ? r.memberId == null
                      : r.memberId == memberFilter)) &&
              (!onlyAbove || r.celsius >= c.threshold),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 900;
      return TickerMode(
        enabled: foreground,
        child: NightBackdrop(
          showMoon: tab == 0,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            bottomNavigationBar: wide
                ? null
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0x334B3E78))),
                    ),
                    child: NavigationBar(
                      animationDuration: motionTime(context, 400),
                      selectedIndex: tab == 3 ? 2 : tab,
                      onDestinationSelected: select,
                      destinations: List.generate(
                        3,
                        (i) => NavigationDestination(
                          icon: AnimatedScale(
                            scale: tab == i ? 1.12 : 1,
                            duration: motionTime(context, 300),
                            curve: Curves.easeOutBack,
                            child: Icon(icons[i]),
                          ),
                          label: titles[i],
                        ),
                      ),
                    ),
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide) _sidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        _topbar(wide),
                        Expanded(
                          child: _pageMotion(
                            SingleChildScrollView(
                              key: ValueKey(tab),
                              physics: reduceMotion(context)
                                  ? const ClampingScrollPhysics()
                                  : const BouncingScrollPhysics(),
                              padding: EdgeInsets.all(wide ? 32 : 18),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1080,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (c.error != null ||
                                          c.syncWarning != null) ...[
                                        _errorBanner(),
                                        const SizedBox(height: 18),
                                      ],
                                      switch (tab) {
                                        0 => _home(),
                                        1 => _history(),
                                        2 => _device(),
                                        _ => _settings(),
                                      },
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _brand() => const Text(
    'ThermoCare',
    style: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w900,
      color: nightText,
      letterSpacing: -.8,
    ),
  );

  Widget _sidebar() => Container(
    width: 240,
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
    decoration: const BoxDecoration(
      color: Color(0x66131029),
      border: Border(right: BorderSide(color: Color(0x334B3E78))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: _brand()),
        const SizedBox(height: 10),
        const Text(
          'Always a little care, every day.',
          style: TextStyle(fontSize: 13, color: nightMuted),
        ),
        const SizedBox(height: 42),
        ...List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: tab == i ? pale : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: MotionPress(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => select(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icons[i],
                          color: tab == i ? teal : nightMuted,
                          size: 23,
                        ),
                        const SizedBox(width: 13),
                        Text(
                          titles[i],
                          style: TextStyle(
                            color: tab == i ? ink : nightMuted,
                            fontSize: 16,
                            fontWeight: tab == i
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        const Center(child: CareMascot(width: 160)),
        const SizedBox(height: 16),
        const Text(
          'A little moment of care.',
          style: TextStyle(
            color: nightText,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your quiet companion for everyday temperature check-ins.',
          style: TextStyle(color: nightMuted, fontSize: 14, height: 1.5),
        ),
      ],
    ),
  );

  Widget _topbar(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 20, wide ? 32 : 18, 8),
    child: Row(
      children: [
        if (!wide) const SizedBox(width: 48),
        Expanded(
          child: Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (wide)
                Text(
                  titles[tab],
                  style: const TextStyle(
                    color: nightText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                FittedBox(fit: BoxFit.scaleDown, child: _brand()),
              const SizedBox(height: 3),
              const Text(
                'Always a little care, every day.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: nightMuted),
              ),
            ],
          ),
        ),
        MotionPress(
          child: IconButton(
            tooltip: tab == 3 ? 'Close settings' : 'Settings',
            onPressed: () => select(tab == 3 ? 2 : 3),
            icon: AnimatedRotation(
              turns: tab == 3 ? .25 : 0,
              duration: motionTime(context, 400),
              curve: Curves.easeOutCubic,
              child: Icon(
                tab == 3 ? Icons.close_rounded : Icons.settings_outlined,
              ),
            ),
            color: nightMuted,
          ),
        ),
      ],
    ),
  );

  Widget _errorBanner() => Surface(
    color: peach,
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: amber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.error != null
                    ? 'Let’s reconnect your thermometer.'
                    : 'Your history needs a moment.',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: amber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          c.error ?? c.syncWarning!,
          style: const TextStyle(color: ink, fontSize: 14),
        ),
        const SizedBox(height: 7),
        MotionPress(
          child: TextButton.icon(
            onPressed: c.busy ? null : () => c.poll(forceHistory: true),
            icon: const Icon(Icons.refresh_rounded, size: 19),
            label: const Text('Try again'),
          ),
        ),
      ],
    ),
  );

  Widget _intro(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge!.copyWith(color: nightText),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(color: nightMuted, fontSize: 16, height: 1.5),
        ),
      ],
    ),
  );

  Widget _home() => LayoutBuilder(
    builder: (context, constraints) {
      final extras = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _quickActions(),
          const SizedBox(height: 14),
          _careActions(),
          if (c.dueMemberId != null) ...[
            const SizedBox(height: 14),
            _dueReminder(),
          ],
          const SizedBox(height: 14),
          _connectionStrip(),
          const SizedBox(height: 14),
          _lastCheckIn(),
          const SizedBox(height: 14),
          _gentleHelp(),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.activeMembers.isEmpty) ...[
            _gettingStarted(),
            const SizedBox(height: 18),
          ],
          if (constraints.maxWidth >= 720)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: _nightReading()),
                const SizedBox(width: 22),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 110),
                    child: extras,
                  ),
                ),
              ],
            )
          else ...[
            _nightReading(),
            const SizedBox(height: 14),
            extras,
          ],
          const SizedBox(height: 18),
          _measurementNote(),
        ],
      );
    },
  );

  Widget _gettingStarted() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Welcome to ThermoCare',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'Add someone you care for, connect your thermometer, and save your first check-in.',
          style: TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _editProfile(),
          icon: const Icon(Icons.person_add_alt_rounded),
          label: const Text('Add your first family member'),
        ),
        OutlinedButton.icon(
          onPressed: () => select(2),
          icon: const Icon(Icons.wifi_rounded),
          label: const Text('Set up your thermometer'),
        ),
        if (widget.accounts != null && widget.accounts!.user == null)
          TextButton(
            onPressed: () => showFamilySignIn(context, widget.accounts!),
            child: const Text('Sign in or create a family account'),
          ),
        const Text(
          'A family account shares check-ins and reminders across your phones. You can start saving on this phone while offline.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  Widget _nightReading() {
    final compact = MediaQuery.sizeOf(context).height < 740;
    final width = compact ? 185.0 : 220.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: 0,
          child: Semantics(
            button: true,
            label: 'Say hello to your care companion',
            child: GestureDetector(
              onTap: () => setState(() => cheer++),
              child: CheerMotion(
                trigger: cheer,
                child: CareMascot(width: width),
              ),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(height: width * .535),
            _readingCard(),
          ],
        ),
        Positioned(
          top: 0,
          child: IgnorePointer(
            child: CheerMotion(
              trigger: cheer,
              child: CareMascot(width: width, pawsOnly: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickActions() => LayoutBuilder(
    builder: (context, constraints) {
      final history = _quickAction(
        'View history',
        Icons.description_outlined,
        () => select(1),
      );
      final share = _quickAction(
        'Share record',
        Icons.ios_share_rounded,
        !c.records.any((r) => r.memberId != null)
            ? null
            : () =>
                  _export(c.records.where((r) => r.memberId != null).toList()),
      );
      return MediaQuery.textScalerOf(context).scale(1) > 1.25
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EnterMotion(delay: 90, child: history),
                const SizedBox(height: 12),
                EnterMotion(delay: 170, child: share),
              ],
            )
          : Row(
              children: [
                Expanded(child: EnterMotion(delay: 90, child: history)),
                const SizedBox(width: 12),
                Expanded(child: EnterMotion(delay: 170, child: share)),
              ],
            );
    },
  );

  void _openCalendar() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          FamilyCareCalendar(controller: c, onReadingTap: _readingDetails),
    ),
  );

  void _openReminders() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => PersonalReminders(controller: c)),
  );

  Widget _careActions() => Surface(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'A little care, together.',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        const Text(
          'Your companion will take it one small step at a time.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        MotionPress(
          child: FilledButton.icon(
            onPressed: () => openCheckIn(context, c),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Start guided check-in'),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _openCalendar,
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              label: const Text('Family calendar'),
            ),
            TextButton.icon(
              onPressed: _openReminders,
              icon: const Icon(Icons.notifications_active_outlined, size: 20),
              label: const Text('Reminders'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PersonalTrends(
                    controller: c,
                    onReadingTap: _readingDetails,
                  ),
                ),
              ),
              icon: const Icon(Icons.insights_rounded, size: 20),
              label: const Text('Personal trends'),
            ),
          ],
        ),
        if (c.reminderWarning != null)
          Text(
            c.reminderWarning!,
            style: const TextStyle(color: amber, fontSize: 12),
          ),
      ],
    ),
  );

  Widget _dueReminder() {
    final id = c.dueMemberId;
    final name =
        c.activeMembers.where((m) => m.id == id).firstOrNull?.name ??
        'your family';
    return Surface(
      color: lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A little moment for $name?',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your planned check-in is here. Start whenever you’re ready.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              c.dismissReminder();
              openCheckIn(context, c, memberId: id);
            },
            child: const Text('Begin check-in'),
          ),
          TextButton(
            onPressed: c.dismissReminder,
            child: const Text('Maybe later'),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(String label, IconData icon, VoidCallback? onTap) =>
      Material(
        color: card,
        borderRadius: BorderRadius.circular(24),
        child: MotionPress(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: pale,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          icon,
                          color: onTap == null ? muted : teal,
                          size: 23,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: onTap == null ? muted : teal,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: onTap == null ? muted : ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _connectionStrip() => Material(
    color: c.active && c.error == null ? pale : peach,
    borderRadius: BorderRadius.circular(20),
    child: MotionPress(
      child: InkWell(
        onTap: () => select(2),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                c.active && c.error == null
                    ? Icons.wifi_rounded
                    : Icons.wifi_off_rounded,
                color: teal,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.fresh
                      ? 'Your thermometer is connected'
                      : c.active && c.error == null
                      ? 'Ready when you tap Get reading'
                      : 'Connect your thermometer',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: teal, size: 20),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _readingCard() => Surface(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _memberPicker(),
        if (c.temperatureAlert case final alert?) ...[
          const SizedBox(height: 16),
          Surface(
            color: peach,
            padding: const EdgeInsets.all(16),
            child: TemperatureAlertNotice(
              reading: alert,
              person: c.memberName(alert),
              threshold: c.threshold,
              unit: c.unit,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Last requested reading',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: muted,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          label: c.hasReading
              ? 'Surface temperature ${c.unit.format(c.latest!.celsius)} ${c.unit.symbol}'
              : 'Tap Get reading to measure',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: c.hasReading ? motionTime(context, 200) : Duration.zero,
              child: Text(
                key: ValueKey(
                  c.hasReading
                      ? '${c.unit.format(c.latest!.celsius)}${c.unit.symbol}'
                      : 'waiting',
                ),
                c.hasReading
                    ? '${c.unit.format(c.latest!.celsius)}${c.unit.symbol}'
                    : '— —${c.unit.symbol}',
                style: const TextStyle(
                  fontSize: 66,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.5,
                  color: ink,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Center(
          child: Pill(
            c.aboveThreshold ? 'Above your reference' : 'Skin-surface reading',
            color: c.aboveThreshold ? amber : teal,
            icon: c.aboveThreshold
                ? Icons.info_outline_rounded
                : Icons.thermostat_rounded,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          c.hasReading
              ? DateFormat(
                  'MMM d, yyyy  ·  h:mm a',
                ).format(c.lastContact!.toLocal())
              : 'Ready whenever you are.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 15),
        const Text(
          'Updates only when you ask. Guided check-ins sample while you capture.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        MotionPress(
          child: FilledButton.icon(
            onPressed: refreshing || c.busy ? null : _getReading,
            icon: Icon(
              refreshing ? Icons.hourglass_top_rounded : Icons.wifi_rounded,
              size: 24,
            ),
            label: Text(refreshing ? 'Getting reading…' : 'Get reading'),
          ),
        ),
        MotionPress(
          child: TextButton.icon(
            onPressed: !c.active || saving || c.selectedMember == null
                ? null
                : () => openCheckIn(context, c),
            icon: Icon(
              saving
                  ? Icons.hourglass_top_rounded
                  : Icons.bookmark_add_outlined,
              size: 19,
            ),
            label: Text(saving ? 'Saving…' : 'Save reading'),
          ),
        ),
      ],
    ),
  );

  Future<void> _getReading() async {
    if (!c.active) {
      select(2);
      return;
    }
    setState(() => refreshing = true);
    try {
      await c.poll(forceHistory: true);
      if (mounted && c.fresh) setState(() => cheer++);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Widget _memberPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Who are we checking?',
              style: TextStyle(
                color: muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          MotionPress(
            child: IconButton(
              tooltip: 'Add family member',
              onPressed: () => _editProfile(),
              icon: const Icon(Icons.person_add_alt_rounded, size: 21),
            ),
          ),
        ],
      ),
      if (c.activeMembers.isEmpty)
        OutlinedButton.icon(
          onPressed: () => _editProfile(),
          icon: const Icon(Icons.favorite_border_rounded),
          label: const Text('Add someone you love'),
        )
      else
        DropdownButtonFormField<String>(
          key: ValueKey(
            '${c.selectedMember?.id}/${c.activeMembers.map((m) => '${m.id}:${m.name}').join()}',
          ),
          initialValue: c.selectedMember?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          hint: const Text('Choose a family member'),
          items: c.activeMembers
              .map(
                (m) => DropdownMenuItem(
                  value: m.id,
                  child: Row(
                    children: [
                      MemberAvatar(m, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(m.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id != null) {
              action(
                () => c.selectMember(id),
                'Ready for ${c.activeMembers.firstWhere((m) => m.id == id).name}.',
              );
            }
          },
        ),
    ],
  );

  Widget _memberFilterChip(String id, String name, {FamilyMember? member}) =>
      MotionPress(
        child: ChoiceChip(
          avatar: member == null ? null : MemberAvatar(member, size: 24),
          label: Text(name),
          selected: memberFilter == id,
          onSelected: (_) => setState(() {
            memberFilter = id;
            historyLimit = 50;
          }),
        ),
      );

  Future<void> _editProfile([FamilyMember? member]) async {
    final result = await editMember(context, member: member);
    if (result == null || !mounted) return;
    await action(
      () => c.saveMember(existing: member, name: result.$1, avatar: result.$2),
      '${result.$1} has a little place here.',
    );
  }

  Widget _familyCard() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('Your family'),
        const SizedBox(height: 8),
        Text(
          'A little place for everyone you care for.',
          style: const TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        ...c.members.map(
          (member) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                MemberAvatar(member, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        member.archived
                            ? 'Archived · history kept'
                            : '${c.records.where((r) => r.memberId == member.id).length} saved check-ins',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit ${member.name}',
                  onPressed: () => _editProfile(member),
                  icon: const Icon(Icons.edit_outlined, size: 21),
                ),
                IconButton(
                  tooltip: member.archived
                      ? 'Restore ${member.name}'
                      : 'Archive ${member.name}',
                  onPressed: () => action(
                    () => c.saveMember(
                      existing: member,
                      name: member.name,
                      avatar: member.avatar,
                      archived: !member.archived,
                    ),
                    member.archived
                        ? '${member.name} is back in your family list.'
                        : 'Profile archived. Their history is still here.',
                  ),
                  icon: Icon(
                    member.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        MotionPress(
          child: OutlinedButton.icon(
            onPressed: () => _editProfile(),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Add family member'),
          ),
        ),
      ],
    ),
  );

  Widget _accountCard() {
    final accounts = widget.accounts;
    final cloud = c.cloud;
    final signedIn = accounts?.user != null;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Your family account'),
          const SizedBox(height: 10),
          Text(
            signedIn
                ? c.accountEmail ?? 'Signed in'
                : 'Keep your family’s check-ins together.',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            signedIn
                ? 'Saved on this phone first. Family check-ins sync when you have internet, and appear on other phones using this account.'
                : 'Sign in to keep profiles, check-ins and reminders together across your family’s phones. You can also save on this phone without an account.',
            style: const TextStyle(color: muted, height: 1.6),
          ),
          if (signedIn && cloud != null) ...[
            const SizedBox(height: 14),
            _detail(
              'Cloud saves',
              cloud.error != null
                  ? cloud.error!
                  : cloud.syncing
                  ? 'Syncing with care…'
                  : cloud.pending > 0
                  ? '${cloud.pending} changes waiting to upload'
                  : 'All queued changes uploaded',
            ),
            if (cloud.lastSynced != null)
              _detail(
                'Last upload',
                DateFormat('MMM d · h:mm a').format(cloud.lastSynced!),
              ),
            OutlinedButton.icon(
              onPressed: cloud.syncing ? null : cloud.flush,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('Sync now'),
            ),
            OutlinedButton(
              onPressed: _importPhoneProfiles,
              child: const Text('Add this phone’s local profiles to account'),
            ),
          ],
          const SizedBox(height: 14),
          if (accounts == null)
            Text(
              widget.firebaseSetupError ??
                  'Family sync is unavailable. Your records can still save on this phone. Restart the app to try again.',
              style: const TextStyle(color: muted, height: 1.5),
            )
          else if (signedIn)
            TextButton(
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Sign out of your family account?'),
                    content: const Text(
                      'Unsynced changes stay on this phone for this account. Sign back in to upload them. Other accounts cannot see them.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Stay here'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (yes == true) await accounts.signOut();
              },
              child: const Text('Sign out'),
            )
          else
            MotionPress(
              child: FilledButton.icon(
                onPressed: () => showFamilySignIn(context, accounts),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Sign in / Create family account'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importPhoneProfiles() async {
    final local = AppStore(c.store.database);
    final members = await local.loadMembers();
    final readings = await local.loadReadings();
    await local.migrateReminders();
    final reminders = await local.loadReminders();
    if (!mounted) return;
    if (members.isEmpty) {
      toast('No local family profiles to add yet.');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bring these profiles into your family?'),
        content: Text(
          'Add ${members.length} local profiles, their saved check-ins, and ${reminders.length} reminders to this account. Only continue if they belong to this family. Unassigned samples stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Maybe later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add to family'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await action(() async {
      await c.importLocalFamily(members, readings, reminders: reminders);
    }, 'Your phone’s family profiles are ready to sync.');
  }

  Widget _lastCheckIn() => Surface(
    padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
    color: lavender,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, color: teal, size: 25),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Last saved reading',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.records.isEmpty
                        ? 'No readings saved yet'
                        : '${c.unit.format(c.records.first.celsius)} ${c.unit.symbol} · ${DateFormat('d MMM, h:mm a').format(c.records.first.at.toLocal())}',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        MotionPress(
          child: TextButton.icon(
            onPressed: () => select(1),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('See past readings'),
          ),
        ),
      ],
    ),
  );

  Widget _gentleHelp() => Surface(
    color: pale,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.favorite_border_rounded, color: teal),
      title: const Text(
        'A little help with check-ins',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            'Help your loved one get comfortable. Hold the sensor steady with the skin area in view, and take your time.',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
        ),
      ],
    ),
  );

  Widget _measurementNote({bool night = true}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.info_outline_rounded,
        size: 18,
        color: night ? nightMuted : muted,
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          'This is a skin-surface reading. For a body-temperature concern, check with a clinical thermometer.',
          style: TextStyle(
            color: night ? nightMuted : muted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ),
    ],
  );

  Widget _emptyRecords() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(Icons.bookmark_border_rounded, color: teal, size: 34),
        SizedBox(height: 12),
        Text(
          'Your first check-in starts here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 7),
        Text(
          'Save a reading when you’re ready. We’ll keep it here for you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 14),
        ),
      ],
    ),
  );

  Widget _recordRow(Reading r) => Semantics(
    button: true,
    child: MotionPress(
      child: InkWell(
        onTap: () => _readingDetails(r),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 39,
                height: 45,
                decoration: BoxDecoration(
                  color: r.celsius >= c.threshold ? peach : pale,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.thermostat_rounded,
                  size: 23,
                  color: r.celsius >= c.threshold ? amber : teal,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.memberName(r),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('d MMM · h:mm:ss a').format(r.at.toLocal())}${r.memberId == null ? ' · Automatic' : ''}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (r.note.isNotEmpty)
                      Text(
                        r.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: teal, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${c.unit.format(r.celsius)} ${c.unit.symbol}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: r.celsius >= c.threshold ? amber : ink,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
            ],
          ),
        ),
      ),
    ),
  );

  void _readingDetails(Reading r) => showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AnimationStyle(
      duration: motionTime(context, 360),
      reverseDuration: motionTime(context, 250),
    ),
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: card,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            32 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A closer look',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 17),
              Text(
                '${c.unit.format(r.celsius)} ${c.unit.symbol}',
                style: const TextStyle(
                  fontSize: 48,
                  color: teal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Skin-surface temperature',
                style: TextStyle(color: muted, fontSize: 16),
              ),
              const SizedBox(height: 22),
              if (r.memberId != null && r.celsius >= c.threshold) ...[
                TemperatureAlertNotice(
                  reading: r,
                  person: c.memberName(r),
                  threshold: c.threshold,
                  unit: c.unit,
                ),
                const SizedBox(height: 20),
              ],
              _detail('Family member', c.memberName(r)),
              _detail(
                'Saved at',
                DateFormat('d MMM yyyy, h:mm:ss a').format(r.at.toLocal()),
              ),
              _detail(
                'Surroundings',
                '${c.unit.format(r.ambient)} ${c.unit.symbol}',
              ),
              _detail(
                'Time source',
                r.estimatedTime
                    ? 'Estimated from this device'
                    : 'Thermometer clock (UTC)',
              ),
              _detail(
                'Reference',
                '${c.unit.format(c.threshold)} ${c.unit.symbol} · ${r.celsius >= c.threshold ? 'Above reference' : 'Below reference'}',
              ),
              _detail('Thermometer', r.deviceId),
              _detail(
                'Capture preparation',
                r.quality?.prepared == true
                    ? 'Checklist completed · ${r.quality!.sampleCount} stable samples over ${r.quality!.windowSeconds}s'
                    : 'Not recorded for this earlier reading',
              ),
              if (r.quality != null)
                _detail(
                  'Capture variation',
                  '${(r.quality!.surfaceRange * (c.unit == TemperatureUnit.fahrenheit ? 1.8 : 1)).toStringAsFixed(2)} ${c.unit.symbol} surface range',
                ),
              const SizedBox(height: 20),
              ReadingNote(controller: c, reading: r),
              const SizedBox(height: 20),
              _measurementNote(night: false),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _history() {
    final readings = filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro('Your little check-ins.', 'Saved with care, all in one place.'),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            onPressed: _openCalendar,
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('Open family care calendar'),
          ),
        ),
        Surface(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                c.fresh ? Icons.sensors_rounded : Icons.history_rounded,
                color: teal,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.fresh
                      ? 'Last requested sample: ${DateFormat('h:mm:ss a').format(c.lastContact!.toLocal())}. Get reading requests one update.'
                      : 'Saved records stay here. Tap Get reading on Home when you want a new sample.',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _memberFilterChip('all', 'Everyone'),
            ...c.members.map(
              (m) => _memberFilterChip(
                m.id,
                '${m.name}${m.archived ? ' (archived)' : ''}',
                member: m,
              ),
            ),
            _memberFilterChip('unassigned', 'Unassigned'),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...['Today', '7 days', 'All time'].map(
              (r) => MotionPress(
                child: ChoiceChip(
                  label: Text(r),
                  selected: range == r,
                  onSelected: (_) => setState(() {
                    range = r;
                    historyLimit = 50;
                  }),
                ),
              ),
            ),
            MotionPress(
              child: FilterChip(
                label: const Text('Above my reference'),
                selected: onlyAbove,
                onSelected: (v) => setState(() {
                  onlyAbove = v;
                  historyLimit = 50;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: MotionPress(
            child: OutlinedButton.icon(
              onPressed: readings.isEmpty ? null : () => _export(readings),
              icon: const Icon(Icons.ios_share_rounded, size: 21),
              label: const Text('Share these readings'),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Surface(
          child: MotionSize(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeading('Past readings'),
                const SizedBox(height: 5),
                Text(
                  '${readings.length} ${readings.length == 1 ? 'reading' : 'readings'} · ${c.cloud != null ? 'Your family’s history' : 'Saved on this phone'}',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (readings.isEmpty)
                  Center(child: _emptyRecords())
                else
                  ...readings
                      .take(historyLimit)
                      .map(
                        (r) => EnterMotion(
                          key: ValueKey(r.id),
                          child: _recordRow(r),
                        ),
                      ),
                if (readings.length > historyLimit) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => historyLimit += 50),
                      child: Text(
                        'Show older readings (${readings.length - historyLimit} more)',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Everyone shows saved family check-ins. Unassigned contains automatic thermometer samples. To save a check-in for someone, choose them on Home and tap Save reading. Shared records include each person’s name.',
          style: TextStyle(color: nightMuted, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 18),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text(
              'See the temperature trend',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            children: [
              if (memberFilter == 'all')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Choose one person for a meaningful personal comparison.',
                    style: TextStyle(color: muted),
                  ),
                ),
              if (memberFilter == 'all')
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PersonalTrends(
                        controller: c,
                        onReadingTap: _readingDetails,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Open personal trends'),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TemperatureChart(
                    readings: readings.reversed.toList(),
                    unit: c.unit,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _measurementNote(),
      ],
    );
  }

  Future<void> _export(List<Reading> readings) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(readingsCsv(readings))),
              mimeType: 'text/csv',
            ),
          ],
          fileNameOverrides: [
            'thermocare-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
          ],
          subject: 'ThermoCare temperature records',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      toast('The share menu did not open. Please try again.');
    }
  }

  Widget _device() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _intro(
        'Your care companion.',
        'Connect once. Then take a little moment together.',
      ),
      Surface(
        color: pale,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: const Text(
            'Need a hand connecting?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          children: [
            _step(
              '1',
              'Power your thermometer',
              'Use its USB-C cable with a power bank or 5 V USB adapter.',
            ),
            _step(
              '2',
              'Join the same Wi-Fi',
              'At home, use your home network. Away from home, join the thermometer’s ThermoCare network with its separate password.',
            ),
            _step(
              '3',
              'Enter the address on its screen',
              'Look for numbers like 192.168.254.137. On the ThermoCare network, use 192.168.4.1.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('Connect your thermometer'),
            const SizedBox(height: 18),
            TextField(
              controller: address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Address on your thermometer',
                hintText: '192.168.1.42',
                prefixIcon: const Icon(Icons.wifi_rounded),
                errorText: addressError,
              ),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: MotionPress(
                child: FilledButton.icon(
                  onPressed: connecting ? null : () => _connect(),
                  icon: Icon(
                    connecting
                        ? Icons.hourglass_top_rounded
                        : Icons.add_link_rounded,
                    size: 21,
                  ),
                  label: Text(
                    connecting ? 'Connecting…' : 'Connect thermometer',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Joined the ThermoCare Wi-Fi on your phone? Connect directly below. No internet or mobile data is needed for readings.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: connecting ? null : () => _connect(direct: true),
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Connect on ThermoCare Wi-Fi'),
              ),
            ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(c.error!, style: const TextStyle(color: amber, height: 1.5)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.active)
                  MotionPress(
                    child: TextButton(
                      onPressed: c.disconnect,
                      child: const Text('Disconnect'),
                    ),
                  ),
              ],
            ),
            const Divider(height: 30),
            _detail(
              'Connection',
              c.fresh
                  ? 'Connected over Wi-Fi'
                  : c.active
                  ? c.error != null
                        ? 'Check device and Wi-Fi'
                        : 'Ready for an on-demand reading'
                  : 'Not connected yet',
            ),
            _detail(
              'Last reading',
              c.lastContact == null
                  ? 'Waiting for your first reading'
                  : DateFormat('h:mm:ss a').format(c.lastContact!.toLocal()),
            ),
            _detail(
              'History synced',
              c.lastHistorySync == null
                  ? 'Not yet'
                  : DateFormat(
                      'h:mm:ss a',
                    ).format(c.lastHistorySync!.toLocal()),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule_rounded, color: teal, size: 25),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Keep time together',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Set your thermometer’s clock from this device so saved readings have the right date and time.',
              style: TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 17),
            SizedBox(
              width: double.infinity,
              child: MotionPress(
                child: OutlinedButton.icon(
                  onPressed: !c.fresh || syncingClock
                      ? null
                      : () async {
                          setState(() => syncingClock = true);
                          await action(
                            c.syncClock,
                            'Your thermometer’s clock is now set.',
                          );
                          if (mounted) {
                            setState(() => syncingClock = false);
                          }
                        },
                  icon: const Icon(Icons.sync_rounded, size: 21),
                  label: Text(
                    syncingClock ? 'Setting the clock…' : 'Sync device clock',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'About your thermometer',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Using your thermometer',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text(
                'The thermometer measures exposed skin-surface temperature. Use the same skin site and device setup for each check-in. Keep the thermometer on your trusted local Wi-Fi network. It does not need a computer once set up.',
                style: TextStyle(color: muted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _step(String number, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: card, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(
              color: teal,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _connect({bool direct = false}) async {
    if (connecting) return;
    setState(() {
      connecting = true;
      addressError = null;
      if (direct) address.text = '192.168.4.1';
    });
    try {
      deviceUri(address.text);
      await c.connect(address.text);
      if (mounted && c.fresh) {
        toast('You’re connected. Ready for a little check-in.');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => addressError = e is FormatException
              ? e.message
              : 'We could not save that connection. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _intro('Make yourself at home.', 'A few small settings, just for you.'),
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: OutlinedButton.icon(
          onPressed: _openReminders,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Family reminders'),
        ),
      ),
      _familyCard(),
      const SizedBox(height: 20),
      _accountCard(),
      const SizedBox(height: 20),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('How readings appear'),
            const SizedBox(height: 18),
            const Text(
              'Temperature unit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: TemperatureUnit.values
                  .map(
                    (unit) => MotionPress(
                      child: ChoiceChip(
                        label: Text(
                          unit == TemperatureUnit.celsius
                              ? 'Celsius · °C'
                              : 'Fahrenheit · °F',
                        ),
                        selected: c.unit == unit,
                        onSelected: (_) => action(
                          () => c.setUnit(unit),
                          'Your temperature unit is updated.',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Divider(height: 38),
            const Text(
              'Your temperature reference',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 9),
            const Text(
              'A saved check-in at or above this number shows a high temperature alert for that person. The reference is saved on this phone. Confirm any fever concern with a clinical thermometer; a skin reading cannot diagnose or rule out fever. Alerts appear in the app when you save or view records.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: threshold,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Reference temperature',
                suffixText: '°C',
                helperText: 'Enter a value from 30 to 45°C, always in Celsius.',
              ),
            ),
            const SizedBox(height: 18),
            MotionPress(
              child: FilledButton(
                onPressed: () => action(() async {
                  final value = double.tryParse(threshold.text.trim());
                  if (value == null) {
                    throw const FormatException(
                      'Please enter a number in Celsius.',
                    );
                  }
                  await c.setThreshold(value);
                }, 'Your temperature reference is saved.'),
                child: const Text('Save preference'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        color: lavender,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: Color(0xFF716084)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your records stay close.',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              c.cloud != null
                  ? 'Family check-ins save on this phone first, then sync to your family account. Automatic unassigned samples stay on this phone.'
                  : 'Readings are saved on this phone. Sign in to share family check-ins and reminders across your phones.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 14),
            _detail('Saved readings', '${c.records.length}'),
            const SizedBox(height: 10),
            MotionPress(
              child: OutlinedButton.icon(
                onPressed: c.records.isEmpty ? null : _clearRecords,
                icon: const Icon(Icons.delete_outline_rounded, size: 21),
                label: const Text('Clear saved readings'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              c.cloud != null
                  ? 'Clearing deletes your family’s saved readings from your family account too, once connected. Profiles are kept.'
                  : 'This clears this phone’s history. Samples still on the thermometer can sync again.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _measurementNote(),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'ThermoCare',
            applicationVersion: '$productVersion ($productBuild)',
            applicationIcon: const Icon(
              Icons.favorite_rounded,
              color: teal,
              size: 40,
            ),
            applicationLegalese: 'Family care, one check-in at a time.',
          ),
          icon: const Icon(Icons.info_outline_rounded, color: nightMuted),
          label: const Text(
            'About ThermoCare',
            style: TextStyle(color: nightMuted),
          ),
        ),
      ),
    ],
  );

  Future<void> _clearRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle(
        duration: motionTime(context, 280),
        reverseDuration: motionTime(context, 180),
        curve: Curves.easeOutCubic,
      ),
      builder: (context) => AlertDialog(
        title: const Text('Clear these readings?'),
        content: Text(
          c.cloud != null
              ? 'All saved family readings will be deleted on this phone and from your family account when connected. Share a CSV first to keep a copy. Family profiles are kept.'
              : 'Your saved readings on this phone will be deleted. Share a CSV first if you’d like to keep a copy. Samples on the thermometer are not cleared.',
        ),
        actions: [
          MotionPress(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep readings'),
            ),
          ),
          MotionPress(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear readings'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await action(c.clearRecords, 'Your saved readings have been cleared.');
    }
  }
}
