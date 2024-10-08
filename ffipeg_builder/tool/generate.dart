import 'dart:io';

import 'package:ffigen/ffigen.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as path;

const String root = 'ffmpeg-headers/current';

// enum Library {
//   avcodec('FFAVCodec'),
//   avdevice('FFAVDevice'),
//   avfilter('FFAVFilter'),
//   avformat('FFAVFormat'),
//   avutil('FFAVUtil'),
//   postproc('FFPostProc'),
//   swresample('FFSWResample'),
//   swscale('FFSWScale');

//   final String className;

//   String get dir => 'lib$name';

//   const Library(this.className);

//   static Library fromDir(String dir) => values.firstWhere((v) => v.dir == dir);
// }

final gen = FfiGen();

const exclude = <String>[
  'libavcodec/d3d11va.h',
  'libavcodec/dxva2.h',
  'libavcodec/qsv.h',
  'libavcodec/vdpau.h',
  'libavcodec/videotoolbox.h',
  'libavcodec/xvmc.h',
  'libavutil/hwcontext_cuda.h',
  'libavutil/hwcontext_d3d11va.h',
  'libavutil/hwcontext_d3d12va.h',
  'libavutil/hwcontext_drm.h',
  'libavutil/hwcontext_dxva2.h',
  'libavutil/hwcontext_mediacodec.h',
  'libavutil/hwcontext_opencl.h',
  'libavutil/hwcontext_qsv.h',
  'libavutil/hwcontext_vaapi.h',
  'libavutil/hwcontext_vdpau.h',
  'libavutil/hwcontext_videotoolbox.h',
  'libavutil/hwcontext_vulkan.h',
];

void main() {
  Config;
  final glob = Glob('**/*.h');
  final files = glob.listSync(root: root).whereType<File>();
  // final headerFiles = <Library, List<String>>{};
  final headerFiles = <String>[];
  for (final file in files) {
    if (exclude.any(file.path.endsWith)) {
      continue;
    }
    // final lib = Library.fromDir(path.basename(file.parent.path));
    // headerFiles.putIfAbsent(lib, () => []).add(file.path);
    headerFiles.add(file.path);
  }

  Directory('config')
    ..deleteSync(recursive: true)
    ..createSync(recursive: true);

  Glob('lib/src/*.g.dart').listSync().forEach((f) => f.deleteSync());

  _generate(headerFiles);

  // for (final lib in headerFiles.keys) {
  //   _generate(lib, headerFiles[lib]!);
  // }
}

// void _generate(Library lib, List<String> files) {
void _generate(List<String> files) {
  // final dir = lib.dir;
  // final className = lib.className;

  final ffigenConfig = '''
name: 'FFmpeg'

output: '../lib/src/ffmpeg.g.dart'

headers:
  entry-points:
${files.map((file) => "    - '../$file'").join('\n')}

compiler-opts:
  - '-I$root'

llvm-path:
  - '/Library/Developer/CommandLineTools/usr/lib/'

preamble: |
  // ignore_for_file: type=lint, doc_directive_unknown, unused_field, unused_element

silence-enum-warning: true
''';

  final configFile = File('config/ffmpeg.yaml');
  configFile.writeAsStringSync(ffigenConfig);

  print('ffmpeg.yaml generated successfully.');

  final config = YamlConfig.fromFile(configFile);
  gen.run(config);
}
