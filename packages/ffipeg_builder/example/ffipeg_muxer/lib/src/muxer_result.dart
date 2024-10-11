sealed class MuxerResult {
  const MuxerResult();
}

final class MuxerError extends MuxerResult implements Exception {
  const MuxerError(this.message);

  final String message;

  @override
  String toString() => 'MuxerError: $message';
}

final class MuxerOK extends MuxerResult {
  const MuxerOK(this.outputFile);

  final String outputFile;
}
