import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'theme.dart';

class TemperatureAlertNotice extends StatelessWidget {
  const TemperatureAlertNotice({
    super.key,
    required this.reading,
    required this.person,
    required this.threshold,
    required this.unit,
    this.showTitle = true,
  });
  final Reading reading;
  final String person;
  final double threshold;
  final TemperatureUnit unit;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'High temperature alert',
                  style: TextStyle(
                    color: amber,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          '$person: ${unit.format(reading.celsius)} ${unit.symbol}',
          style: const TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Reading taken ${DateFormat('MMM d, yyyy · h:mm a').format(reading.at.toLocal())}',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Text(
          'This skin reading reached your ${unit.format(threshold)} ${unit.symbol} alert reference. Check with a clinical thermometer if you are concerned about fever.',
          style: const TextStyle(color: ink, height: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          'Skin temperature alone cannot confirm or rule out fever.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );
}
