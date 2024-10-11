/// Result returned from `Muxer.run`.
sealed class MuxerResult {
  const MuxerResult();
}

/// Result returned from `Muxer.run` when there is an error.
final class MuxerError extends MuxerResult implements Exception {
  const MuxerError(this.message);

  /// The error message. The actual **FFmpeg** error message, if any,
  /// is appended internally in `Muxer.run`.
  final String message;

  @override
  String toString() => 'MuxerError: $message';
}

/// Result returned from `Muxer.run` when successful.
final class MuxerOK extends MuxerResult {
  const MuxerOK(this.outputFile);

  /// The path to the output file (same as the `outputFile` argument).
  final String outputFile;
}
