/// Generate Dart FFI bindings to FFmpeg with a simple library annotation.
///
/// This library allows you to automatically generate FFI bindings to FFmpeg
/// by using the `@FFmpegGen` annotation on your Dart library.
///
/// To use this library, annotate your Dart library with `@FFmpegGen`, specifying the FFmpeg
/// functions, structs, enums, and other elements you want to include or exclude. The bindings
/// will be generated automatically when you run the build process.
///
/// Example usage (all fields are optional unless required by your system config; please review annotation docs):
///
/// ```dart
/// @FFmpegGen(
///   versionSpec: '>=7.1 <8.0',
///   headerPaths: {'/usr/local/include', '/opt/ffmpeg/include'},
///   llvmPaths: {'/usr/local/opt/llvm', '/opt/llvm'},
///   libraries: {FFmpegLibrary.avCodec, FFmpegLibrary.avFormat},
///   excludeAllByDefault: true,
///   functions: FFInclude({
///     'av_compare_ts',
///     'av_interleaved_write_frame',
///     'av_log_set_level',
///   }),
///   structs: FFInclude({'AVFormatContext', 'AVIOContext', 'AVPacket'}),
///   enums: FFInclude({'AVMediaType'}),
///   unnamedEnums: FFInclude({'UNNAMED_ENUM'}),
///   unions: ffAllowAll,
///   globals: ffDenyAll,
///   macros: FFInclude({'AVIO_FLAG_WRITE', 'AV_NOPTS_VALUE'}),
///   typedefs: ffAllowAll,
///   className: 'FFmpegBindings',
///   excludeHeaders: {'libavcodec/jni.h', ...defaultExcludeHeaders},
/// )
/// library;
///
/// import 'my_library.ffipeg.dart'; // Use the generated bindings
/// ```
///
/// The generated file can be imported and used in your project, allowing direct access
/// to the FFmpeg C API through Dart's FFI (Foreign Function Interface).
///
/// For a full working example, please see the `ffipeg_muxer` package.
library;

export 'src/ffmpeg_gen.dart';
