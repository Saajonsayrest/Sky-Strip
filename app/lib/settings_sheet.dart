import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge.dart';
import 'open_meteo.dart';
import 'place.dart';
import 'theme.dart';

enum _Section { range, temperature, location }

/// "Widget Settings" bottom sheet. Returns the chosen settings on OK, null on Cancel.
Future<WidgetSettings?> showWidgetSettings(
  BuildContext context, {
  required Bridge bridge,
  required WidgetSettings initial,
  bool isNew = false,
}) {
  return showModalBottomSheet<WidgetSettings>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SettingsSheet(bridge: bridge, initial: initial, isNew: isNew),
  );
}

/// Default for a new widget: medium span, °F in the US and a few others, manual place.
WidgetSettings defaultSettings(Locale locale) {
  const fahrenheitCountries = {'US', 'LR', 'MM', 'BS', 'BZ', 'KY', 'PW', 'FM', 'MH'};
  return WidgetSettings(fahrenheit: fahrenheitCountries.contains(locale.countryCode));
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.bridge, required this.initial, required this.isNew});

  final Bridge bridge;
  final WidgetSettings initial;
  final bool isNew;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late WidgetSettings s = widget.initial;
  late _Section? open = s.complete ? null : _Section.location;
  LocationAccess access = LocationAccess.none;

  /// Automatic place: the user read the background-location notice.
  bool understood = false;

  @override
  void initState() {
    super.initState();
    _readAccess();
    widget.bridge.onResumed = _readAccess;
  }

  @override
  void dispose() {
    widget.bridge.onResumed = null;
    super.dispose();
  }

  Future<void> _readAccess() async {
    final a = await widget.bridge.locationAccess();
    if (mounted) setState(() => access = a);
  }

  bool get _ready =>
      s.mode == LocationMode.manual ? s.place != null : access != LocationAccess.none;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Widget Settings',
                textAlign: TextAlign.center, style: outfit(22, weight: 600, color: c.text)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(children: [
                _section(_Section.range, Icons.calendar_month_outlined, 'Forecast Range',
                    s.span.name, _rangeBody(c)),
                const SizedBox(height: 2),
                _section(_Section.temperature, Icons.thermostat, 'Temperature',
                    s.fahrenheit ? '°F' : '°C', _temperatureBody(c)),
                const SizedBox(height: 2),
                _section(_Section.location, Icons.location_on_outlined, 'Location',
                    _locationSummary(), _locationBody(c)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: outfit(16, weight: 500, color: c.primary)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  disabledBackgroundColor: c.chip,
                  minimumSize: const Size(68, 40),
                ),
                onPressed: _ready ? () => Navigator.pop(context, s) : null,
                child: Text('OK',
                    style: outfit(16, weight: 500, color: _ready ? c.onPrimary : c.outline)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String? _locationSummary() {
    if (s.mode == LocationMode.automatic) {
      return access == LocationAccess.none ? 'Setup incomplete' : 'Automatic';
    }
    return s.place?.name ?? 'Setup incomplete';
  }

  Widget _section(_Section id, IconData icon, String title, String? value, Widget body) {
    final c = AppColors.of(context);
    final expanded = open == id;
    return Material(
      color: c.card,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => open = expanded ? null : id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              Icon(icon, size: 24, color: c.text),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: outfit(16.5, weight: 600, color: c.text)),
                  if (!expanded && value != null)
                    Text(value, style: outfit(14.5, weight: 400, color: c.muted)),
                ]),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
                child: Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 24, color: c.text),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(children: [
                  Divider(height: 1, thickness: 1, color: c.sheet),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 20), child: body),
                ])
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _segments<T>(List<(T, String, IconData?)> items, T value, ValueChanged<T> onPick) {
    return SegmentedButton<T>(
      // A tick only on text-only choices; Automatic/Manual keep their own icons.
      showSelectedIcon: items.every((e) => e.$3 == null),
      style: SegmentedButton.styleFrom(
        textStyle: outfit(15, weight: 400),
        minimumSize: const Size.fromHeight(40),
      ),
      segments: [
        for (final (v, label, icon) in items)
          ButtonSegment(value: v, label: Text(label), icon: icon == null ? null : Icon(icon)),
      ],
      selected: {value},
      onSelectionChanged: (set) => onPick(set.first),
    );
  }

  Widget _rangeBody(AppColors c) => Column(children: [
        SizedBox(
          width: double.infinity,
          child: _segments<Span>([
            (Span.short, 'short', null),
            (Span.medium, 'medium', null),
            (Span.long, 'long', null),
          ], s.span, (v) => setState(() => s = s.copyWith(span: v))),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 24, color: c.text),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Tip: tapping the picture on the widget also switches the range.',
                style: outfit(13, color: c.text)),
          ),
        ]),
      ]);

  Widget _temperatureBody(AppColors c) {
    final other = s.fahrenheit ? '°C' : '°F';
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: _segments<bool>([(false, '°C', null), (true, '°F', null)], s.fahrenheit,
            (v) => setState(() => s = s.copyWith(fahrenheit: v))),
      ),
      const SizedBox(height: 8),
      _switchRow(c, Icons.waves, 'Feels-like temperature', s.feelsLike,
          (v) => setState(() => s = s.copyWith(feelsLike: v))),
      _switchRow(c, Icons.add, 'Also show $other', s.alsoOtherUnit,
          (v) => setState(() => s = s.copyWith(alsoOtherUnit: v))),
    ]);
  }

  Widget _switchRow(AppColors c, IconData icon, String label, bool value, ValueChanged<bool> on) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 22, color: c.text),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: outfit(14, color: c.text))),
        Switch(value: value, onChanged: on),
      ]),
    );
  }

  Widget _locationBody(AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _segments<LocationMode>([
        (LocationMode.automatic, 'Automatic', Icons.my_location),
        (LocationMode.manual, 'Manual', Icons.push_pin_outlined),
      ], s.mode, (v) => setState(() => s = s.copyWith(mode: v))),
      const SizedBox(height: 16),
      if (s.mode == LocationMode.manual)
        _PlaceField(
          picked: s.place,
          onPick: (p) => setState(() => s = s.copyWith(place: p)),
        )
      else
        _automaticBody(c),
    ]);
  }

  Widget _automaticBody(AppColors c) {
    final body = outfit(15, color: c.text, height: 1.4);
    if (access == LocationAccess.background) {
      return Text('The widget follows your location, even when the app is closed.', style: body);
    }
    if (access == LocationAccess.foreground || understood && access != LocationAccess.none) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Enable Location Access', style: outfit(16, weight: 600, color: c.text)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(style: body, children: [
            const TextSpan(text: 'For the forecast to follow you, set location access to '),
            TextSpan(text: '"Allow all the time"', style: body.copyWith(fontVariations: const [
              FontVariation('wght', 700),
            ], fontWeight: FontWeight.w700)),
            const TextSpan(text: '.'),
          ]),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => setState(() => s = s.copyWith(mode: LocationMode.manual)),
            child: Text('No thanks', style: outfit(15, weight: 500, color: c.primary)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              final a = await widget.bridge.requestBackgroundLocation();
              if (mounted) setState(() => access = a);
            },
            child: Text('OK', style: outfit(15, weight: 500, color: c.onPrimary)),
          ),
        ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'With this setting, the app uses your phone\'s location in the background, so the '
        'widget always shows the forecast where you are.',
        style: body,
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () async {
            setState(() => understood = true);
            final a = await widget.bridge.requestLocation();
            if (!mounted) return;
            setState(() => access = a);
            if (a == LocationAccess.foreground) {
              // Straight on to "Allow all the time", like the original.
              final b = await widget.bridge.requestBackgroundLocation();
              if (mounted) setState(() => access = b);
            }
          },
          child: Text('I understand', style: outfit(15, weight: 500, color: c.onPrimary)),
        ),
      ),
    ]);
  }
}

/// "Search Location" field with results under it.
class _PlaceField extends StatefulWidget {
  const _PlaceField({required this.picked, required this.onPick});

  final Place? picked;
  final ValueChanged<Place> onPick;

  @override
  State<_PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<_PlaceField> {
  final _api = PlaceSearch();
  late final _text = TextEditingController(text: widget.picked?.name ?? '');
  Timer? _wait;
  List<Place> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _wait?.cancel();
    if (v.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _wait = Timer(const Duration(milliseconds: 350), () => _search(v.trim()));
  }

  Future<void> _search(String v) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await _api.search(v);
      if (mounted && _text.text.trim() == v) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search did not work. Check your internet.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _text,
        onChanged: _changed,
        style: outfit(18, color: c.text),
        decoration: InputDecoration(
          hintText: 'Search Location',
          hintStyle: outfit(18, color: c.muted),
          prefixIcon: Icon(Icons.search, color: c.text),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: outfit(13, color: Theme.of(context).colorScheme.error)),
        ),
      for (final p in _results)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.location_on_outlined, color: c.muted),
          title: Text(p.name, style: outfit(16, weight: 500, color: c.text)),
          subtitle: p.region.isEmpty ? null : Text(p.region, style: outfit(13, color: c.muted)),
          onTap: () {
            FocusScope.of(context).unfocus();
            _text.text = p.name;
            setState(() => _results = const []);
            widget.onPick(p);
          },
        ),
    ]);
  }
}
