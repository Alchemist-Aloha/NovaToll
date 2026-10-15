import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showSources(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sources & coverage',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            'Nova Toll is an independent Northern Virginia trip planner. Estimates are for a standard paid E-ZPass trip. Posted roadside prices govern.',
          ),
          const SizedBox(height: 12),
          for (final source in const {
            'I-495 / I-95 / I-395 · Express Lanes':
                'https://www.expresslanes.com/map-your-trip',
            'I-66 inside Beltway · VDOT': 'https://vai66tolls.com',
            'I-66 outside Beltway · Ride66Express':
                'https://ride66express.com/pricing/plan-your-trip/',
          }.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(source.key),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                try {
                  if (!await launchUrl(
                    Uri.parse(source.value),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('No browser');
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open the operator website.'),
                      ),
                    );
                  }
                }
              },
            ),
          const Divider(height: 32),
          Text(
            'About estimates',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Outside-Beltway I-66 planner values are described as historical averages; realtime accuracy is unverified. Inside-Beltway responses do not provide a rate timestamp. Fetch time is not proof of a new rate.',
          ),
          const SizedBox(height: 24),
          Text(
            'About the supplied map',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ramp dots are approximately calibrated to the artwork, not surveyed coordinates. Construction, study and Opitz notes are historical artwork, not current road-status information. Verify ramp names and signs.',
          ),
          const SizedBox(height: 24),
          Text(
            'Your location and trips',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Location is requested once and stays on your device. Proximity cannot establish express-lane access or recover your original entry. Saved trips are stored locally, with no account or sync.',
          ),
          const SizedBox(height: 16),
          const Text('Use while parked or have a passenger operate it.'),
        ],
      ),
    ),
  ),
);
