// @FFmpegGen(
//   excludeAllByDefault: true,
//   functions: FFInclude({
//     'av_register_all',
//     'avcodec_parameters_copy',
//     'avformat_network_init',
//     'avformat_alloc_context',
//     'avformat_free_context',
//     'avformat_open_input',
//     'avformat_find_stream_info',
//     'avformat_alloc_output_context2',
//     'avformat_new_stream',
//     'avformat_write_header',
//     'avio_open',
//     'avio_close',
//     'avformat_close_input',
//     'av_read_frame',
//     'av_interleaved_write_frame',
//     'av_packet_unref',
//     'av_write_trailer',
//   }),
//   macros: FFInclude({'AVFMT_FLAG_.*', 'AVIO_FLAG_.*'}),
//   structs: FFInclude({
//     'AVFormatContext',
//     'AVIOContext',
//     'AVPacket',
//     'AVStream',
//   }),
// )
library;

import 'dart:ffi';

import 'package:example/example.ffipeg.dart';
import 'package:ffi/ffi.dart';
import 'package:ffipeg/ffipeg.dart';

void main() {
  final videoFile = '/Users/tom/Desktop/XqvKDCP5-xE_video.webm';
  final audioFile = '/Users/tom/Desktop/XqvKDCP5-xE_audio.webm';
  final outputFile = '/Users/tom/Desktop/test.mp4';

  testFffmpeg(videoFile, audioFile, outputFile);
}

void testFffmpeg(String videoFile, String audioFile, String outputFile) {
  final ffmpeg = FFmpeg(DynamicLibrary.open('/Users/tom/ffmpeg/bin/ffmpeg'));

  // Allocate necessary pointers
  final videoFmtCtx = calloc<Pointer<AVFormatContext>>();
  final audioFmtCtx = calloc<Pointer<AVFormatContext>>();
  final outputFmtCtx = calloc<Pointer<AVFormatContext>>();
  final pkt = calloc<AVPacket>();

  final avioCtx = calloc<Pointer<AVIOContext>>();

  // Convert Dart strings to ffi.Pointer<Utf8> using the Utf8.fromUtf8 method
  final videoFileNative = videoFile.toNativeUtf8();
  final audioFileNative = audioFile.toNativeUtf8();
  final outputFileNative = outputFile.toNativeUtf8();

  try {
    // Open video file
    if (ffmpeg.avformat_open_input(
            videoFmtCtx, videoFileNative.cast(), nullptr, nullptr) !=
        0) {
      print('Failed to open video file');
      return;
    }

    // Find video stream information
    if (ffmpeg.avformat_find_stream_info(videoFmtCtx.value, nullptr) < 0) {
      print('Failed to find video stream information');
      return;
    }

    // Open audio file
    if (ffmpeg.avformat_open_input(
            audioFmtCtx, audioFileNative.cast(), nullptr, nullptr) !=
        0) {
      print('Failed to open audio file');
      return;
    }

    // Find audio stream information
    if (ffmpeg.avformat_find_stream_info(audioFmtCtx.value, nullptr) < 0) {
      print('Failed to find audio stream information');
      return;
    }

    // Allocate output context
    if (ffmpeg.avformat_alloc_output_context2(
            outputFmtCtx, nullptr, nullptr, outputFileNative.cast()) <
        0) {
      print('Failed to allocate output context');
      return;
    }

    // Add video stream to output
    final videoStream = ffmpeg.avformat_new_stream(outputFmtCtx.value, nullptr);
    if (videoStream == nullptr) {
      print('Failed to add video stream to output');
      return;
    }

    // Copy video stream parameters
    ffmpeg.avcodec_parameters_copy(videoStream.ref.codecpar,
        videoFmtCtx.value.ref.streams[0].ref.codecpar);

    // Add audio stream to output
    final audioStream = ffmpeg.avformat_new_stream(outputFmtCtx.value, nullptr);
    if (audioStream == nullptr) {
      print('Failed to add audio stream to output');
      return;
    }

    // Copy audio stream parameters
    ffmpeg.avcodec_parameters_copy(audioStream.ref.codecpar,
        audioFmtCtx.value.ref.streams[0].ref.codecpar);

    videoStream.ref.time_base = videoFmtCtx.value.ref.streams[0].ref.time_base;
    audioStream.ref.time_base = audioFmtCtx.value.ref.streams[0].ref.time_base;
    videoStream.ref.r_frame_rate =
        videoFmtCtx.value.ref.streams[0].ref.r_frame_rate;
    videoStream.ref.codecpar.ref.codec_tag = 0;
    audioStream.ref.codecpar.ref.codec_tag = 0;

    // Open output file
    if (ffmpeg.avio_open(avioCtx, outputFileNative.cast(), AVIO_FLAG_WRITE) <
        0) {
      print('Failed to open output file');
      return;
    }

    // Assign avioCtx to the output format context's pb field
    outputFmtCtx.value.ref.pb = avioCtx.value;
    outputFmtCtx.value.ref.oformat.ref.flags |= AVFMT_FLAG_GENPTS;

    // Write header
    if (ffmpeg.avformat_write_header(outputFmtCtx.value, nullptr) < 0) {
      print('Failed to write header');
      return;
    }

    // Read packets from video and write them to the output
    while (ffmpeg.av_read_frame(videoFmtCtx.value, pkt) >= 0) {
      pkt.ref.stream_index = videoStream.ref.index;
      ffmpeg
        ..av_interleaved_write_frame(outputFmtCtx.value, pkt)
        ..av_packet_unref(pkt);
    }

    // Read packets from audio and write them to the output
    while (ffmpeg.av_read_frame(audioFmtCtx.value, pkt) >= 0) {
      pkt.ref.stream_index = audioStream.ref.index;
      ffmpeg
        ..av_interleaved_write_frame(outputFmtCtx.value, pkt)
        ..av_packet_unref(pkt);
    }

    // Write trailer
    ffmpeg.av_write_trailer(outputFmtCtx.value);
  } finally {
    // Clean up

    // Free the AVIOContext pointer
    if (avioCtx != nullptr) {
      ffmpeg.avio_close(avioCtx.value);
    }

    calloc
      ..free(videoFmtCtx)
      ..free(audioFmtCtx)
      ..free(outputFmtCtx)
      ..free(pkt)
      ..free(avioCtx)
      ..free(videoFileNative)
      ..free(audioFileNative)
      ..free(outputFileNative);
  }

  print('Muxing complete: $outputFile');
}
