import 'package:flutter/material.dart';

import 'bridge.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'tour_page.dart';

const appVersion = '1.0.0';

/// Credit line for the forecast data (required by the data provider's licence).
const forecastCredit = 'Forecasts by Open-Meteo.com (CC BY 4.0).';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.bridge, required this.onTour, required this.onShare});

  final Bridge bridge;
  final VoidCallback onTour;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Sky\nStrip', style: outfit(56, weight: 700, color: c.text, height: 1.1)),
            const SizedBox(height: 32),
            BigButton(
              icon: Icons.widgets_outlined,
              label: 'Add Widget',
              onPressed: () => addWidget(context, bridge),
            ),
            const SizedBox(height: 40),
            _Item(icon: Icons.outlined_flag, label: 'Quick Tour', onTap: onTour),
            _Item(icon: Icons.volunteer_activism_outlined, label: 'Recommend to Friends', onTap: onShare),
            const Spacer(),
            Text('Version $appVersion', style: outfit(13, color: c.text)),
            const SizedBox(height: 2),
            Text(forecastCredit, style: outfit(13, color: c.text)),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage())),
              child: Text('Privacy policy',
                  style: outfit(13, color: c.text).copyWith(decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Settings first, then the launcher's "add to home screen" dialog.
Future<void> addWidget(BuildContext context, Bridge bridge) async {
  if (!await bridge.canPin()) {
    if (!context.mounted) return;
    final c = AppColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Can't add widget automatically", style: outfit(22, weight: 600, color: c.text)),
        content: Text(
          'Your home screen can\'t add it from here. Touch and hold an empty spot on your home '
          'screen, tap Widgets, then find Sky Strip.',
          style: outfit(15, color: c.text, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Dismiss')),
        ],
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final s = await showWidgetSettings(
    context,
    bridge: bridge,
    initial: defaultSettings(Localizations.localeOf(context)),
    isNew: true,
  );
  if (s != null) await bridge.pin(s);
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 24, color: c.text),
          const SizedBox(width: 16),
          Text(label, style: outfit(17, weight: 400, color: c.text)),
        ]),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = outfit(16, color: c.text, height: 1.45);
    return Scaffold(
      appBar: AppBar(title: Text('Privacy policy', style: outfit(20, weight: 600, color: c.text))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          'This app has no account, no ads and no tracking.\n\n'
          'To show the forecast, the place you type, or your phone\'s location when you choose '
          'Automatic, is sent to the weather and place search services named on the home screen. '
          'Nothing else leaves your phone.\n\n'
          'With Automatic and "Allow all the time", the widget reads your location in the '
          'background about every 45 minutes, only to update the forecast. Switch the widget to '
          'Manual, or remove the permission in your phone settings, to stop this.',
          style: body,
        ),
      ]),
    );
  }
}
