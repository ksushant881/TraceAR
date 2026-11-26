import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracear/features/gallery/gallery_controller.dart';
import 'package:tracear/services/recording_service.dart';
import 'package:video_player/video_player.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(galleryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: galleryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No recordings or result photos yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(galleryControllerProvider.notifier).refresh(),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _GalleryTile(
                  item: item,
                  onTap: () => _openViewer(context, ref, item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openViewer(BuildContext context, WidgetRef ref, RecordingItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MediaViewerPage(
          item: item,
          onDelete: () async {
            await ref
                .read(galleryControllerProvider.notifier)
                .delete(item.path);
          },
        ),
      ),
    );
  }
}

class _GalleryTile extends ConsumerStatefulWidget {
  const _GalleryTile({required this.item, required this.onTap});

  final RecordingItem item;
  final VoidCallback onTap;

  @override
  ConsumerState<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends ConsumerState<_GalleryTile> {
  Future<Uint8List?>? _thumbFuture;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _thumbFuture = ref
          .read(galleryControllerProvider.notifier)
          .thumbnailFor(widget.item.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.item.isVideo)
              FutureBuilder<Uint8List?>(
                future: _thumbFuture,
                builder: (context, snap) {
                  if (snap.hasData && snap.data != null) {
                    return Image.memory(snap.data!, fit: BoxFit.cover);
                  }
                  return const ColoredBox(
                    color: Colors.black26,
                    child: Icon(Icons.videocam_outlined),
                  );
                },
              )
            else
              Image.file(File(widget.item.path), fit: BoxFit.cover),
            if (widget.item.isVideo)
              const Positioned(
                right: 6,
                bottom: 6,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow, size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaViewerPage extends StatefulWidget {
  const _MediaViewerPage({required this.item, required this.onDelete});

  final RecordingItem item;
  final Future<void> Function() onDelete;

  @override
  State<_MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<_MediaViewerPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _videoController = VideoPlayerController.file(File(widget.item.path))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(widget.item.path)]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () async {
              await widget.onDelete();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Center(
        child: widget.item.isVideo
            ? (_videoController != null &&
                      _videoController!.value.isInitialized)
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_videoController!.value.isPlaying) {
                            _videoController!.pause();
                          } else {
                            _videoController!.play();
                          }
                        });
                      },
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : const CircularProgressIndicator()
            : InteractiveViewer(child: Image.file(File(widget.item.path))),
      ),
    );
  }
}
