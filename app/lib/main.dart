import 'package:flutter/material.dart';

import 'bridge.dart';
import 'home_page.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'tour_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WeatherWidgetApp(bridge: Bridge()));
}

class WeatherWidgetApp extends StatefulWidget {
  const WeatherWidgetApp({super.key, required this.bridge});

  final Bridge bridge;

  @override
  State<WeatherWidgetApp> createState() => _WeatherWidgetAppState();
}

class _WeatherWidgetAppState extends State<WeatherWidgetApp> {
  final _nav = GlobalKey<NavigatorState>();
  bool? _tourSeen;

  Bridge get bridge => widget.bridge;

  @override
  void initState() {
    super.initState();
    bridge.onOpenWidget = (id) => _editWidget(id, configure: false);
    _start();
  }

  Future<void> _start() async {
    final seen = await bridge.flag('tour_seen');
    final launch = await bridge.launch();
    setState(() => _tourSeen = seen || launch.widgetId != null);
    final id = launch.widgetId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _editWidget(id, configure: launch.mode == 'configure'));
    }
  }

  /// Settings for one placed widget. From the launcher ("configure") the widget is only added on OK.
  Future<void> _editWidget(int id, {required bool configure}) async {
    final context = _nav.currentContext;
    if (context == null) return;
    final current = await bridge.settings(id);
    if (!context.mounted) return;
    final s = await showWidgetSettings(
      context,
      bridge: bridge,
      initial: current ?? defaultSettings(Localizations.localeOf(context)),
      isNew: current == null,
    );
    if (s != null) await bridge.save(id, s);
    if (configure) await bridge.finishConfigure(id, ok: s != null);
  }

  Future<void> _finishTour() async {
    await bridge.setFlag('tour_seen', true);
    if (_tourSeen == false) {
      setState(() => _tourSeen = true);
    } else {
      _nav.currentState?.maybePop();
    }
  }

  void _openTour() {
    _nav.currentState?.push(MaterialPageRoute(
      builder: (context) => TourPage(
        bridge: bridge,
        onDone: _finishTour,
        onAddWidget: () => addWidget(context, bridge),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final seen = _tourSeen;
    return MaterialApp(
      title: 'Sky Strip',
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: seen == null
          ? const Scaffold()
          : seen
              ? HomePage(bridge: bridge, onTour: _openTour, onShare: bridge.share)
              : Builder(
                  builder: (context) => TourPage(
                    bridge: bridge,
                    onDone: _finishTour,
                    onAddWidget: () => addWidget(context, bridge),
                  ),
                ),
    );
  }
}
