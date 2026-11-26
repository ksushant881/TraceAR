import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:tracear/models/template_item.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/providers/app_providers.dart';

class HomeState {
  const HomeState({
    this.recent = const [],
    this.templates = const [],
    this.isImporting = false,
    this.errorMessage,
  });

  final List<TraceImage> recent;
  final List<TemplateItem> templates;
  final bool isImporting;
  final String? errorMessage;

  HomeState copyWith({
    List<TraceImage>? recent,
    List<TemplateItem>? templates,
    bool? isImporting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      recent: recent ?? this.recent,
      templates: templates ?? this.templates,
      isImporting: isImporting ?? this.isImporting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class HomeController extends AsyncNotifier<HomeState> {
  final _picker = picker.ImagePicker();

  @override
  Future<HomeState> build() async {
    final library = ref.read(imageLibraryServiceProvider);
    final recent = await library.listRecent();
    List<TemplateItem> templates = const [];
    try {
      templates = await library.loadTemplates();
    } catch (_) {
      templates = const [];
    }
    return HomeState(recent: recent, templates: templates);
  }

  Future<void> refresh() async {
    final library = ref.read(imageLibraryServiceProvider);
    final recent = await library.listRecent();
    final current = state.value ?? const HomeState();
    state = AsyncData(current.copyWith(recent: recent, clearError: true));
  }

  Future<TraceImage?> pickAndImport(picker.ImageSource source) async {
    final current = state.value ?? const HomeState();
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) return null;

      state = AsyncData(current.copyWith(isImporting: true, clearError: true));
      final imported = await ref
          .read(imageLibraryServiceProvider)
          .importImage(picked.path);
      final recent = await ref.read(imageLibraryServiceProvider).listRecent();
      state = AsyncData(current.copyWith(recent: recent, isImporting: false));
      return imported;
    } catch (e) {
      state = AsyncData(
        current.copyWith(
          isImporting: false,
          errorMessage: 'Could not import image: $e',
        ),
      );
      return null;
    }
  }

  Future<void> deleteImage(String imageId) async {
    await ref.read(imageLibraryServiceProvider).deleteImage(imageId);
    await refresh();
  }
}

final homeControllerProvider = AsyncNotifierProvider<HomeController, HomeState>(
  HomeController.new,
);
