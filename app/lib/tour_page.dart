import 'package:flutter/material.dart';

import 'bridge.dart';
import 'illustrations.dart';
import 'theme.dart';

class _Step {
  const _Step(this.icon, this.title, this.text, this.picture);
  final IconData icon;
  final String title;
  final String text;
  final Widget Function(Bridge bridge)? picture;
}

/// The quick tour: what each part of the widget means, then "add a widget".
class TourPage extends StatefulWidget {
  const TourPage({super.key, required this.bridge, required this.onDone, required this.onAddWidget});

  final Bridge bridge;
  final VoidCallback onDone;
  final VoidCallback onAddWidget;

  @override
  State<TourPage> createState() => _TourPageState();
}

class _TourPageState extends State<TourPage> {
  final _pages = PageController();
  int _at = 0;

  late final List<_Step> _steps = [
    _Step(
      Icons.widgets_outlined,
      'Get to know Sky Strip',
      'The weather right now is on the left side.\n\n'
          'The picture shows the coming hours, one column for every hour.\n\n'
          'Here is what each part means…',
      (b) => WidgetPreview(bridge: b),
    ),
    _Step(Icons.device_thermostat, 'Temperature',
        'The colour shows how warm it is, and the shape of the curve shows how fast it changes',
        (_) => const TemperaturePicture()),
    _Step(Icons.wb_twilight, 'Cloud cover & daylight',
        'The sky colour shows the clouds, and also when the sun rises and sets',
        (_) => const SkyPicture()),
    _Step(Icons.grain, 'Rain & snow', 'Blue dots are rain, white dots are snow',
        (_) => const RainPicture()),
    _Step(Icons.air, 'Wind',
        'More arrows mean stronger wind, from 1 to 12 on the Beaufort scale',
        (_) => const WindPicture()),
    const _Step(Icons.add_circle_outline, 'Let’s get started!',
        'Touch and hold an empty spot on your home screen to add a widget, or use the button '
            'below.\n\nYou can add several widgets, each one for a different place.',
        null),
  ];

  bool get _last => _at == _steps.length - 1;

  void _go(int i) =>
      _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: IconButton(
                onPressed: widget.onDone,
                icon: Icon(Icons.close, size: 24, color: c.outline),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _at = i),
              itemBuilder: (context, i) => _page(context, _steps[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: Row(children: [
              for (var i = 0; i < _steps.length; i++)
                Expanded(
                  child: IconButton(
                    onPressed: () => _go(i),
                    icon: Icon(_steps[i].icon,
                        size: 24, color: i == _at ? c.primary : c.outline.withValues(alpha: 0.6)),
                  ),
                ),
              const SizedBox(width: 8),
              _last
                  ? OutlinedButton(
                      onPressed: widget.onDone,
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        fixedSize: const Size(42, 42),
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: c.text, width: 1.5),
                      ),
                      child: Icon(Icons.check, color: c.text),
                    )
                  : FilledButton(
                      onPressed: () => _go(_at + 1),
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        fixedSize: const Size(42, 42),
                        padding: EdgeInsets.zero,
                        backgroundColor: c.primary,
                      ),
                      child: Icon(Icons.chevron_right, size: 28, color: c.onPrimary),
                    ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _page(BuildContext context, _Step step) {
    final c = AppColors.of(context);
    final picture = step.picture;
    return LayoutBuilder(builder: (context, box) {
      // Pictures sit at the same height on every page; titles stand right above them.
      final pictureTop = (box.maxHeight * 0.25).clamp(140.0, 240.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: picture == null ? pictureTop + 60 : pictureTop,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(step.title, style: outfit(38, weight: 700, color: c.text, height: 1.15)),
              ),
            ),
          ),
          if (picture != null) PictureCard(child: picture(widget.bridge)),
          SizedBox(height: picture == null ? 8 : 32),
          Text(step.text, style: outfit(16, weight: 400, color: c.text, height: 1.5)),
          if (picture == null) ...[
            const SizedBox(height: 40),
            BigButton(icon: Icons.widgets_outlined, label: 'Add Widget', onPressed: widget.onAddWidget),
          ],
        ]),
      );
    });
  }
}

/// The large rounded buttons of the home screen.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 72,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
        ),
        child: Row(children: [
          Icon(icon, size: 24, color: c.onPrimary),
          const SizedBox(width: 14),
          Text(label, style: outfit(23, weight: 600, color: c.onPrimary)),
        ]),
      ),
    );
  }
}
