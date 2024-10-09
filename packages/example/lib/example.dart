@FFmpegGen(
  excludeAllByDefault: true,
  functions: FFInclude([
    'av_register_all',
    'avcodec_parameters_copy',
    'avformat_network_init',
    'avformat_alloc_context',
    'avformat_free_context',
    'avformat_open_input',
    'avformat_find_stream_info',
    'avformat_alloc_output_context2',
    'avformat_new_stream',
    'avformat_write_header',
    'avio_open',
    'avio_close',
    'avformat_close_input',
    'av_read_frame',
    'av_interleaved_write_frame',
    'av_packet_unref',
    'av_write_trailer',
  ]),
  structs: FFInclude([
    'AVFormatContext',
    'AVPacket',
    'AVStream',
  ]),
)
library;

import 'package:ffipeg/ffipeg.dart';
export 'example.ffipeg.dart';
