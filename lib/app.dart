import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:tracear/core/theme.dart';
import 'package:tracear/router.dart';

class TraceArApp extends StatefulWidget {
  const TraceArApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  State<TraceArApp> createState() => _TraceArAppState();
}

class _TraceArAppState extends State<TraceArApp> {
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TraceAR',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
