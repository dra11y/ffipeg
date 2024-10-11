@FFmpegGen(
  versionSpec: '>=7.1 <8.0',
  excludeAllByDefault: true,
  functions: FFInclude(functions),
  structs: FFInclude({'AVFormatContext', 'AVIOContext', 'AVPacket'}),
  enums: FFInclude({'AVMediaType'}),
  macros: FFInclude(
      {'AVIO_FLAG_WRITE', 'AV_NOPTS_VALUE', 'AV_LOG_.*', 'AVERROR.*'}),
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

/// Convenient wrapper for media packet info coupled with its
/// context and streams, to avoid passing them around separately.
class MediaPacket {
  final AVMediaType mediaType;
  final Pointer<Pointer<AVFormatContext>> inputCtx;
  final Pointer<AVPacket> pkt;
  final Pointer<AVStream> inputStream;
  final Pointer<AVStream> outputStream;

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

extension AVMediaTypeDescription on AVMediaType {
  /// Get the stream description in lowercase, i.e. 'audio' or 'video'
  String get description => name.split('_').last.toLowerCase();
}

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
    ffmpeg = FFmpeg(dylib);
    log = logger ?? Logger.root;
  }

  late final FFmpeg ffmpeg;
  late final Logger log;

  String getFFmpegVersion() {
    final Pointer<Utf8> versionPtr = ffmpeg.av_version_info().cast();
    return versionPtr.toDartString();
  }

  String getFFmpegConfig() {
    final Pointer<Utf8> configPtr =
        ffmpeg.avformat_configuration().cast<Utf8>();
    return configPtr.toDartString();
  }

  MuxerResult run({
    required String videoFile,
    required String audioFile,
    required String outputFile,
    String? format,
    bool overwrite = false,
  }) {
    if (File(outputFile).existsSync() && !overwrite) {
      return _error('Output file $outputFile already exists.');
    }

    ffmpeg.av_log_set_level(_avLogLevel(log.level));

    // Allocate pointers
    log.finer('Allocating pointers...');
    final audioPktPtr = _allocPacket();
    if (audioPktPtr == null) {
      return _error('Failed to allocate audio packet');
    }
    final videoPktPtr = _allocPacket();
    if (videoPktPtr == null) {
      ffmpeg.av_packet_free(audioPktPtr);
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
      int errorCode = ffmpeg.avformat_alloc_output_context2(
          outputCtx, nullptr, formatNative.cast(), outputFileNative.cast());
      if (errorCode < 0) {
        throw _error('Failed to allocate output context', errorCode: errorCode);
      }
      log.fine('Allocated output context.');

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
      log.fine('Opening output file: $outputFile...');
      errorCode =
          ffmpeg.avio_open(avioCtx, outputFileNative.cast(), AVIO_FLAG_WRITE);
      if (errorCode < 0) {
        throw _error('Failed to open output file: $outputFile',
            errorCode: errorCode);
      }
      log.info('Opened output file: $outputFile');

      // Step 7: Assign the AVIO context to the output format context
      outputCtx.value.ref.pb = avioCtx.value;
      log.finer('Assigned AVIO context to output context.');

      // Step 8: Write the file header
      errorCode = ffmpeg.avformat_write_header(outputCtx.value, nullptr);
      if (errorCode < 0) {
        throw _error('Failed to write header', errorCode: errorCode);
      }
      log.fine('Wrote header.');

      // Step 9: Mux streams
      _muxStreams(
          outputCtx: outputCtx,
          videoPacket: videoPacket,
          audioPacket: audioPacket);

      // Step 10: Write trailer to close the file
      errorCode = ffmpeg.av_write_trailer(outputCtx.value);
      if (errorCode < 0) {
        throw _error('Failed to write trailer', errorCode: errorCode);
      }
      log.fine('Wrote trailer.');

      return MuxerOK(outputFile);
    } on MuxerError catch (e) {
      return e;
    } finally {
      // Clean up

      if (avioCtx.value != nullptr) {
        ffmpeg.avio_close(avioCtx.value);
        log.info('Output file $outputFile closed.');
      }

      ffmpeg
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

      log.info('Resources freed.');
    }
  }

  MuxerError _error(String message, {int? errorCode}) {
    final List<String> errorList = [message];

    if (errorCode != null) {
      const int errbufSize = 1024;
      final errbuf = calloc<Char>(errbufSize);
      try {
        // Fetch FFmpeg error description
        final result = ffmpeg.av_strerror(errorCode, errbuf, errbufSize);
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
    log.severe(errorMessage);
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
    final pkt = ffmpeg.av_packet_alloc();
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
    log.fine('Opening $description file: $filePath...');
    final fileNative = filePath.toNativeUtf8();
    try {
      int errorCode = ffmpeg.avformat_open_input(
          inputCtx, fileNative.cast(), nullptr, nullptr);
      if (errorCode != 0) {
        throw _error('Failed to open $description file: $filePath',
            errorCode: errorCode);
      }
      log.info('Opened $description file: $filePath');

      errorCode = ffmpeg.avformat_find_stream_info(inputCtx.value, nullptr);
      if (errorCode < 0) {
        throw _error('Failed to find $description stream info',
            errorCode: errorCode);
      }
      log.fine('Found $description stream info.');

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

    final outputStream = ffmpeg.avformat_new_stream(outputCtx.value, nullptr);
    if (outputStream == nullptr) {
      throw _error('Failed to create $description stream');
    }
    log.fine('Added $description stream to output context.');

    int errorCode = ffmpeg.avcodec_parameters_copy(
        outputStream.ref.codecpar, inputStream.ref.codecpar);
    if (errorCode < 0) {
      throw _error('Failed to copy $description codec parameters',
          errorCode: errorCode);
    }
    if (inputStream.ref.time_base.den == 0) {
      throw _error('Invalid $description time base');
    }
    outputStream.ref.time_base = inputStream.ref.time_base;
    log.finer('Copied $description stream codec parameters.');

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
              ffmpeg.av_compare_ts(
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

    log.info('Wrote ${videoPacket.outputStream.ref.nb_frames} video frames'
        ' and ${audioPacket.outputStream.ref.nb_frames} audio frames.');
  }

  bool _readNextPacket(MediaPacket pkt) {
    int errorCode = ffmpeg.av_read_frame(pkt.inputCtx.value, pkt.pkt);
    if (errorCode < 0) {
      return false;
    }
    // Rescale does nothing if input and output time bases are the same.
    // In this package, currently, they are, but it's good practice to do it anyway.
    ffmpeg.av_packet_rescale_ts(
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
    log.finer([
      'Write ${pkt.mediaType.description} pkt,',
      'pts=${pkt.pkt.ref.pts}',
      if (pkt.pkt.ref.dts != pkt.pkt.ref.pts) '(dts=${pkt.pkt.ref.dts})',
      'size=${pkt.pkt.ref.size}B',
      '@ ${pkt.scaledPts.toStringAsFixed(2)}s',
    ].join(' '));

    AVERROR_BSF_NOT_FOUND;

    // Write the packet ensuring correct interleaving.
    int errorCode = ffmpeg.av_interleaved_write_frame(outputCtx, pkt.pkt);
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
