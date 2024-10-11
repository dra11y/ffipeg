@FFmpegGen(
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
  'av_interleaved_write_frame',
  'av_log_set_level',
  'av_packet_alloc',
  'av_packet_free',
  'av_packet_rescale_ts',
  'av_read_frame',
  'av_write_trailer',
  'avcodec_parameters_copy',
  'avformat_alloc_output_context2',
  'avformat_close_input',
  'avformat_configuration',
  'avformat_find_stream_info',
  'avformat_free_context',
  'avformat_new_stream',
  'avformat_open_input',
  'avformat_version',
  'avformat_write_header',
  'avio_close',
  'avio_open',
};

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

  int avformatVersion() {
    return ffmpeg.avformat_version();
  }

  String avformatConfiguration() {
    final Pointer<Utf8> configPtr =
        ffmpeg.avformat_configuration().cast<Utf8>();
    return configPtr.toDartString();
  }

  MuxerError error(String message) {
    log.severe(message);
    return MuxerError(message);
  }

  int avLogLevel(Level level) => switch (level) {
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

  MuxerResult run({
    required String videoFile,
    required String audioFile,
    required String outputFile,
    String? format,
    bool overwrite = false,
  }) {
    if (File(outputFile).existsSync() && !overwrite) {
      return error('Output file $outputFile already exists.');
    }

    ffmpeg.av_log_set_level(avLogLevel(log.level));

    // Allocate pointers
    log.finer('Allocating pointers...');
    final videoInputCtx = calloc<Pointer<AVFormatContext>>();
    final audioInputCtx = calloc<Pointer<AVFormatContext>>();
    final outputCtx = calloc<Pointer<AVFormatContext>>();
    final avioCtx = calloc<Pointer<AVIOContext>>();
    final audioPkt = ffmpeg.av_packet_alloc();
    final videoPkt = ffmpeg.av_packet_alloc();
    final audioPktPtr = calloc<Pointer<AVPacket>>();
    final videoPktPtr = calloc<Pointer<AVPacket>>();
    audioPktPtr.value = audioPkt;
    videoPktPtr.value = videoPkt;

    // Convert Dart strings to native UTF-8 strings
    final videoFileNative = videoFile.toNativeUtf8();
    final audioFileNative = audioFile.toNativeUtf8();
    final outputFileNative = outputFile.toNativeUtf8();
    final formatNative = format?.toNativeUtf8() ?? nullptr;

    try {
      // Step 1: Open video input file
      log.fine('Opening video file: $videoFile...');
      if (0 !=
          ffmpeg.avformat_open_input(
              videoInputCtx, videoFileNative.cast(), nullptr, nullptr)) {
        throw error('Failed to open video file: $videoFile');
      }
      log.info('Opened video file: $videoFile');

      if (ffmpeg.avformat_find_stream_info(videoInputCtx.value, nullptr) < 0) {
        throw error('Failed to find video stream info');
      }
      log.fine('Found video stream info.');

      // Find video stream index in the video file
      Pointer<AVStream> videoInputStream = nullptr;
      for (int i = 0; i < videoInputCtx.value.ref.nb_streams; i++) {
        if (videoInputCtx.value.ref.streams[i].ref.codecpar.ref.codec_type ==
            AVMediaType.AVMEDIA_TYPE_VIDEO) {
          videoInputStream = videoInputCtx.value.ref.streams[i];
          break;
        }
      }
      if (videoInputStream == nullptr) {
        throw error('No video stream found in video file.');
      }

      // Step 2: Open audio input file
      log.fine('Opening audio file: $audioFile...');
      if (ffmpeg.avformat_open_input(
              audioInputCtx, audioFileNative.cast(), nullptr, nullptr) !=
          0) {
        throw error('Failed to open audio file: $audioFile');
      }
      log.info('Opened audio file: $audioFile');

      if (ffmpeg.avformat_find_stream_info(audioInputCtx.value, nullptr) < 0) {
        throw error('Failed to find audio stream info');
      }
      log.fine('Found audio stream info.');

      // Find audio stream index in the audio file
      Pointer<AVStream> audioInputStream = nullptr;
      for (int i = 0; i < audioInputCtx.value.ref.nb_streams; i++) {
        if (audioInputCtx.value.ref.streams[i].ref.codecpar.ref.codec_type ==
            AVMediaType.AVMEDIA_TYPE_AUDIO) {
          audioInputStream = audioInputCtx.value.ref.streams[i];
          break;
        }
      }
      if (audioInputStream == nullptr) {
        throw error('No audio stream found in audio file.');
      }

      // Step 3: Allocate output context
      if (ffmpeg.avformat_alloc_output_context2(outputCtx, nullptr,
              formatNative.cast(), outputFileNative.cast()) <
          0) {
        throw error('Failed to allocate output context');
      }
      log.fine('Allocated output context.');

      // Step 4: Add video stream to the output context
      final videoOutputStream =
          ffmpeg.avformat_new_stream(outputCtx.value, nullptr);
      if (videoOutputStream == nullptr) {
        throw error('Failed to create video stream');
      }
      log.fine('Added video stream to output context.');

      final videoPacket = MediaPacket(
        mediaType: AVMediaType.AVMEDIA_TYPE_VIDEO,
        inputCtx: videoInputCtx,
        pkt: videoPkt,
        inputStream: videoInputStream,
        outputStream: videoOutputStream,
      );

      ffmpeg.avcodec_parameters_copy(videoPacket.outputStream.ref.codecpar,
          videoPacket.inputStream.ref.codecpar);
      if (videoPacket.inputStream.ref.time_base.den == 0) {
        throw error('Invalid video time base');
      }
      videoPacket.outputStream.ref.time_base =
          videoPacket.inputStream.ref.time_base;
      log.finer('Copied video stream codec parameters.');

      // Step 5: Add audio stream to the output context
      final audioOutputStream =
          ffmpeg.avformat_new_stream(outputCtx.value, nullptr);
      if (audioOutputStream == nullptr) {
        throw error('Failed to create audio stream');
      }
      log.fine('Added audio stream to output context.');

      final audioPacket = MediaPacket(
        mediaType: AVMediaType.AVMEDIA_TYPE_AUDIO,
        inputCtx: audioInputCtx,
        pkt: audioPkt,
        inputStream: audioInputStream,
        outputStream: audioOutputStream,
      );

      ffmpeg.avcodec_parameters_copy(audioPacket.outputStream.ref.codecpar,
          audioPacket.inputStream.ref.codecpar);
      if (audioPacket.inputStream.ref.time_base.den == 0) {
        throw error('Invalid audio time base');
      }
      audioPacket.outputStream.ref.time_base =
          audioPacket.inputStream.ref.time_base;
      log.finer('Copied audio stream codec parameters.');

      // Step 6: Open output file
      log.fine('Opening output file: $outputFile...');
      if (ffmpeg.avio_open(avioCtx, outputFileNative.cast(), AVIO_FLAG_WRITE) <
          0) {
        throw error('Failed to open output file: $outputFile');
      }
      log.info('Opened output file: $outputFile');

      // Step 7: Assign the AVIO context to the output format context
      outputCtx.value.ref.pb = avioCtx.value;
      log.finer('Assigned AVIO context to output context.');

      // Step 8: Write the file header
      if (ffmpeg.avformat_write_header(outputCtx.value, nullptr) < 0) {
        throw error('Failed to write header');
      }
      log.fine('Wrote header.');

      // Step 9: Start reading and muxing packets

      bool readPacket(MediaPacket pkt) {
        final result = ffmpeg.av_read_frame(pkt.inputCtx.value, pkt.pkt);
        if (result < 0) {
          return false;
        }
        // Rescale does nothing if input and output time bases are the same.
        ffmpeg.av_packet_rescale_ts(
          pkt.pkt,
          pkt.inputStream.ref.time_base,
          pkt.outputStream.ref.time_base,
        );
        // Set the stream index to the proper output stream index.
        pkt.pkt.ref.stream_index = pkt.outputStream.ref.index;
        return true;
      }

      void logPacket(MediaPacket pkt) {
        // log.finer(
        //     'write ${pkt.mediaType} @ ${pkt.scaledPts.toStringAsFixed(2)} s');
        log.finer([
          'Write ${pkt.mediaType == AVMediaType.AVMEDIA_TYPE_VIDEO ? 'VIDEO' : 'audio'} pkt,',
          'pts=${pkt.pkt.ref.pts}',
          if (pkt.pkt.ref.dts != pkt.pkt.ref.pts) '(dts=${pkt.pkt.ref.dts})',
          'size=${pkt.pkt.ref.size}B',
          '@ ${pkt.scaledPts.toStringAsFixed(2)}s',
        ].join(' '));
      }

      bool writePacketAndReadNext(MediaPacket pkt) {
        logPacket(pkt);
        ffmpeg.av_interleaved_write_frame(outputCtx.value, pkt.pkt);

        return readPacket(pkt);
      }

      bool hasVideo = readPacket(videoPacket);
      bool hasAudio = readPacket(audioPacket);

      bool wantsVideoPacket() {
        if (!hasVideo) {
          return false;
        }

        if (!hasAudio) {
          return true;
        }

        final compare = ffmpeg.av_compare_ts(
          videoPacket.pkt.ref.pts,
          videoPacket.outputStream.ref.time_base,
          audioPacket.pkt.ref.pts,
          audioPacket.outputStream.ref.time_base,
        );

        return compare <= 0;
      }

      while (hasAudio || hasVideo) {
        final wantsVideo = wantsVideoPacket();
        if (wantsVideo) {
          hasVideo = writePacketAndReadNext(videoPacket);
        } else {
          hasAudio = writePacketAndReadNext(audioPacket);
        }
      }

      log.info('Wrote ${videoPacket.outputStream.ref.nb_frames} video frames'
          ' and ${audioPacket.outputStream.ref.nb_frames} audio frames.');

      // Step 10: Write trailer to close the file
      ffmpeg.av_write_trailer(outputCtx.value);
      log.fine('Wrote trailer.');

      return MuxerOK(outputFile);
    } catch (e) {
      return error('An unhandled error occurred: $e');
    } finally {
      // Clean up

      if (avioCtx.value != nullptr) {
        ffmpeg.avio_close(avioCtx.value);
        log.info('Output file $outputFile closed.');
      } else {
        log.warning('Output file $outputFile was never opened.');
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

  void _freeAll(List<Pointer> ptrs) {
    for (final ptr in ptrs) {
      if (ptr != nullptr) {
        calloc.free(ptr);
      }
    }
  }
}
