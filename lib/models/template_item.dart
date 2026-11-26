class TemplateItem {
  const TemplateItem({
    required this.id,
    required this.title,
    required this.steps,
    required this.difficulty,
  });

  final String id;
  final String title;
  final int steps;
  final String difficulty;

  String get fullAssetPath => 'assets/templates/$id/full.png';
  String get thumbAssetPath => 'assets/templates/$id/thumb.png';
  List<String> get stepAssetPaths =>
      List.generate(steps, (i) => 'assets/templates/$id/step_${i + 1}.png');

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      id: json['id'] as String,
      title: json['title'] as String,
      steps: json['steps'] as int,
      difficulty: json['difficulty'] as String,
    );
  }
}
