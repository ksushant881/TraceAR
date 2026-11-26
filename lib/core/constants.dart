class AppConstants {
  AppConstants._();

  static const String nativeChannelName = 'com.sushant.tracear/native';
  static const String timelapseProgressChannelName =
      'com.sushant.tracear/native/timelapse_progress';

  static const String imagesDirName = 'images';
  static const String sessionsDirName = 'sessions';
  static const String recordingsDirName = 'recordings';
  static const String imageIndexFileName = 'index.json';
  static const String galleryAlbumName = 'TraceAR';

  static const int maxImportDimension = 2048;
  static const int maxLineArtDimension = 1024;

  /// Bump when the line-art / step algorithm changes so cached results made
  /// by an older version are regenerated instead of reused.
  static const int lineArtAlgorithmVersion = 2;
  static const String lineArtFileName = 'lineart_v$lineArtAlgorithmVersion.png';

  static const double minTouchTarget = 48.0;
}
