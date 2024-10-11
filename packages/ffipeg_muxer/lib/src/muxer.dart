@FFmpegGen(
  versionSpec: '>=7.1 <8.0',
  excludeAllByDefault: true,
  functions: FFInclude(functions),
  structs: FFInclude({'AVFormatContext', 'AVIOContext', 'AVPacket'}),
  enums: FFInclude({'AVMediaType'}),
  macros: FFInclude({'AVIO_FLAG_WRITE', 'AV_NOPTS_VALUE', 'AV_LOG_.*'}),
)
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ffipeg/ffipeg.dart';
import 'package:ffipeg_muxer/src/muxer_result.dart';
import 'package:logging/logging.dart';

import 'muxer.ffipeg.dart';

const functions = <String>{
  'av_compare_ts',
  'av_version_info',
  'av_interleaved_write_frame',
  'av_log_set_level',
  'av_packet_alloc',
  'av_packet_free',
  'av_packet_rescale_ts',
  'av_read_frame',
  'av_strerror',
  'av_write_trailer',
  'avcodec_parameters_copy',
  'avformat_alloc_output_context2',
  'avformat_close_input',
  'avformat_configuration',
  'avformat_find_stream_info',
  'avformat_free_context',
  'avformat_new_stream',
  'avformat_open_input',
  'avformat_write_header',
  'avio_close',
  'avio_open',
};

/// Convenience wrapper for media packet info coupled with its
/// context and streams, to avoid passing them around separately.
class MediaPacket {
  /// The media type of the packet.
  final AVMediaType mediaType;

  /// The input context for the packet.
  final Pointer<Pointer<AVFormatContext>> inputCtx;

  /// The packet itself.
  final Pointer<AVPacket> pkt;

  /// The input stream for the packet.
  final Pointer<AVStream> inputStream;

  /// The output stream for the packet.
  final Pointer<AVStream> outputStream;

  /// The scaled presentation timestamp (PTS) in seconds.
  double get scaledPts =>
      pkt.ref.pts.toDouble() *
      outputStream.ref.time_base.num /
      outputStream.ref.time_base.den;

  const MediaPacket({
    required this.mediaType,
    required this.inputCtx,
    required this.pkt,
    required this.inputStream,
    required this.outputStream,
  });
}

/// Provides a `description` for an `AVMediaType`.
extension AVMediaTypeDescription on AVMediaType {
  /// Get the stream description in lowercase, i.e. 'audio' or 'video'
  String get description => name.split('_').last.toLowerCase();
}

/// Main muxing class that uses generated Dart FFI bindings to FFmpeg's C API
/// to mux audio and video files.
///
/// Instantiate with a `DynamicLibrary` pointing to an FFmpeg 7.1:
///   - shared library (e.g. libffmpeg.7.dylib), or
///   - executable.
/// Optionally pass a `logger` to control the log level/output.
/// Then invoke `run` on the instance with the appropriate arguments.
///
/// Can be instantiated and run in a Dart isolate to run
/// asynchronously in the background.
///
/// For FFmpeg examples in C, refer to:
/// https://github.com/FFmpeg/FFmpeg/tree/master/doc/examples
/// e.g. mux.c and remux.c
class Muxer {
  Muxer(DynamicLibrary dylib, {Logger? logger}) {
    for (final function in functions) {
      if (!dylib.providesSymbol(function)) {
        throw MuxerError(
            'Invalid FFmpeg library provided: missing function: $function');
      }
    }
    _ffmpeg = FFmpeg(dylib);
    _log = logger ?? Logger.root;
  }

  late final FFmpeg _ffmpeg;
  late final Logger _log;

  /// Retrieve the instantiated FFmpeg version, e.g. "7.1".
  String getFFmpegVersion() {
    final Pointer<Utf8> versionPtr = _ffmpeg.av_version_info().cast();
    return versionPtr.toDartString();
  }

  /// Retrieve the FFmpeg configuration that it was built with.
  String getFFmpegConfig() {
    final Pointer<Utf8> configPtr =
        _ffmpeg.avformat_configuration().cast<Utf8>();
    return configPtr.toDartString();
  }

  /// Muxes a video and audio file into a single output file.
  /// This function is synchronous and blocking.
  ///
  /// Returns `MuxerOK` if successful, or `MuxerError` if an error occurs.
  ///
  /// FFmpeg logs will be written **to stdout** based on `logger.level`
  /// (capturing FFmpeg log output using FFI is non-trivial).
  ///
  /// Can be run in a Dart isolate in the background.
  MuxerResult run({
    /// The video input file to be muxed.
    required String videoFile,

    /// The audio input file to be muxed.
    required String audioFile,

    /// The muxed output file.
    required String outputFile,

    /// Optional format (overrides auto-detection using filename).
    String? format,

    /// If the file exists and `overwrite` == `false`, returns an error.
    bool overwrite = false,
  }) {
    if (File(outputFile).existsSync() && !overwrite) {
      return _error('Output file $outputFile already exists.');
    }

    _ffmpeg.av_log_set_level(_avLogLevel(_log.level));

    // Allocate pointers
    _log.finer('Allocating pointers...');
    final audioPktPtr = _allocPacket();
    if (audioPktPtr == null) {
      return _error('Failed to allocate audio packet');
    }
    final videoPktPtr = _allocPacket();
    if (videoPktPtr == null) {
      _ffmpeg.av_packet_free(audioPktPtr);
      return _error('Failed to allocate video packet');
    }
    final videoInputCtx = calloc<Pointer<AVFormatContext>>();
    final audioInputCtx = calloc<Pointer<AVFormatContext>>();
    final outputCtx = calloc<Pointer<AVFormatContext>>();
    final avioCtx = calloc<Pointer<AVIOContext>>();

    // Convert Dart strings to native UTF-8 strings
    final videoFileNative = videoFile.toNativeUtf8();
    final audioFileNative = audioFile.toNativeUtf8();
    final outputFileNative = outputFile.toNativeUtf8();
    final formatNative = format?.toNativeUtf8() ?? nullptr;

    try {
      // Step 1 & 2: Open video and audio input files
      final videoInputStream = _openInputFile(
          videoFile, videoInputCtx, AVMediaType.AVMEDIA_TYPE_VIDEO);
      final audioInputStream = _openInputFile(
          audioFile, audioInputCtx, AVMediaType.AVMEDIA_TYPE_AUDIO);

      // Step 3: Allocate output context
      int errorCode = _ffmpeg.avformat_alloc_output_context2(
          outputCtx, nullptr, formatNative.cast(), outputFileNative.cast());
      if (errorCode < 0) {
        throw _error('Failed to allocate output context', errorCode: errorCode);
      }
      _log.fine('Allocated output context.');

      // Steps 4 & 5: Add video and audio streams to the output context
      final videoOutputStream = _addStreamToOutputContext(
          outputCtx: outputCtx,
          inputStream: videoInputStream,
          streamType: AVMediaType.AVMEDIA_TYPE_VIDEO);
      final audioOutputStream = _addStreamToOutputContext(
          outputCtx: outputCtx,
          inputStream: audioInputStream,
          streamType: AVMediaType.AVMEDIA_TYPE_AUDIO);

      final videoPacket = MediaPacket(
        mediaType: AVMediaType.AVMEDIA_TYPE_VIDEO,
        inputCtx: videoInputCtx,
        pkt: videoPktPtr.value,
        inputStream: videoInputStream,
        outputStream: videoOutputStream,
      );

      final audioPacket = MediaPacket(
        mediaType: AVMediaType.AVMEDIA_TYPE_AUDIO,
        inputCtx: audioInputCtx,
        pkt: audioPktPtr.value,
        inputStream: audioInputStream,
        outputStream: audioOutputStream,
      );

      // Step 6: Open output file
      _log.fine('Opening output file: $outputFile...');
      errorCode =
          _ffmpeg.avio_open(avioCtx, outputFileNative.cast(), AVIO_FLAG_WRITE);
      if (errorCode < 0) {
        throw _error('Failed to open output file: $outputFile',
            errorCode: errorCode);
      }
      _log.info('Opened output file: $outputFile');

      // Step 7: Assign the AVIO context to the output format context
      outputCtx.value.ref.pb = avioCtx.value;
      _log.finer('Assigned AVIO context to output context.');

      // Step 8: Write the file header
      errorCode = _ffmpeg.avformat_write_header(outputCtx.value, nullptr);
      if (errorCode < 0) {
        throw _error('Failed to write header', errorCode: errorCode);
      }
      _log.fine('Wrote header.');

      // Step 9: Mux streams
      _muxStreams(
          outputCtx: outputCtx,
          videoPacket: videoPacket,
          audioPacket: audioPacket);

      // Step 10: Write trailer to close the file
      errorCode = _ffmpeg.av_write_trailer(outputCtx.value);
      if (errorCode < 0) {
        throw _error('Failed to write trailer', errorCode: errorCode);
      }
      _log.fine('Wrote trailer.');

      return MuxerOK(outputFile);
    } on MuxerError catch (e) {
      return e;
    } finally {
      // Clean up

      if (avioCtx.value != nullptr) {
        _ffmpeg.avio_close(avioCtx.value);
        _log.info('Output file $outputFile closed.');
      }

      _ffmpeg
        ..avformat_close_input(videoInputCtx)
        ..avformat_close_input(audioInputCtx)
        ..av_packet_free(audioPktPtr)
        ..av_packet_free(videoPktPtr)
        ..avformat_free_context(outputCtx.value);

      _freeAll([
        videoInputCtx,
        audioInputCtx,
        outputCtx,
        avioCtx,
        audioPktPtr,
        videoPktPtr,
        videoFileNative,
        audioFileNative,
        outputFileNative,
        formatNative,
      ]);

      _log.info('Resources freed.');
    }
  }

  MuxerError _error(String message, {int? errorCode}) {
    final List<String> errorList = [message];

    if (errorCode != null) {
      const int errbufSize = 1024;
      final errbuf = calloc<Char>(errbufSize);
      try {
        // Fetch FFmpeg error description
        final result = _ffmpeg.av_strerror(errorCode, errbuf, errbufSize);
        if (result == 0) {
          errorList.add(errbuf.cast<Utf8>().toDartString());
        } else {
          errorList.add('Unable to retrieve error description from FFmpeg');
        }
      } finally {
        calloc.free(errbuf);
      }
    }
    final errorMessage = errorList.join(': ');
    _log.severe(errorMessage);
    return MuxerError(errorMessage);
  }

  int _avLogLevel(Level level) => switch (level) {
        Level.ALL => AV_LOG_TRACE,
        Level.FINEST => AV_LOG_TRACE,
        Level.FINER => AV_LOG_DEBUG,
        Level.FINE => AV_LOG_VERBOSE,
        Level.CONFIG => AV_LOG_VERBOSE,
        Level.INFO => AV_LOG_INFO,
        Level.WARNING => AV_LOG_WARNING,
        Level.SEVERE => AV_LOG_ERROR,
        Level.SHOUT => AV_LOG_FATAL,
        Level.OFF => AV_LOG_QUIET,
        _ => AV_LOG_QUIET,
      };

  Pointer<Pointer<AVPacket>>? _allocPacket() {
    final pktPtr = calloc<Pointer<AVPacket>>();
    final pkt = _ffmpeg.av_packet_alloc();
    if (pkt == nullptr) {
      calloc.free(pktPtr);
      return null;
    }
    pktPtr.value = pkt;
    return pktPtr;
  }

  Pointer<AVStream> _openInputFile(
    String filePath,
    Pointer<Pointer<AVFormatContext>> inputCtx,
    AVMediaType streamType,
  ) {
    final description = streamType.description;
    _log.fine('Opening $description file: $filePath...');
    final fileNative = filePath.toNativeUtf8();
    try {
      int errorCode = _ffmpeg.avformat_open_input(
          inputCtx, fileNative.cast(), nullptr, nullptr);
      if (errorCode != 0) {
        throw _error('Failed to open $description file: $filePath',
            errorCode: errorCode);
      }
      _log.info('Opened $description file: $filePath');

      errorCode = _ffmpeg.avformat_find_stream_info(inputCtx.value, nullptr);
      if (errorCode < 0) {
        throw _error('Failed to find $description stream info',
            errorCode: errorCode);
      }
      _log.fine('Found $description stream info.');

      Pointer<AVStream> inputStream = nullptr;
      for (int i = 0; i < inputCtx.value.ref.nb_streams; i++) {
        if (inputCtx.value.ref.streams[i].ref.codecpar.ref.codec_type ==
            streamType) {
          inputStream = inputCtx.value.ref.streams[i];
          break;
        }
      }
      if (inputStream == nullptr) {
        throw _error('No $description stream found in file: $filePath');
      }

      return inputStream;
    } finally {
      calloc.free(fileNative);
    }
  }

  Pointer<AVStream> _addStreamToOutputContext({
    required Pointer<Pointer<AVFormatContext>> outputCtx,
    required Pointer<AVStream> inputStream,
    required AVMediaType streamType,
  }) {
    final description = streamType.description;

    final outputStream = _ffmpeg.avformat_new_stream(outputCtx.value, nullptr);
    if (outputStream == nullptr) {
      throw _error('Failed to create $description stream');
    }
    _log.fine('Added $description stream to output context.');

    int errorCode = _ffmpeg.avcodec_parameters_copy(
        outputStream.ref.codecpar, inputStream.ref.codecpar);
    if (errorCode < 0) {
      throw _error('Failed to copy $description codec parameters',
          errorCode: errorCode);
    }

    if (inputStream.ref.time_base.den == 0) {
      throw _error('Invalid $description time base');
    }
    outputStream.ref.time_base = inputStream.ref.time_base;
    _log.finer('Copied $description stream codec parameters.');

    return outputStream;
  }

  void _muxStreams({
    required Pointer<Pointer<AVFormatContext>> outputCtx,
    required MediaPacket videoPacket,
    required MediaPacket audioPacket,
  }) {
    // Prime the loop with the first packet of each stream.
    bool hasVideo = _readNextPacket(videoPacket);
    bool hasAudio = _readNextPacket(audioPacket);

    // While there are still video or audio packets to write...
    while (hasAudio || hasVideo) {
      // Find the next packet with the earliest timestamp.
      final bool wantsVideo = (hasVideo &&
          (!hasAudio ||
              _ffmpeg.av_compare_ts(
                      videoPacket.pkt.ref.pts,
                      videoPacket.outputStream.ref.time_base,
                      audioPacket.pkt.ref.pts,
                      audioPacket.outputStream.ref.time_base) <=
                  0));
      if (wantsVideo) {
        _writePacket(outputCtx.value, videoPacket);
        hasVideo = _readNextPacket(videoPacket);
      } else {
        _writePacket(outputCtx.value, audioPacket);
        hasAudio = _readNextPacket(audioPacket);
      }
    }

    _log.info('Wrote ${videoPacket.outputStream.ref.nb_frames} video frames'
        ' and ${audioPacket.outputStream.ref.nb_frames} audio frames.');
  }

  bool _readNextPacket(MediaPacket pkt) {
    int errorCode = _ffmpeg.av_read_frame(pkt.inputCtx.value, pkt.pkt);
    if (errorCode < 0) {
      return false;
    }
    if (pkt.pkt.ref.pts == AV_NOPTS_VALUE) {
      _log.warning('No PTS for ${pkt.mediaType.description} packet at pos '
          '${pkt.pkt.ref.pos} bytes');
    }
    // Rescale does nothing if input and output time bases are the same.
    // In this package, currently, they are, but it's good practice to do it anyway.
    _ffmpeg.av_packet_rescale_ts(
      pkt.pkt,
      pkt.inputStream.ref.time_base,
      pkt.outputStream.ref.time_base,
    );
    // Set the stream index to the proper output stream index.
    // Otherwise, the packet will be written to the wrong stream.
    pkt.pkt.ref.stream_index = pkt.outputStream.ref.index;
    return true;
  }

  void _writePacket(Pointer<AVFormatContext> outputCtx, MediaPacket pkt) {
    _log.finer([
      'Write ${pkt.mediaType.description} pkt,',
      'pts=${pkt.pkt.ref.pts}',
      if (pkt.pkt.ref.dts != pkt.pkt.ref.pts) '(dts=${pkt.pkt.ref.dts})',
      'size=${pkt.pkt.ref.size}B',
      '@ ${pkt.scaledPts.toStringAsFixed(2)}s',
    ].join(' '));

    // Write the packet ensuring correct interleaving.
    int errorCode = _ffmpeg.av_interleaved_write_frame(outputCtx, pkt.pkt);
    if (errorCode < 0) {
      throw _error('Failed to write ${pkt.mediaType.description} packet',
          errorCode: errorCode);
    }
  }

  void _freeAll(List<Pointer> ptrs) {
    for (final ptr in ptrs) {
      if (ptr != nullptr) {
        calloc.free(ptr);
      }
    }
  }
}
