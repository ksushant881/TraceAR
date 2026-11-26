class StepSet {
  const StepSet({
    required this.imageId,
    required this.paramsHash,
    required this.stepPaths,
    this.isAsset = false,
  });

  final String imageId;
  final String paramsHash;
  final List<String> stepPaths;
  final bool isAsset;

  StepSet copyWith({
    String? imageId,
    String? paramsHash,
    List<String>? stepPaths,
    bool? isAsset,
  }) {
    return StepSet(
      imageId: imageId ?? this.imageId,
      paramsHash: paramsHash ?? this.paramsHash,
      stepPaths: stepPaths ?? this.stepPaths,
      isAsset: isAsset ?? this.isAsset,
    );
  }
}
