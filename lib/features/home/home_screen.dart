import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:tracear/features/home/home_controller.dart';
import 'package:tracear/models/template_item.dart';
import 'package:tracear/models/trace_image.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(homeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TraceAR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Gallery',
            onPressed: () => context.push('/gallery'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: homeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (home) => Stack(
          children: [
            RefreshIndicator(
              onRefresh: () =>
                  ref.read(homeControllerProvider.notifier).refresh(),
              child: CustomScrollView(
                slivers: [
                  if (home.errorMessage != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: MaterialBanner(
                          content: Text(home.errorMessage!),
                          actions: [
                            TextButton(
                              onPressed: () => ref
                                  .read(homeControllerProvider.notifier)
                                  .refresh(),
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _handleImport(
                                context,
                                ref,
                                picker.ImageSource.gallery,
                              ),
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text('Pick image'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _handleImport(
                                context,
                                ref,
                                picker.ImageSource.camera,
                              ),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Take photo'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (home.templates.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'Templates',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 156,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: home.templates.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = home.templates[index];
                            return _TemplateCard(
                              item: item,
                              onTap: () =>
                                  context.push('/prepare/template:${item.id}'),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (home.recent.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No recent photos yet.\nPick an image or choose a template above to start tracing.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final img = home.recent[index];
                          return _RecentTile(
                            image: img,
                            onTap: () async {
                              await context.push('/prepare/${img.id}');
                              if (context.mounted) {
                                ref
                                    .read(homeControllerProvider.notifier)
                                    .refresh();
                              }
                            },
                            onLongPress: () =>
                                _confirmDelete(context, ref, img),
                          );
                        }, childCount: home.recent.length),
                      ),
                    ),
                ],
              ),
            ),
            if (home.isImporting)
              const ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImport(
    BuildContext context,
    WidgetRef ref,
    picker.ImageSource source,
  ) async {
    final imported = await ref
        .read(homeControllerProvider.notifier)
        .pickAndImport(source);
    if (imported != null && context.mounted) {
      await context.push('/prepare/${imported.id}');
      if (context.mounted) {
        ref.read(homeControllerProvider.notifier).refresh();
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TraceImage image,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text(
          'This removes the image, its generated line art, and its saved session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(homeControllerProvider.notifier).deleteImage(image.id);
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.item, required this.onTap});

  final TemplateItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(item.thumbAssetPath, fit: BoxFit.contain),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${item.steps} steps • ${item.difficulty}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.image,
    required this.onTap,
    required this.onLongPress,
  });

  final TraceImage image;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Recent image, long press to delete',
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(image.originalPath),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Colors.black26,
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }
}
