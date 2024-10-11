# ffipeg

Easily generate Dart FFI bindings to FFmpeg for use in your project in 3 steps:
1. Add a library annotation;
2. Run `build_runner`;
3. Import the generated file, ffi, and go!

## Example

(Incomplete; for illustrative purposes only; see `ffipeg_muxer` package for full working example.)

### ffmpeg.dart
```dart
@FFmpegGen(
  excludeAllByDefault: true,
  functions: FFInclude({
    'av_compare_ts',
    'av_interleaved_write_frame',
    'av_log_set_level',
    'av_packet_alloc',
    // ...
    'avio_open',
  }),
  structs: FFInclude({'AVFormatContext', 'AVIOContext', 'AVPacket'}),
  enums: FFInclude({'AVMediaType'}),
  macros: FFInclude({'AVIO_FLAG_WRITE', 'AV_NOPTS_VALUE', 'AV_LOG_.*'}),
)
library;

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:ffipeg/ffipeg.dart'; // Exports `@FFmpegGen` Annotation
import 'ffmpeg.ffipeg.dart'; // Generated _name_.ffipeg.dart file with FFI bindings

void main() {
    final dylib = DynamicLibrary.open('/path/to/ffmpeg')
    final ffmpeg = FFmpeg(dylib);
    ffmpeg.av_log_set_level(AV_LOG_DEBUG);
    final videoInputCtx = calloc<Pointer<AVFormatContext>>();
    final videoPkt = ffmpeg.av_packet_alloc();
    final videoPktPtr = calloc<Pointer<AVPacket>>();
    final videoFile = "/path/to/video/file.mp4";
    if (0 != ffmpeg.avformat_open_input(
        videoInputCtx, videoFile.toNativeUtf8().cast(), nullptr, nullptr)) {
        throw Exception('Failed to open video file: $videoFile');
    }
    // ... do more stuff ...
    // We're dealing with C ... be sure to clean up resources!
    ffmpeg
        ..avformat_close_input(videoInputCtx)
        ..av_packet_free(videoPktPtr);
    if (videoPktPtr != nullptr) {
        calloc.free(videoPktPtr);
    }
    if (videoInputCtx != nullptr) {
        calloc.free(videoInputCtx);
    }
}

```

## Features

- This package is basically a wrapper around `FfiGen()` that uses `build_runner` and makes it more accessible as part of a standard build process. It offers reasonable defaults for FFmpeg.
- Specify your own `headerPaths` to FFmpeg header files, or use default included headers. If supplied, `headerPaths` will be tried in order, so multiple build platforms can be supported.
- Specify which FFmpeg libraries (`FFmpegLibrary.avCodec`, etc.), (all by default), should be included.
- Pass standard `FfiGen()` include/exclude options via strongly-typed options of `Set<String>` for functions, structs, macros, enums, etc. using `FFInclude({...})`, `FFExclude({...})`, `ffAllowAll`, or `ffDenyAll`.
- Customize the generated class name for functions (`FFmpeg` by default).
- Pass custom `llvmPaths` to `FfiGen()` (optional).

## Getting started

### Prerequisites

- Flutter is **not** required. Only Dart + the package dependencies are required for code _generation_.
- Actually running your FFI code **requires** an FFmpeg binary (either executable CLI or dylib, e.g. in the [`fvp`](https://pub.dev/packages/fvp) package for Flutter).
- This package does **not** require `fvp` or its `mdk-sdk`. __Any__ FFmpeg binary built with the functions/features used and compatible with **both the target system and the version of headers used** to build the bindings will work.

### Installation

- Add the 4 required packages:
```
dart pub add ffipeg
dart pub add ffi
dart pub add --dev ffipeg_builder
dart pub add --dev build_runner
```

## Usage

- You will need to ensure the FFmpeg binary is available in your built Flutter app or Dart executable's path.
    - You may need a specific `Platform` switch to specify the path/name passed into the `DynamicLibrary()` constructor.

Refer to the [`FFmpegGen` class source documentation](lib/src/ffmpeg_gen.dart) for specific usage of the annotation.

Refer to the example code above to get started, or [`ffipeg_muxer`](https://pub.dev/packages/ffipeg_muxer) package for a working CLI/Dart class example demonstratng how to mux an audio and video file without transcoding (copies the codecs).

## Premise

There is currently no simple way of including the FFmpeg binary in a cross-platform Flutter desktop app. [`ffmpeg_kit_flutter`](https://pub.dev/packages/ffmpeg_kit_flutter) does not offer a Windows or Linux version (Why not? They already have a build pipeline for 3 platforms...).

The only solution I found was [`fvp`](https://pub.dev/packages/fvp), which includes the FFmpeg binary via its bundled [`mdk-sdk`](https://github.com/wang-bin/mdk-sdk), but it offers no FFmpeg API itself. And including both `fvp` and a built FFmpeg binary in my app would introduce too much bloat for the one function I needed.

Therefore, I learned to use FFmpeg through FFI and created this package.

## Contributing

Contributions are welcome, especially if any bugs are found. Please open an issue in the repo at https://github.com/dra11y/ffipeg-dart.
