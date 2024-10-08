library;

import 'package:build/build.dart';

import 'src/ffmpeg_builder.dart';

FFmpegBuilder ffmpegBuilderFactory(BuilderOptions options) =>
    FFmpegBuilder(options);
