import 'package:go_router/go_router.dart';
import 'package:tracear/features/gallery/gallery_screen.dart';
import 'package:tracear/features/home/home_screen.dart';
import 'package:tracear/features/prepare/prepare_screen.dart';
import 'package:tracear/features/settings/settings_screen.dart';
import 'package:tracear/features/trace/trace_screen.dart';

GoRouter createRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/prepare/:imageId',
        builder: (context, state) {
          final imageId = Uri.decodeComponent(state.pathParameters['imageId']!);
          return PrepareScreen(imageId: imageId);
        },
      ),
      GoRoute(
        path: '/trace/:imageId',
        builder: (context, state) {
          final imageId = Uri.decodeComponent(state.pathParameters['imageId']!);
          return TraceScreen(imageId: imageId);
        },
      ),
      GoRoute(
        path: '/gallery',
        builder: (context, state) => const GalleryScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
