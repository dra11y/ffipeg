import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:ffigen/ffigen.dart';
import 'package:ffipeg/ffipeg.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as path;
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';
import 'dart_object_extension.dart';

const ffmpegGenAnnotation = TypeChecker.fromRuntime(FFmpegGen);

class FFmpegBuilder extends Builder {
  final BuilderOptions options;

  FFmpegBuilder(this.options);

  @override
  Future<void> build(BuildStep buildStep) async {
    print('buildStep: $buildStep');
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    final library = await buildStep.resolver.libraryFor(buildStep.inputId);
    final annotation = ffmpegGenAnnotation.firstAnnotationOf(library);
    if (annotation == null) {
      print('ANNOTATION NOT FOUND: $library');
      return;
    }

    final searchPaths = annotation.getStringList('searchPaths');
    final libraries = annotation.getEnumList('libraries', FFmpegLibrary.values);
    final functions = annotation.getIncludeExclude('functions');
    final structs = annotation.getIncludeExclude('structs');
    final enums = annotation.getIncludeExclude('enums');
    final libraryName = annotation.getStringValue('libraryName')!;
    final libclangDylib = annotation.getStringValue('libclangDylib');
    final excludeHeaders = annotation.getStringList('excludeHeaders');

    final (includePath, headers) =
        searchForFFmpegHeaders(searchPaths, libraries, excludeHeaders);

    final tempDir = await Directory.systemTemp.createTemp('ffipeg_builder');
    final tempOutputFile = File(path.join(tempDir.path,
        'ffigen_output_${DateTime.now().millisecondsSinceEpoch}.dart'));

    Map<String, dynamic> includeExclude(FFIncludeExclude includeExclude) {
      return switch (includeExclude) {
        FFInclude include => {'include': include.include},
        FFExclude exclude => {'exclude': exclude.exclude},
      };
    }

    final configMap = <String, dynamic>{
      'silence-enum-warning': true,
      'preamble': '''
        // ignore_for_file: type=lint, doc_directive_unknown, unused_field, unused_element
      ''',
      'llvm-path': ['/Library/Developer/CommandLineTools/usr/lib/'],
      'name': libraryName,
      'output': tempOutputFile.path,
      'compiler-opts': ['-I$includePath'],
      'headers': {
        'entry-points': headers,
      },
      'functions': includeExclude(functions),
      'structs': includeExclude(structs),
      'enums': includeExclude(enums),
      if (libclangDylib != null) 'libclangDylib': libclangDylib,
    };

    final config = YamlConfig.fromYaml(YamlMap.wrap(configMap));

    try {
      final generatedContent = await runFfiGenInIsolate(config);
      final outputId = buildStep.inputId.changeExtension('.g.dart');
      await buildStep.writeAsString(outputId, generatedContent);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  /// Searches for FFmpeg headers in the provided searchPaths.
  /// Returns a list of all *.h file paths found within the `lib*` subdirectories.
  (String, List<String>) searchForFFmpegHeaders(
    List<String> searchPaths,
    List<FFmpegLibrary> libraries,
    List<String> excludeHeaders,
  ) {
    if (searchPaths.isEmpty) {
      searchPaths.add('ffmpeg-headers/current');
    }

    for (final headerPath in searchPaths) {
      if (Directory(headerPath).existsSync()) {
        final foundHeaders = <String>[];

        // Iterate over each FFmpegLibrary to find headers in their respective subfolders
        for (final lib in libraries) {
          final libDir = '$headerPath/${lib.dir}';

          if (Directory(libDir).existsSync()) {
            // Glob all *.h files in the libDir folder
            final headerFiles =
                Glob('$libDir/*.h').listSync().whereType<File>();

            if (headerFiles.isNotEmpty) {
              foundHeaders.addAll(headerFiles
                  .map((file) => file.path)
                  .where((p) => !excludeHeaders.any(p.endsWith)));
            }
          }
        }

        // If headers were found, return the list
        if (foundHeaders.isNotEmpty) {
          print('Found FFmpeg headers: $foundHeaders');
          return (headerPath, foundHeaders);
        }
      }
    }

    // Throw an exception if no headers are found
    throw Exception(
        'FFmpeg headers not found in any of the provided search paths: $searchPaths');
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.g.dart']
      };
}

/// Runs FfiGen in a separate isolate to avoid logging conflicts and returns the generated content.
Future<String> runFfiGenInIsolate(YamlConfig config) async {
  final receivePort = ReceivePort();

  // Spawn an isolate to run FfiGen
  await Isolate.spawn(_ffiGenIsolate, [receivePort.sendPort, config]);

  // Wait for the result from the isolate
  return await receivePort.first as String;
}

/// The entry point for the isolate running FfiGen.
void _ffiGenIsolate(List<dynamic> args) async {
  final sendPort = args[0] as SendPort;
  final config = args[1] as YamlConfig;
  final ffiGen = FfiGen();

  try {
    // Run FfiGen and read the generated file
    ffiGen.run(config);
    final outputFile = File(config.output.toFilePath());
    final generatedContent = await outputFile.readAsString();

    // Send the result back to the main isolate
    sendPort.send(generatedContent);
  } catch (e, stacktrace) {
    // In case of an error, send an error message back
    sendPort.send('Error: $e\n$stacktrace');
  }
}
