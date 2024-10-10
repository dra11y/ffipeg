library;

import 'package:build/build.dart';

import 'src/ffmpeg_config_builder.dart';
import 'src/ffmpeg_ffigen_builder.dart';

FFmpegConfigBuilder ffmpegConfigBuilderFactory(BuilderOptions options) =>
    FFmpegConfigBuilder(options);

FFmpegFfiGenBuilder ffmpegFfiGenBuilderFactory(BuilderOptions options) =>
    FFmpegFfiGenBuilder(options);
