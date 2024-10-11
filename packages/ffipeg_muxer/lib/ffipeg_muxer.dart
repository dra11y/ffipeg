/// # ffipeg_muxer
///
/// CLI and API to use FFmpeg FFI to mux separate audio and video files into a single output file.
///
/// ## Example Usage
///
/// ```dart
/// void main() {
///     // Use FFmpeg on macOS installed via Homebrew:
///     final muxer = Muxer(DynamicLibrary.open('/opt/homebrew/bin/ffmpeg'));
///     // Use FFmpeg in macOS Desktop Flutter app installed via `fvp` (v0.26.1) package:
///     final muxer = Muxer(DynamicLibrary.open('libffmpeg.7.dylib'));
///     final result = muxer.run(
///         videoFile: '/path/to/video.webm',
///         audioFile: '/path/to/audio.mp4',
///         outputFile: '/path/to/output.mp4',
///     );
///     switch (result) {
///         case MuxerOK(:final outputFile):
///             print('Successfully muxed to $outputFile');
///             break;
///         case MuxerError(:final message):
///             print('Muxing failed: $message');
///             throw result;
///     }
/// }
/// ```
///
/// ### Installation
///
/// - Only this package **and the ffmpeg binary** are required, since bindings are already generated (`ffipeg` is a transitive dependency):
/// ```
/// dart pub add ffipeg_muxer
/// ```
///
/// ## Features
///
/// - This package only muxes; it does not transcode, retime, filter, or do anything else.
/// - Both files will be muxed from the beginning.
/// - If the video input is longer than the audio, the remaining video will be silent.
/// - If the audio input is longer than the video, the remaining audio will have black video.
/// - I've only tested this with VP9 video and Opus audio, but H.264 and AAC should work fine.
/// - The resulting files will likely not play back in QuickTime (as it does not support much!). Use VLC and `ffprobe` to test outputs.
///
/// Please refer to the [`ffipeg`](https://pub.dev/packages/ffipeg) package README for more info / further usage of FFI bindings to FFmpeg in Dart.
library;

export 'src/muxer.dart' show Muxer;
export 'src/muxer_result.dart' show MuxerResult, MuxerError, MuxerOK;
export 'src/version.dart';
