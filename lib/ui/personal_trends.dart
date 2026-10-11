import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../models.dart';
import '../care_models.dart';
import 'care_pages.dart';
import 'chart.dart';
import 'theme.dart';

class PersonalTrends extends StatefulWidget {
  const PersonalTrends({
    super.key,
    required this.controller,
    required this.onReadingTap,
  });
  final MonitorController controller;
  final ValueChanged<Reading> onReadingTap;
  @override
  State<PersonalTrends> createState() => _PersonalTrendsState();
}

class _PersonalTrendsState extends State<PersonalTrends> {
  late String? memberId = widget.controller.selectedMember?.id;
  int days = 7;
  int limit = 20;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final id = c.members.any((m) => m.id == memberId)
          ? memberId
          : c.members.firstOrNull?.id;
      final trend = PersonalTrend(c.records, id ?? '', DateTime.now(), days);
      final rows = trend.readings;
      String temperature(double value) =>
          '${c.unit.format(value)} ${c.unit.symbol}';
      String difference(double value) {
        final converted =
            value * (c.unit == TemperatureUnit.fahrenheit ? 1.8 : 1);
        return '${converted > 0 ? '+' : ''}${converted.toStringAsFixed(1)} ${c.unit.symbol}';
      }

      final daily = trend.dailyAverages;
      return CarePage(
        title: 'Personal trends',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Their story, one check-in at a time.',
              style: TextStyle(
                color: nightText,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              c.store.ownerId == null
                  ? 'Sign in to share saved check-ins and notes across your family’s phones.'
                  : 'From your saved family check-ins. Synced history is available offline; new changes arrive when connected.',
              style: const TextStyle(color: nightMuted),
            ),
            const SizedBox(height: 18),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.members.isEmpty)
                    const Text(
                      'Add a family member and save their first check-in to begin.',
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: c.members
                        .map(
                          (m) => ChoiceChip(
                            label: Text(
                              '${m.name}${m.archived ? ' (archived)' : ''}',
                            ),
                            selected: id == m.id,
                            onSelected: (_) => setState(() {
                              memberId = m.id;
                              limit = 20;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [7, 30, 90]
                        .map(
                          (d) => ChoiceChip(
                            label: Text('$d days'),
                            selected: days == d,
                            onSelected: (_) => setState(() {
                              days = d;
                              limit = 20;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  if (rows.isEmpty)
                    const Text(
                      'No saved check-ins in this period. Start a guided check-in for this person.',
                      style: TextStyle(color: muted),
                    )
                  else ...[
                    Text(
                      '${rows.length} check-ins · ${daily.length} ${daily.length == 1 ? 'day' : 'days'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 14,
                      children: [
                        _stat('Latest', temperature(rows.last.celsius)),
                        _stat('Period average', temperature(trend.average!)),
                        _stat(
                          'First to latest',
                          trend.change == null
                              ? 'Need two check-ins'
                              : difference(trend.change!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Latest: ${DateFormat('MMM d, yyyy · h:mm a').format(rows.last.at.toLocal())}',
                      style: const TextStyle(color: muted),
                    ),
                    Text(
                      '${rows.where((r) => r.quality?.prepared == true).length}/${rows.length} check-ins include preparation and stability details.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Daily surface-temperature averages',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    if (daily.length < 2)
                      Text(
                        'Daily average: ${temperature(daily.single.celsius)}. Save check-ins on another day to see a line.',
                        style: const TextStyle(color: muted),
                      )
                    else
                      TemperatureChart(readings: daily, unit: c.unit),
                    const SizedBox(height: 12),
                    const Text(
                      'Each point averages that day’s saved check-ins. Gaps show time without a check-in; a connecting line does not represent continuous monitoring.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (rows.isNotEmpty)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Check-ins and notes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...rows.reversed
                        .take(limit)
                        .map(
                          (r) => Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                temperature(r.celsius),
                                style: const TextStyle(
                                  color: teal,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat('MMM d, yyyy · h:mm a').format(r.at.toLocal())}'
                                '${r.estimatedTime ? ' · phone-estimated time' : ''}\n${r.note.isEmpty ? 'No note added' : r.note}',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => widget.onReadingTap(r),
                            ),
                          ),
                        ),
                    if (rows.length > limit)
                      TextButton(
                        onPressed: () => setState(() => limit += 20),
                        child: const Text('Show older check-ins'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            const Text(
              'Compare the same skin site and device setup. These are surface temperatures; the trend does not diagnose fever or illness.',
              style: TextStyle(color: nightMuted, height: 1.5),
            ),
          ],
        ),
      );
    },
  );
  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(
          color: teal,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}
